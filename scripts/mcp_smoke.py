#!/usr/bin/env python3

import json
import os
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
MCP_EXECUTABLE = REPO_ROOT / ".build" / "debug" / "lmnh-mcp"
EXPECTED_TOOLS = {
    "macos_permission_status",
    "macos_open_app",
    "macos_list_apps",
    "macos_list_windows",
    "macos_snapshot",
    "macos_get_element",
    "macos_find_elements",
    "macos_get_screenshot",
    "macos_set_virtual_cursor",
    "macos_hide_virtual_cursor",
    "macos_perform_action",
    "macos_click",
    "macos_type_text",
}


def encode_request(message):
    return json.dumps(message, separators=(",", ":")) + "\n"


def parse_messages(raw):
    messages = []
    index = 0
    while index < len(raw):
        if raw.startswith(b"Content-Length:", index):
            header_end = raw.find(b"\r\n\r\n", index)
            separator_length = 4
            if header_end == -1:
                header_end = raw.find(b"\n\n", index)
                separator_length = 2
            if header_end == -1:
                raise RuntimeError(f"Missing MCP header terminator at byte {index}")

            header = raw[index:header_end].decode("utf-8")
            length = int(header.split(":", 1)[1].strip())
            start = header_end + separator_length
            body = raw[start : start + length]
            messages.append(json.loads(body))
            index = start + length
        elif raw[index : index + 1].isspace():
            index += 1
        else:
            line_end = raw.find(b"\n", index)
            if line_end == -1:
                line_end = len(raw)
            line = raw[index:line_end].strip()
            if line:
                messages.append(json.loads(line))
            index = line_end + 1
    return messages


def response_by_id(messages, request_id):
    for message in messages:
        if message.get("id") == request_id:
            return message
    raise AssertionError(f"Missing response id {request_id}")


def tool_text(response):
    content = response.get("result", {}).get("content", [])
    return content[0].get("text", "") if content else ""


def main():
    if not MCP_EXECUTABLE.exists():
        raise SystemExit(f"Missing {MCP_EXECUTABLE}; run swift build first")

    requests = [
        {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": "2025-06-18",
                "capabilities": {},
                "clientInfo": {"name": "lmnh-smoke", "version": "0"},
            },
        },
        {"jsonrpc": "2.0", "method": "notifications/initialized"},
        {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
        {
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": {"name": "macos_permission_status", "arguments": {}},
        },
        {
            "jsonrpc": "2.0",
            "id": 4,
            "method": "tools/call",
            "params": {"name": "macos_list_apps", "arguments": {"include_background": False}},
        },
        {
            "jsonrpc": "2.0",
            "id": 5,
        "method": "tools/call",
        "params": {"name": "macos_list_windows", "arguments": {}},
    },
    {
        "jsonrpc": "2.0",
        "id": 6,
            "method": "tools/call",
            "params": {
                "name": "macos_set_virtual_cursor",
                "arguments": {
                    "x": 100,
                    "y": 100,
                    "state": "aiming",
                    "label": "smoke test",
                    "session_id": "smoke",
                },
            },
        },
        {
            "jsonrpc": "2.0",
        "id": 7,
            "method": "tools/call",
            "params": {
                "name": "macos_snapshot",
                "arguments": {
                    "mode": "summary",
                    "include_screenshot": False,
                    "include_ocr": False,
                    "max_depth": 2,
                    "max_nodes": 50,
                },
            },
        },
        {
            "jsonrpc": "2.0",
        "id": 8,
            "method": "tools/call",
            "params": {
                "name": "macos_click",
                "arguments": {
                    "x": -1,
                    "y": -1,
                    "coordinate_space": "global_display_points",
                },
            },
        },
        {
            "jsonrpc": "2.0",
            "id": 9,
            "method": "tools/call",
            "params": {
                "name": "macos_type_text",
                "arguments": {
                    "text": "smoke",
                    "method": "paste",
                },
            },
        },
    ]

    env = dict(**os.environ, LMNH_OVERLAY_RENDERER="headless")
    process = subprocess.run(
        [str(MCP_EXECUTABLE)],
        input="".join(encode_request(request) for request in requests).encode("utf-8"),
        capture_output=True,
        timeout=15,
        cwd=REPO_ROOT,
        env=env,
    )
    if process.returncode != 0:
        sys.stderr.write(process.stderr.decode("utf-8", errors="replace"))
        raise SystemExit(process.returncode)

    messages = parse_messages(process.stdout)
    tools_response = response_by_id(messages, 2)
    tool_names = {tool["name"] for tool in tools_response["result"]["tools"]}
    missing_tools = sorted(EXPECTED_TOOLS - tool_names)
    if missing_tools:
        raise AssertionError(f"Missing MCP tools: {missing_tools}")

    permission_text = tool_text(response_by_id(messages, 3))
    apps_text = tool_text(response_by_id(messages, 4))
    windows_text = tool_text(response_by_id(messages, 5))
    cursor_response = response_by_id(messages, 6)
    snapshot_response = response_by_id(messages, 7)
    click_response = response_by_id(messages, 8)
    type_response = response_by_id(messages, 9)

    if "Accessibility:" not in permission_text:
        raise AssertionError(f"Unexpected permission response: {permission_text}")
    if "Listed" not in apps_text:
        raise AssertionError(f"Unexpected app list response: {apps_text}")
    if "Listed" not in windows_text:
        raise AssertionError(f"Unexpected window list response: {windows_text}")

    cursor = cursor_response["result"]["structuredContent"]["virtual_cursor"]
    if cursor["real_mouse_moved"]:
        raise AssertionError("Virtual cursor smoke moved the real mouse")

    snapshot_result = snapshot_response["result"]
    if "structuredContent" in snapshot_result:
        raise AssertionError("Snapshot should be plaintext-only and must not include structuredContent")
    snapshot_text = tool_text(snapshot_response)
    if not snapshot_text.startswith("<macos_snapshot"):
        raise AssertionError("Snapshot did not include XML-like LLM text")
    if "accessibilityTree" in snapshot_text or '"applications"' in snapshot_text:
        raise AssertionError("Snapshot leaked raw verbose fields")

    click_result = click_response["result"]["structuredContent"]["action"]
    if click_result["real_mouse_moved"]:
        raise AssertionError("Focusless click failure path moved the real mouse")
    if click_result["layer"] != "semantic_ax_at_position":
        raise AssertionError(f"Unexpected click layer: {click_result['layer']}")
    if "frontmostBefore" in click_result or "fallbacksAttempted" in click_result:
        raise AssertionError("Click result leaked verbose internal action fields")

    type_tool = next(tool for tool in tools_response["result"]["tools"] if tool["name"] == "macos_type_text")
    type_schema = type_tool["inputSchema"]["properties"]
    if "mode" not in type_schema:
        raise AssertionError("macos_type_text schema does not expose mutation mode")
    if sorted(type_schema["mode"]["enum"]) != ["append", "replace", "selection"]:
        raise AssertionError(f"Unexpected type modes: {type_schema['mode']['enum']}")

    type_result = type_response["result"]
    if not type_result["isError"]:
        raise AssertionError("paste fallback smoke should be explicitly unsupported")
    type_structured = type_result["structuredContent"]
    if type_structured["fallback_policy"] != "keyboard_and_paste_not_attempted_to_preserve_focus":
        raise AssertionError(f"Unexpected type fallback policy: {type_structured}")
    if type_structured["real_mouse_moved"]:
        raise AssertionError("Unsupported text fallback moved the real mouse")

    open_tool = next(tool for tool in tools_response["result"]["tools"] if tool["name"] == "macos_open_app")
    open_schema = open_tool["inputSchema"]["properties"]
    for key in ("bundle_id", "app_path", "background", "restore_focus"):
        if key not in open_schema:
            raise AssertionError(f"macos_open_app schema missing {key}")

    print("MCP smoke passed")
    print(f"tools={len(tool_names)} snapshot_chars={len(snapshot_text)}")
    print(permission_text)


if __name__ == "__main__":
    main()
