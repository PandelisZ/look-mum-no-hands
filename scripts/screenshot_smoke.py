#!/usr/bin/env python3
"""Live smoke test for macos_get_screenshot through the stdio MCP server."""

import base64
import json
import os
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
MCP_EXECUTABLE = REPO_ROOT / ".build" / "debug" / "lmnh-mcp"


def encode_request(message):
    return json.dumps(message, separators=(",", ":")) + "\n"


def parse_messages(raw):
    messages = []
    for line in raw.splitlines():
        line = line.strip()
        if line:
            messages.append(json.loads(line))
    return messages


def response_by_id(messages, request_id):
    for message in messages:
        if message.get("id") == request_id:
            return message
    raise AssertionError(f"Missing response id {request_id}")


def main():
    if not MCP_EXECUTABLE.exists():
        raise SystemExit(f"Missing {MCP_EXECUTABLE}; run swift build first")

    out_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("/tmp/lmnh-screenshot-smoke")
    out_dir.mkdir(parents=True, exist_ok=True)

    requests = [
        {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": "2025-06-18",
                "capabilities": {},
                "clientInfo": {"name": "lmnh-screenshot-smoke", "version": "0"},
            },
        },
        {"jsonrpc": "2.0", "method": "notifications/initialized"},
        {
            "jsonrpc": "2.0",
            "id": 2,
            "method": "tools/call",
            "params": {
                "name": "macos_get_screenshot",
                "arguments": {"target": "frontmost_window", "max_width": 1200},
            },
        },
        {
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": {
                "name": "macos_get_screenshot",
                "arguments": {"target": "display", "max_width": 1200, "format": "jpeg"},
            },
        },
        {
            "jsonrpc": "2.0",
            "id": 4,
            "method": "tools/call",
            "params": {
                "name": "macos_get_screenshot",
                "arguments": {"target": "element"},
            },
        },
    ]

    env = dict(**os.environ, LMNH_OVERLAY_RENDERER="headless")
    process = subprocess.run(
        [str(MCP_EXECUTABLE)],
        input="".join(encode_request(request) for request in requests).encode("utf-8"),
        capture_output=True,
        timeout=30,
        cwd=REPO_ROOT,
        env=env,
    )
    if process.returncode != 0:
        sys.stderr.write(process.stderr.decode("utf-8", errors="replace"))
        raise SystemExit(process.returncode)

    messages = parse_messages(process.stdout.decode("utf-8"))

    for request_id, name, expect_format in ((2, "frontmost_window", "png"), (3, "display", "jpeg")):
        result = response_by_id(messages, request_id)["result"]
        if result.get("isError"):
            raise AssertionError(f"{name} screenshot failed: {result['content'][0].get('text')}")
        image = next(item for item in result["content"] if item["type"] == "image")
        if image["mimeType"] != f"image/{expect_format}":
            raise AssertionError(f"{name} unexpected mime type {image['mimeType']}")
        metadata = result["structuredContent"]["screenshot"]
        if metadata["pixel_width"] < 1 or metadata["pixel_height"] < 1:
            raise AssertionError(f"{name} returned an empty image: {metadata}")
        if metadata["pixel_width"] > 1200:
            raise AssertionError(f"{name} ignored max_width: {metadata}")
        path = out_dir / f"{name}.{expect_format}"
        path.write_bytes(base64.b64decode(image["data"]))
        print(f"{name}: {metadata['pixel_width']}x{metadata['pixel_height']} -> {path}")

    invalid = response_by_id(messages, 4)["result"]
    if not invalid.get("isError"):
        raise AssertionError("element target without ids should report invalid arguments")
    print(f"element-without-ids correctly errored: {invalid['content'][0]['text']}")
    print("Screenshot smoke passed")


if __name__ == "__main__":
    main()
