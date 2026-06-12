#!/usr/bin/env bash

set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
log_dir="$repo_root/.lmnh-agent/logs"
log_file="$log_dir/verify.log"

mkdir -p "$log_dir"
cd "$repo_root" || exit 1

status=0

run_step() {
  printf '\n$'
  printf ' %q' "$@"
  printf '\n'

  "$@"
  step_status=$?
  if [ "$step_status" -ne 0 ]; then
    printf 'Command failed with exit status %s\n' "$step_status"
    if [ "$status" -eq 0 ]; then
      status="$step_status"
    fi
  fi
}

{
  printf 'Look Mum No Hands verification started at %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf 'Repository: %s\n' "$repo_root"
  run_step swift --version
  run_step python3 -m json.tool .cursor/mcp.json
  run_step python3 -c "import pathlib,tomllib; tomllib.loads(pathlib.Path('.codex/config.toml').read_text())"
  run_step swift test
  run_step swift build
  run_step python3 scripts/mcp_smoke.py
  run_step python3 scripts/screenshot_smoke.py
  run_step python3 scripts/http_mcp_smoke.py
  printf '\nLook Mum No Hands verification finished at %s with status %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$status"
  exit "$status"
} 2>&1 | tee "$log_file"

exit "${PIPESTATUS[0]}"
