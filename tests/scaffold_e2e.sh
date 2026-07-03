#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCAFFOLDER="$ROOT/new-project.sh"

require_command() {
  local command_name="$1"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Required command not found: %s\n' "$command_name" >&2
    exit 127
  fi
}

run_project_checks() {
  local project_dir="$1"

  pushd "$project_dir" >/dev/null
  ./scripts/check.sh
  ./scripts/fix.sh
  ./scripts/check.sh
  popd >/dev/null
}

assert_file_contains() {
  local file_path="$1"
  local expected="$2"

  if [[ "$(<"$file_path")" != *"$expected"* ]]; then
    printf 'Expected %s to contain: %s\n' "$file_path" "$expected" >&2
    exit 1
  fi
}

assert_pyright_venv_config() {
  local profile="$1"
  local project_dir="$2"
  local pyproject_path="$project_dir/pyproject.toml"

  if [[ "$profile" == "web" || "$profile" == "game" ]]; then
    pyproject_path="$project_dir/backend/pyproject.toml"
  fi

  assert_file_contains "$pyproject_path" 'venvPath = "."'
  assert_file_contains "$pyproject_path" 'venv = ".venv"'
}

run_scaffold_case() {
  local profile="$1"
  local name="$2"
  local project_dir="$TMP_ROOT/$name"

  mkdir -p "$project_dir"
  pushd "$project_dir" >/dev/null
  "$SCAFFOLDER" \
    --profile "$profile" \
    --name "$name" \
    --no-git \
    --no-install-hooks \
    --no-github-actions
  popd >/dev/null

  assert_pyright_venv_config "$profile" "$project_dir"
  run_project_checks "$project_dir"
  printf '%s scaffold e2e passed\n' "$profile"
}

require_command bash
require_command uv
require_command npm

if [[ ! -x "$SCAFFOLDER" ]]; then
  printf 'Scaffolder is not executable: %s\n' "$SCAFFOLDER" >&2
  exit 1
fi

TMP_ROOT="$(mktemp -d)"
if [[ "${REPOSEED_KEEP_E2E:-0}" == "1" ]]; then
  printf 'Keeping E2E workspace: %s\n' "$TMP_ROOT"
else
  trap 'rm -rf "$TMP_ROOT"' EXIT
fi

export UV_CACHE_DIR="${UV_CACHE_DIR:-/tmp/reposeed-uv-cache}"
export npm_config_cache="${npm_config_cache:-/tmp/reposeed-npm-cache}"

printf 'E2E workspace: %s\n' "$TMP_ROOT"

run_scaffold_case base base-demo
run_scaffold_case web web-demo

if [[ "${REPOSEED_E2E_GAME:-0}" == "1" ]]; then
  run_scaffold_case game game-demo
fi

printf 'all scaffold e2e tests passed\n'
