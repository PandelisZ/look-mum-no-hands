---
name: look-mum-no-hands
description: Inspect and control the local macOS desktop UI through the Look Mum No Hands (LMNH) MCP server. Use whenever the user wants to read on-screen UI state, find or click a macOS UI element, type text, take screenshots, or operate an app without moving the real mouse. Prefer these MCP tools over osascript, AppleScript, System Events, shell keyboard events, or ad hoc app scripting for any UI control task.
---

# Look Mum No Hands

LMNH exposes a Swift MCP server that drives macOS via the Accessibility (AX) APIs and a virtual cursor overlay, so UI control happens without hijacking the real mouse pointer.

## When to use

Trigger this skill when the user asks to:
- inspect what is on screen (snapshot, screenshot, list windows/apps)
- find a specific UI element (button, menu item, text field) by label or role
- click, press, or perform an accessibility action on an element
- type text into the focused field
- show, move, or hide the virtual cursor overlay
- open an app and operate it

Do **not** fall back to `osascript`, `AppleScript`, `System Events`, shell keyboard events (`cliclick`, raw CGEvent scripting), or app-specific scripting bridges for UI control. Use the MCP tools below instead.

## Tools (MCP server `look-mum-no-hands`)

- `macos_permission_status` — verify Accessibility / Screen Recording permissions before doing anything else.
- `macos_list_apps` / `macos_list_windows` — enumerate running apps and their windows.
- `macos_open_app` — launch or focus an app by bundle id or name.
- `macos_snapshot` — structured AX tree of the frontmost (or specified) window. Cheap; use this first to locate elements.
- `macos_get_screenshot` — pixel screenshot when AX is not enough (e.g. canvas content).
- `macos_find_elements` / `macos_get_element` — search the AX tree for elements matching role / label / identifier.
- `macos_perform_action` — perform a named AX action (e.g. `AXPress`, `AXShowMenu`) on an element.
- `macos_click` — click at a point or on a resolved element. Uses the virtual cursor, not the real mouse.
- `macos_type_text` — synthesize keystrokes into the focused field.
- `macos_set_virtual_cursor` / `macos_hide_virtual_cursor` — control the on-screen virtual pointer overlay.

## Recommended workflow

1. Call `macos_permission_status`. If permissions are missing, surface the exact toggle the user must enable in System Settings → Privacy & Security; do not try to work around it.
2. Use `macos_list_apps` / `macos_open_app` to make sure the target app is frontmost.
3. Call `macos_snapshot` (or `macos_find_elements`) to locate the target element by role + label rather than by raw coordinates.
4. Prefer `macos_perform_action` (`AXPress` etc.) over `macos_click` whenever the element exposes an AX action — it is more reliable and does not depend on layout.
5. Fall back to `macos_click` with a resolved element handle if no AX action is available; only use raw screen coordinates as a last resort.
6. For text entry, focus the field first (via action or click) and then call `macos_type_text`.
7. After a state-changing action, re-snapshot to confirm the UI changed as expected before chaining the next step.

## Safety

- Never operate destructive UI (delete confirmations, send buttons, payment flows) without confirming with the user first.
- If the AX tree is empty or actions silently fail, re-check `macos_permission_status` before retrying — the user likely needs to grant Accessibility to the host app.
