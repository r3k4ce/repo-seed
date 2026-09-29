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

assert_file_not_contains() {
  local file_path="$1"
  local unexpected="$2"

  if [[ "$(<"$file_path")" == *"$unexpected"* ]]; then
    printf 'Expected %s not to contain: %s\n' "$file_path" "$unexpected" >&2
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

# Reads one KEY from versions.env so tests assert against the manifest, not
# against copies of version numbers that would drift.
pinned() {
  local key="$1"
  local value

  value="$(sed -nE "s/^${key}=([A-Za-z0-9.+-]+)[[:space:]]*$/\\1/p" "$ROOT/versions.env" | head -n1)"
  if [[ -z "$value" ]]; then
    printf 'versions.env is missing %s\n' "$key" >&2
    exit 1
  fi
  printf '%s' "$value"
}

assert_exact_pins_only() {
  local file_path="$1"

  assert_file_not_contains "$file_path" '"latest"'
  if grep -Eq '": *"[\^~*]' "$file_path"; then
    printf 'Expected only exact version pins in %s\n' "$file_path" >&2
    exit 1
  fi
}

assert_python_pins() {
  local pyproject_path="$1"

  assert_file_contains "$pyproject_path" "ruff==$(pinned PY_RUFF)"
  assert_file_contains "$pyproject_path" "pytest==$(pinned PY_PYTEST)"
  assert_file_contains "$pyproject_path" "pytest-cov==$(pinned PY_PYTEST_COV)"
  assert_file_contains "$pyproject_path" "pyright==$(pinned PY_PYRIGHT)"
  assert_file_contains "$pyproject_path" "pre-commit==$(pinned PY_PRE_COMMIT)"
  assert_file_contains "$pyproject_path" "python-dotenv==$(pinned PY_PYTHON_DOTENV)"
}

assert_web_frontend_config() {
  local project_dir="$1"
  local package_json_path="$project_dir/frontend/package.json"
  local vite_config_path="$project_dir/frontend/vite.config.ts"
  local check_script_path="$project_dir/scripts/check.sh"
  local fix_script_path="$project_dir/scripts/fix.sh"
  local pre_commit_config_path="$project_dir/.pre-commit-config.yaml"

  assert_exact_pins_only "$package_json_path"
  assert_file_contains "$package_json_path" "\"react\": \"$(pinned NPM_REACT)\""
  assert_file_contains "$package_json_path" "\"tailwindcss\": \"$(pinned NPM_TAILWINDCSS)\""
  assert_file_contains "$package_json_path" "\"@tailwindcss/vite\": \"$(pinned NPM_TAILWINDCSS_VITE)\""
  assert_file_contains "$package_json_path" "\"vite\": \"$(pinned NPM_VITE)\""
  assert_file_contains "$package_json_path" "\"vitest\": \"$(pinned NPM_VITEST)\""
  assert_file_contains "$package_json_path" "\"@vitest/coverage-v8\": \"$(pinned NPM_VITEST_COVERAGE_V8)\""
  assert_file_contains "$package_json_path" "\"node\": \">=$(pinned NODE_MIN)\""
  assert_file_contains "$package_json_path" '"test": "vitest run --coverage"'
  assert_file_contains "$package_json_path" '"test:watch": "vitest"'
  assert_file_contains "$project_dir/frontend/.npmrc" 'save-exact=true'
  assert_file_not_contains "$package_json_path" '@playwright/test'
  assert_file_not_contains "$package_json_path" 'test:e2e'
  assert_file_contains "$project_dir/backend/pyproject.toml" "fastapi==$(pinned PY_FASTAPI)"
  assert_file_contains "$project_dir/backend/pyproject.toml" "uvicorn==$(pinned PY_UVICORN)"

  assert_file_contains "$vite_config_path" 'import tailwindcss from "@tailwindcss/vite";'
  assert_file_contains "$vite_config_path" 'plugins: [react(), tailwindcss()]'
  assert_file_contains "$vite_config_path" 'provider: "v8"'
  assert_file_contains "$vite_config_path" 'thresholds: {'

  assert_file_contains "$check_script_path" 'uv run pytest'
  assert_file_contains "$check_script_path" 'npm run test'
  assert_file_contains "$check_script_path" 'npm run typecheck'
  assert_file_contains "$check_script_path" 'npm run lint'
  assert_file_contains "$check_script_path" 'npm run build'
  assert_file_not_contains "$check_script_path" 'npm run test --if-present'
  assert_file_not_contains "$check_script_path" 'npm run test:e2e --if-present'

  assert_file_contains "$fix_script_path" 'uv run pytest'
  assert_file_contains "$fix_script_path" 'npm run test'
  assert_file_contains "$fix_script_path" 'npm run typecheck'
  assert_file_contains "$fix_script_path" 'npm run lint'
  assert_file_contains "$fix_script_path" 'npm run build'
  assert_file_not_contains "$fix_script_path" 'npm run test --if-present'
  assert_file_not_contains "$fix_script_path" 'npm run test:e2e --if-present'

  assert_file_contains "$pre_commit_config_path" 'entry: bash scripts/check.sh'
  assert_file_contains "$pre_commit_config_path" 'stages: [pre-push]'
  assert_file_not_contains "$pre_commit_config_path" 'npm run test:e2e'
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
  if [[ "$profile" == "web" || "$profile" == "game" ]]; then
    assert_python_pins "$project_dir/backend/pyproject.toml"
  else
    assert_python_pins "$project_dir/pyproject.toml"
  fi
  if [[ "$profile" == "web" ]]; then
    assert_web_frontend_config "$project_dir"
  fi
  if [[ "$profile" == "game" ]]; then
    assert_exact_pins_only "$project_dir/frontend/package.json"
    assert_file_contains "$project_dir/frontend/package.json" "\"phaser\": \"$(pinned NPM_PHASER)\""
    assert_file_contains "$project_dir/frontend/package.json" "\"@playwright/test\": \"$(pinned NPM_PLAYWRIGHT_TEST)\""
  fi
  if [[ -e "$project_dir/AGENTS.md" ]]; then
    printf 'Expected no AGENTS.md in generated project: %s/AGENTS.md\n' "$project_dir" >&2
    exit 1
  fi
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
