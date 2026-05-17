---
name: look-mum-no-hands
description: Use when the user asks to use Look Mum No Hands, LMNH, or its macOS MCP tools to inspect the desktop, list apps or windows, capture accessibility snapshots, find UI elements, show a virtual cursor, click, press accessibility actions, type text, or check macOS automation permissions.
---

# Look Mum No Hands

Use the `look-mum-no-hands` MCP server for local macOS UI inspection and controlled desktop automation. Prefer semantic accessibility actions and virtual cursor targeting before actions that may move or affect the real desktop.

## Hard rule: do not bypass LMNH

When a task involves opening, inspecting, clicking, pressing, typing into, or otherwise operating macOS app UI, use the LMNH MCP tools. Do **not** use `open`, `osascript`, AppleScript, `System Events`, GUI scripting, shell-driven keyboard events, or ad hoc app scripting to operate UI unless the user explicitly asks for that specific mechanism or LMNH reports that the required capability is unsupported.

If a model is tempted to run `open -a ...` or `osascript -e 'tell application "System Events" ...'`, stop and use `macos_open_app`, `macos_snapshot`, `macos_find_elements`, `macos_perform_action`, `macos_click`, or `macos_type_text` instead.

## Startup checks

1. If tools are unavailable, confirm the plugin MCP server is installed and enabled.
2. Check permissions first with `macos_permission_status` when a task depends on Accessibility, Screen Recording, or input control.
3. If the MCP server fails to start, run the plugin launcher from the plugin root:

```bash
bash ./scripts/run-lmnh-mcp.sh
```

Set `LMNH_REPO_ROOT=/path/to/look-mum-no-hands` if the installed plugin cache cannot find the Swift package checkout.

## Inspection workflow

1. Use `macos_list_apps` and `macos_list_windows` to understand the visible desktop.
2. Use `macos_snapshot` with `mode: "summary"` for orientation, then `standard` or `full` only when more accessibility detail is needed.
3. Use `macos_find_elements` against the returned `snapshot_id` to find text, labels, roles, or visible elements.
4. Use `macos_get_element` before acting if an element may have changed since the snapshot.

## Action workflow

1. Use `macos_open_app` to open apps. Set `background: true` and `restore_focus: true` unless the user explicitly wants the app focused.
2. Use `macos_set_virtual_cursor` to show the intended target without moving the real mouse.
3. Prefer `macos_perform_action` with `action: "AXPress"` for known accessibility elements.
4. Use `macos_click` with `snapshot_id` and `element_id` when semantic press is unavailable; use coordinates only after a fresh snapshot confirms them.
5. Use `macos_type_text` with focusless AX modes for text fields when possible. Do not use AppleScript, `osascript`, `System Events`, paste, or keystrokes as the first path.
6. Use `macos_hide_virtual_cursor` after a workflow if visual cursors are no longer useful.

## Tool map

- `macos_permission_status`: report Accessibility and Screen Recording status.
- `macos_open_app`: open an app with background-launch intent and focus restoration.
- `macos_list_apps`: list running apps, optionally including background agents.
- `macos_list_windows`: list visible windows and geometry.
- `macos_snapshot`: capture applications, windows, accessibility elements, and virtual cursors.
- `macos_find_elements`: search a snapshot by query, role, visibility, and limit.
- `macos_get_element`: fetch one element from a snapshot.
- `macos_get_screenshot`: return screenshot metadata or image content when available.
- `macos_set_virtual_cursor`: move a visual-only cursor to coordinates or an element.
- `macos_hide_virtual_cursor`: hide one cursor, a session's cursors, or all cursors.
- `macos_perform_action`: run an accessibility action such as `AXPress`.
- `macos_click`: perform a click-like action without moving the real mouse when possible.
- `macos_type_text`: set, paste, or type text into a target.
