#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
INSTALLER="$ROOT/install.sh"

assert_file() {
  local path="$1"
  local message="$2"

  if [[ ! -f "$path" ]]; then
    printf 'Assertion failed: %s\n' "$message" >&2
    exit 1
  fi
}

assert_executable() {
  local path="$1"
  local message="$2"

  if [[ ! -x "$path" ]]; then
    printf 'Assertion failed: %s\n' "$message" >&2
    exit 1
  fi
}

assert_contains() {
  local text="$1"
  local needle="$2"
  local message="$3"

  if [[ "$text" != *"$needle"* ]]; then
    printf 'Assertion failed: %s\nMissing: %s\n' "$message" "$needle" >&2
    exit 1
  fi
}

assert_not_file() {
  local path="$1"
  local message="$2"

  if [[ -f "$path" ]]; then
    printf 'Assertion failed: %s\nUnexpected file: %s\n' "$message" "$path" >&2
    exit 1
  fi
}

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

BIN_DIR="$TMP_ROOT/bin"
DATA_DIR="$TMP_ROOT/share/reposeed"

assert_file "$INSTALLER" "install.sh must exist."
bash -n "$INSTALLER"

bash "$INSTALLER" --bin-dir "$BIN_DIR" --data-dir "$DATA_DIR"

assert_executable "$BIN_DIR/reposeed" "Installer should create an executable reposeed wrapper."
assert_executable "$DATA_DIR/new-project.sh" "Installer should copy new-project.sh as executable."
assert_file "$DATA_DIR/.reposeed-install" "Installer should write a managed-install marker."
assert_file "$DATA_DIR/templates/agents/base.md" "Installer should copy templates."

help_text="$("$BIN_DIR/reposeed" --help)"
assert_contains "$help_text" "Usage: new-project.sh [options]" "Installed command should invoke the scaffolder."

printf 'locally modified\n' >"$DATA_DIR/new-project.sh"
printf 'stale\n' >"$DATA_DIR/templates/stale-template.txt"
bash "$INSTALLER" --bin-dir "$BIN_DIR" --data-dir "$DATA_DIR"
assert_not_file "$DATA_DIR/templates/stale-template.txt" "Reinstall should remove stale managed files."
reinstalled_script="$(<"$DATA_DIR/new-project.sh")"
assert_contains "$reinstalled_script" 'Usage: new-project.sh [options]' "Reinstall should refresh managed script files."

CONFLICT_DIR="$TMP_ROOT/conflict"
mkdir -p "$CONFLICT_DIR"
printf 'user-owned\n' >"$CONFLICT_DIR/file.txt"
if bash "$INSTALLER" --bin-dir "$BIN_DIR" --data-dir "$CONFLICT_DIR" >"$TMP_ROOT/conflict.out" 2>&1; then
  printf 'Assertion failed: Installer should refuse a non-empty unmanaged data directory.\n' >&2
  exit 1
fi

RELATIVE_RUN_DIR="$TMP_ROOT/relative-run"
mkdir -p "$RELATIVE_RUN_DIR"
pushd "$RELATIVE_RUN_DIR" >/dev/null
bash "$INSTALLER" --bin-dir relative-bin --data-dir relative-data >/dev/null
popd >/dev/null

pushd / >/dev/null
relative_help_text="$("$RELATIVE_RUN_DIR/relative-bin/reposeed" --help)"
popd >/dev/null
assert_contains "$relative_help_text" "Usage: new-project.sh [options]" "Relative install paths should still work from another directory."

printf 'Install tests passed.\n'
