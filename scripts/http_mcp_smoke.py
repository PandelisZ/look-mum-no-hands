#!/usr/bin/env python3

import json
import os
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
HTTP_EXECUTABLE = REPO_ROOT / ".build" / "debug" / "lmnh-mcp-http"


def reserve_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def wait_for_port(port, process):
    deadline = time.time() + 10
    while time.time() < deadline:
        if process.poll() is not None:
            stderr = process.stderr.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"HTTP MCP server exited early with {process.returncode}: {stderr}")
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.25):
                return
        except OSError:
            time.sleep(0.1)
    raise TimeoutError(f"Timed out waiting for HTTP MCP server on port {port}")


def rpc(url, message):
    request = urllib.request.Request(
        url,
        data=json.dumps(message, separators=(",", ":")).encode("utf-8"),
        headers={"Content-Type": "application/json", "Accept": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=10) as response:
        return json.loads(response.read())


def main():
    if not HTTP_EXECUTABLE.exists():
        raise SystemExit(f"Missing {HTTP_EXECUTABLE}; run swift build first")

    port = reserve_port()
    url = f"http://127.0.0.1:{port}/mcp"
    env = dict(**os.environ, LMNH_OVERLAY_RENDERER="headless")
    process = subprocess.Popen(
        [str(HTTP_EXECUTABLE), "--port", str(port)],
        cwd=REPO_ROOT,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    try:
        wait_for_port(port, process)

        initialize = rpc(
            url,
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "protocolVersion": "2025-06-18",
                    "capabilities": {},
                    "clientInfo": {"name": "lmnh-http-smoke", "version": "0"},
                },
            },
        )
        tools = rpc(url, {"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
        permission = rpc(
            url,
            {
                "jsonrpc": "2.0",
                "id": 3,
                "method": "tools/call",
                "params": {"name": "macos_permission_status", "arguments": {}},
            },
        )

        if initialize["result"]["serverInfo"]["name"] != "look-mum-no-hands":
            raise AssertionError(f"Unexpected initialize response: {initialize}")

        tool_names = {tool["name"] for tool in tools["result"]["tools"]}
        if "macos_type_text" not in tool_names:
            raise AssertionError(f"HTTP tools/list missed macos_type_text: {tool_names}")

        permission_text = permission["result"]["content"][0]["text"]
        if "Accessibility:" not in permission_text:
            raise AssertionError(f"Unexpected HTTP tool response: {permission_text}")

        print("HTTP MCP smoke passed")
        print(f"url={url} tools={len(tool_names)}")
        print(permission_text)
    except urllib.error.HTTPError as error:
        sys.stderr.write(error.read().decode("utf-8", errors="replace"))
        raise
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)


if __name__ == "__main__":
    main()
