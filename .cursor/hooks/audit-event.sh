#!/usr/bin/env bash

# Project audit hook for Cursor agent activity. It must never block normal work.
set +e

event="${1:-unknown}"
repo_root="$(pwd)"
log_dir="${repo_root}/.lmnh-agent/logs"
log_file="${log_dir}/hooks.jsonl"
input="$(cat 2>/dev/null || true)"

mkdir -p "$log_dir" 2>/dev/null || true

write_with_python() {
  command -v python3 >/dev/null 2>&1 || return 1

  tmp_file="$(mktemp "${TMPDIR:-/tmp}/lmnh-hook.XXXXXX" 2>/dev/null)" || return 1
  printf '%s' "$input" >"$tmp_file" 2>/dev/null || {
    rm -f "$tmp_file" 2>/dev/null || true
    return 1
  }

  EVENT_NAME="$event" INPUT_FILE="$tmp_file" python3 - <<'PY' >>"$log_file" 2>/dev/null
import datetime
import json
import os
import re

SENSITIVE_KEY_RE = re.compile(r"(password|passwd|passphrase|secret|token|api[_-]?key|authorization|cookie|credential)", re.I)
SENSITIVE_VALUE_RE = re.compile(
    r"(?i)\b(password|passwd|passphrase|secret|token|api[_-]?key|authorization|bearer)\b"
    r"(\s*[:=]\s*)([^\s,;]+)"
)
PRIVATE_KEY_RE = re.compile(
    r"-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----",
    re.S,
)
MAX_STRING_LENGTH = 8192
MAX_LIST_ITEMS = 50
MAX_DICT_ITEMS = 100


def scrub_string(value):
    value = PRIVATE_KEY_RE.sub("<redacted-private-key>", value)
    value = SENSITIVE_VALUE_RE.sub(lambda match: f"{match.group(1)}{match.group(2)}<redacted>", value)
    if len(value) > MAX_STRING_LENGTH:
        return value[:MAX_STRING_LENGTH] + "...<truncated>"
    return value


def scrub(value):
    if isinstance(value, dict):
        clean = {}
        for index, (key, item) in enumerate(value.items()):
            if index >= MAX_DICT_ITEMS:
                clean["<truncated>"] = f"{len(value) - MAX_DICT_ITEMS} additional keys omitted"
                break
            key_text = str(key)
            clean[key_text] = "<redacted>" if SENSITIVE_KEY_RE.search(key_text) else scrub(item)
        return clean
    if isinstance(value, list):
        clean = [scrub(item) for item in value[:MAX_LIST_ITEMS]]
        if len(value) > MAX_LIST_ITEMS:
            clean.append(f"<truncated {len(value) - MAX_LIST_ITEMS} additional items>")
        return clean
    if isinstance(value, str):
        return scrub_string(value)
    return value


def find_shell_command(payload):
    if not isinstance(payload, dict):
        return None
    for key in ("command", "shell_command", "cmd"):
        value = payload.get(key)
        if isinstance(value, str):
            return scrub_string(value)
    tool_input = payload.get("tool_input") or payload.get("input")
    if isinstance(tool_input, dict):
        value = tool_input.get("command")
        if isinstance(value, str):
            return scrub_string(value)
    return None


def find_file_path(payload):
    if not isinstance(payload, dict):
        return None
    for key in ("path", "file", "file_path", "target_file", "targetFile"):
        value = payload.get(key)
        if isinstance(value, str):
            return value
    tool_input = payload.get("tool_input") or payload.get("input")
    if isinstance(tool_input, dict):
        for key in ("path", "file", "file_path", "target_file", "targetFile"):
            value = tool_input.get(key)
            if isinstance(value, str):
                return value
    return None


raw = ""
input_file = os.environ.get("INPUT_FILE")
if input_file:
    try:
        with open(input_file, "r", encoding="utf-8", errors="replace") as handle:
            raw = handle.read()
    except OSError as error:
        raw = json.dumps({"read_error": str(error)})

try:
    payload = json.loads(raw) if raw.strip() else {}
except Exception as error:
    payload = {
        "_parse_error": str(error),
        "raw": scrub_string(raw),
    }

entry = {
    "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z"),
    "schema": "lmnh.cursor_hook_audit.v1",
    "event": os.environ.get("EVENT_NAME", "unknown"),
    "cwd": os.getcwd(),
    "command": find_shell_command(payload),
    "file_path": find_file_path(payload),
    "input": scrub(payload),
}

print(json.dumps(entry, sort_keys=True, separators=(",", ":")))
PY

  rm -f "$tmp_file" 2>/dev/null || true
}

write_fallback_event() {
  timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || printf 'unknown')"
  printf '{"timestamp":"%s","schema":"lmnh.cursor_hook_audit.v1","event":"%s","cwd":"%s","input":{"warning":"python3 unavailable; hook input omitted"}}\n' \
    "$timestamp" "$event" "$repo_root" >>"$log_file" 2>/dev/null || true
}

write_with_python || write_fallback_event

case "$event" in
  beforeShellExecution)
    printf '{"permission":"allow"}\n'
    ;;
  *)
    printf '{}\n'
    ;;
esac

exit 0
