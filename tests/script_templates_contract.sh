#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TEMPLATES="$ROOT/templates/scripts"
PROFILES=(base web game)
TASKS=(check fix)

# Resolve the real interpreters before any test narrows PATH to fake tools.
PYTHON="$(command -v python3)"
BASH_BIN="$(command -v bash)"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

# Writes one fake executable per tool. Each logs
# "<tool> <args> | cwd=<dir name> | venv=<VIRTUAL_ENV or unset>" and exits 3
# when "<tool> <args>" equals FAKE_FAIL_ON, otherwise 0.
make_fake_bin() {
  local fake_bin="$1"
  local log_path="$2"
  shift 2
  local tools=("$@")
  [[ ${#tools[@]} -gt 0 ]] || tools=(uv npm)

  mkdir -p "$fake_bin"
  : >"$log_path"
  local tool
  for tool in "${tools[@]}"; do
    cat >"$fake_bin/$tool" <<EOF
#!$BASH_BIN
line="$tool \$*"
printf '%s | cwd=%s | venv=%s\n' "\$line" "\${PWD##*/}" "\${VIRTUAL_ENV-unset}" >>"$log_path"
if [[ -n "\${FAKE_FAIL_ON-}" && "\$line" == "\$FAKE_FAIL_ON" ]]; then
  exit 3
fi
exit 0
EOF
    chmod +x "$fake_bin/$tool"
  done
}

make_project() {
  local project_dir="$1"
  local profile="$2"
  local task="$3"

  mkdir -p "$project_dir/scripts" "$project_dir/backend" "$project_dir/frontend"
  cp "$TEMPLATES/$profile/$task.py" "$project_dir/scripts/$task.py"
}

# Runs a template from the backend/ subfolder with only the fake tools on PATH
# and a caller VIRTUAL_ENV that must not reach the tools. Sets RUN_STATUS and
# writes stdout/stderr next to the project.
run_template() {
  local fake_bin="$1"
  local project_dir="$2"
  local task="$3"

  RUN_STATUS=0
  (
    cd "$project_dir/backend"
    env -i PATH="$fake_bin" VIRTUAL_ENV=/caller/venv FAKE_FAIL_ON="${FAKE_FAIL_ON-}" \
      "$PYTHON" "$project_dir/scripts/$task.py"
  ) >"$project_dir.stdout" 2>"$project_dir.stderr" || RUN_STATUS=$?
}

expected_steps() {
  local profile="$1"
  local task="$2"
  local project_name="$3"
  local python_cwd="$project_name"
  [[ "$profile" == "base" ]] || python_cwd="backend"

  local python_steps=()
  if [[ "$task" == "check" ]]; then
    python_steps=("uv run ruff format --check ." "uv run ruff check .")
  else
    python_steps=("uv run ruff check . --fix" "uv run ruff format ." "uv run ruff check .")
  fi
  python_steps+=("uv run pyright" "uv run pytest")

  local step
  for step in "${python_steps[@]}"; do
    printf '%s | cwd=%s | venv=unset\n' "$step" "$python_cwd"
  done

  local npm_steps=()
  case "$profile" in
    web)
      npm_steps=("npm run test" "npm run typecheck" "npm run lint" "npm run build")
      ;;
    game)
      npm_steps=("npm run test --if-present" "npm run test:e2e --if-present" "npm run lint" "npm run build")
      ;;
  esac
  for step in ${npm_steps[@]+"${npm_steps[@]}"}; do
    printf '%s | cwd=frontend | venv=unset\n' "$step"
  done
}

test_templates_complete() {
  local profile task
  for profile in "${PROFILES[@]}"; do
    for task in "${TASKS[@]}"; do
      [[ -f "$TEMPLATES/$profile/$task.py" ]] || fail "Missing template: scripts/$profile/$task.py"
    done
  done
}

test_shared_helper_identical() {
  local reference="" profile task helper
  for profile in "${PROFILES[@]}"; do
    for task in "${TASKS[@]}"; do
      helper="$(sed -n '/^# --- shared helper ---$/,/^# --- end shared helper ---$/p' "$TEMPLATES/$profile/$task.py")"
      [[ -n "$helper" ]] || fail "No shared helper block in scripts/$profile/$task.py"
      if [[ -z "$reference" ]]; then
        reference="$helper"
      elif [[ "$helper" != "$reference" ]]; then
        fail "Shared helper in scripts/$profile/$task.py differs from scripts/base/check.py"
      fi
    done
  done
}

test_steps() {
  local profile="$1"
  local task="$2"
  local case_dir="$TMP_ROOT/steps-$profile-$task"
  local project_dir="$case_dir/project"
  local log_path="$case_dir/calls.log"

  make_fake_bin "$case_dir/bin" "$log_path"
  make_project "$project_dir" "$profile" "$task"
  FAKE_FAIL_ON="" run_template "$case_dir/bin" "$project_dir" "$task"

  [[ "$RUN_STATUS" -eq 0 ]] || fail "scripts/$profile/$task.py exited $RUN_STATUS: $(<"$project_dir.stderr")"
  local expected
  expected="$(expected_steps "$profile" "$task" project)"
  if [[ "$(<"$log_path")" != "$expected" ]]; then
    printf 'Unexpected steps for scripts/%s/%s.py\n--- expected\n%s\n--- actual\n%s\n' \
      "$profile" "$task" "$expected" "$(<"$log_path")" >&2
    exit 1
  fi
}

test_stops_at_first_failure() {
  local case_dir="$TMP_ROOT/failure"
  local project_dir="$case_dir/project"
  local log_path="$case_dir/calls.log"

  make_fake_bin "$case_dir/bin" "$log_path"
  make_project "$project_dir" base check
  FAKE_FAIL_ON="uv run ruff check ." run_template "$case_dir/bin" "$project_dir" check

  [[ "$RUN_STATUS" -eq 3 ]] || fail "Expected exit code 3 from failing step, got $RUN_STATUS"
  [[ "$(wc -l <"$log_path")" -eq 2 ]] || fail "Expected 2 steps before stopping, got: $(<"$log_path")"
  [[ "$(<"$log_path")" != *"pyright"* ]] || fail "pyright ran after a failing step"
}

test_missing_tool() {
  local case_dir="$TMP_ROOT/missing-npm"
  local project_dir="$case_dir/project"
  local log_path="$case_dir/calls.log"

  make_fake_bin "$case_dir/bin" "$log_path" uv
  make_project "$project_dir" web check
  FAKE_FAIL_ON="" run_template "$case_dir/bin" "$project_dir" check

  [[ "$RUN_STATUS" -ne 0 ]] || fail "Expected non-zero exit when npm is missing"
  [[ "$(<"$project_dir.stderr")" == *"error: 'npm' was not found on PATH"* ]] ||
    fail "Expected missing-npm error, got: $(<"$project_dir.stderr")"
  [[ "$(<"$project_dir.stderr")" != *"Traceback"* ]] || fail "Missing tool produced a traceback"
  [[ "$(wc -l <"$log_path")" -eq 4 ]] || fail "Expected the 4 backend steps before npm, got: $(<"$log_path")"
}

test_prints_commands() {
  local case_dir="$TMP_ROOT/printing"
  local project_dir="$case_dir/project"

  make_fake_bin "$case_dir/bin" "$case_dir/calls.log"
  make_project "$project_dir" base check
  FAKE_FAIL_ON="" run_template "$case_dir/bin" "$project_dir" check

  [[ "$RUN_STATUS" -eq 0 ]] || fail "scripts/base/check.py exited $RUN_STATUS"
  [[ "$(<"$project_dir.stdout")" == *"> uv run ruff format --check ."* ]] ||
    fail "Expected the first command to be printed, got: $(<"$project_dir.stdout")"
  [[ "$(<"$project_dir.stdout")" == *"> uv run pytest"* ]] ||
    fail "Expected the last command to be printed, got: $(<"$project_dir.stdout")"
}

test_templates_complete
test_shared_helper_identical
for profile in "${PROFILES[@]}"; do
  for task in "${TASKS[@]}"; do
    test_steps "$profile" "$task"
  done
done
test_stops_at_first_failure
test_missing_tool
test_prints_commands

printf 'script template contract tests passed\n'
