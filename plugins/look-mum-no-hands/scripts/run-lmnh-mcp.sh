#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

find_repo_root() {
  local candidate

  if [[ -n "${LMNH_REPO_ROOT:-}" && -f "${LMNH_REPO_ROOT}/Package.swift" ]]; then
    printf '%s\n' "${LMNH_REPO_ROOT}"
    return 0
  fi

  candidate="${SCRIPT_DIR}"
  while [[ "${candidate}" != "/" ]]; do
    if [[ -f "${candidate}/Package.swift" && -d "${candidate}/Sources/LMNHMCP" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
    candidate="$(dirname "${candidate}")"
  done

  candidate="/Users/pz/w/look-mum-no-hands"
  if [[ -f "${candidate}/Package.swift" && -d "${candidate}/Sources/LMNHMCP" ]]; then
    printf '%s\n' "${candidate}"
    return 0
  fi

  return 1
}

REPO_ROOT="$(find_repo_root || true)"
if [[ -z "${REPO_ROOT}" ]]; then
  echo "Unable to find look-mum-no-hands repo. Set LMNH_REPO_ROOT to the checkout containing Package.swift." >&2
  exit 1
fi

cd "${REPO_ROOT}"

EXECUTABLE="${REPO_ROOT}/.build/debug/lmnh-mcp"
if [[ ! -x "${EXECUTABLE}" ]]; then
  swift build --product lmnh-mcp >&2
fi

exec "${EXECUTABLE}"
