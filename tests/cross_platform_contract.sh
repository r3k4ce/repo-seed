#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

export UV_CACHE_DIR="${UV_CACHE_DIR:-/tmp/reposeed-uv-cache}"
export npm_config_cache="${npm_config_cache:-/tmp/reposeed-npm-cache}"

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

# Generated helper scripts must be exact copies of templates/scripts/<profile>/,
# with no per-platform shell scripts alongside them.
assert_project_scripts() {
  local profile="$1"
  local project_dir="$2"
  local task leftover

  for task in check fix; do
    cmp -s "$ROOT/templates/scripts/$profile/$task.py" "$project_dir/scripts/$task.py" || {
      printf 'Expected %s/scripts/%s.py to equal templates/scripts/%s/%s.py\n' "$project_dir" "$task" "$profile" "$task" >&2
      exit 1
    }
  done
  for leftover in check.sh fix.sh check.ps1 fix.ps1; do
    if [[ -e "$project_dir/scripts/$leftover" ]]; then
      printf 'Expected no scripts/%s in generated project: %s\n' "$leftover" "$project_dir" >&2
      exit 1
    fi
  done
}

prepend_fake_uv() {
  local fake_bin="$1"

  mkdir -p "$fake_bin"
  cat >"$fake_bin/uv" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1-}" == "--version" ]]; then
  printf 'uv 99.0.0 (fake)\n'
  exit 0
fi

if [[ "${1-}" == "init" ]]; then
  project_dir="."
  package_name="python_project"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)
        package_name="${2//-/_}"
        shift 2
        ;;
      --vcs|--python)
        shift 2
        ;;
      --package)
        shift
        ;;
      init)
        shift
        ;;
      *)
        project_dir="$1"
        shift
        ;;
    esac
  done

  mkdir -p "$project_dir/src/$package_name"
  printf '[project]\nname = "%s"\nversion = "0.1.0"\n' "$package_name" >"$project_dir/pyproject.toml"
  printf 'def project_name() -> str:\n    return "%s"\n' "$package_name" >"$project_dir/src/$package_name/__init__.py"
  exit 0
fi

exit 0
EOF
  chmod +x "$fake_bin/uv"
  export PATH="$fake_bin:$PATH"
}

prepend_fake_npm() {
  local fake_bin="$1"
  local log_path="$2"

  cat >"$fake_bin/npm" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >>"$log_path"
EOF
  chmod +x "$fake_bin/npm"
}

run_bash_install_contract() {
  local tmp_root bin_dir data_dir wrapper

  tmp_root="$(mktemp -d)"
  bin_dir="$tmp_root/bin"
  data_dir="$tmp_root/data"
  wrapper="$bin_dir/reposeed-test"

  "$ROOT/install.sh" \
    --bin-dir "$bin_dir" \
    --data-dir "$data_dir" \
    --command reposeed-test

  [[ -x "$wrapper" ]] || {
    printf 'Expected executable wrapper: %s\n' "$wrapper" >&2
    exit 1
  }
  [[ -f "$data_dir/new-project.sh" ]] || {
    printf 'Expected Bash scaffolder in payload.\n' >&2
    exit 1
  }
  [[ -f "$data_dir/new-project.ps1" ]] || {
    printf 'Expected PowerShell scaffolder in payload.\n' >&2
    exit 1
  }
  [[ -d "$data_dir/templates" ]] || {
    printf 'Expected templates in payload.\n' >&2
    exit 1
  }
  [[ -f "$data_dir/versions.env" ]] || {
    printf 'Expected versions.env in payload.\n' >&2
    exit 1
  }

  assert_file_contains "$wrapper" 'new-project.sh'
}

run_windows_installer_static_contract() {
  local installer_path="$ROOT/install.ps1"

  [[ -f "$installer_path" ]] || {
    printf 'Expected Windows installer: %s\n' "$installer_path" >&2
    exit 1
  }

  assert_file_contains "$installer_path" 'Microsoft\WindowsApps'
  assert_file_contains "$installer_path" 'RepoSeed'
  assert_file_contains "$installer_path" 'new-project.ps1'
  assert_file_contains "$installer_path" 'versions.env'
  assert_file_contains "$installer_path" '$Command.ps1'
}

run_base_scaffold_contract() {
  local tmp_root project_dir agents_path

  tmp_root="$(mktemp -d)"
  prepend_fake_uv "$tmp_root/bin"
  project_dir="$tmp_root/bash-base-demo"
  agents_path="$project_dir/AGENTS.md"
  mkdir -p "$project_dir"

  pushd "$project_dir" >/dev/null
  "$ROOT/new-project.sh" \
    --name bash-base-demo \
    --no-git \
    --no-install-hooks \
    --no-github-actions
  popd >/dev/null

  assert_project_scripts base "$project_dir"
  assert_file_contains "$project_dir/pyproject.toml" 'include = ["src", "tests", "scripts"]'

  if [[ -e "$agents_path" ]]; then
    printf 'Expected no AGENTS.md in generated project: %s\n' "$agents_path" >&2
    exit 1
  fi
}

run_powershell_contract_if_available() {
  if [[ "$(uname -s)" == MINGW* || "$(uname -s)" == MSYS* ]]; then
    printf 'Skipping PowerShell contract under Git Bash\n'
    return
  fi
  if ! command -v pwsh >/dev/null 2>&1; then
    printf 'Skipping PowerShell contract: pwsh not found\n'
    return
  fi

  pwsh -NoProfile -File "$ROOT/new-project.ps1" -? >/dev/null
  pwsh -NoProfile -File "$ROOT/install.ps1" -? >/dev/null

  local tmp_root project_dir agents_path
  tmp_root="$(mktemp -d)"
  prepend_fake_uv "$tmp_root/bin"
  project_dir="$tmp_root/ps-base-demo"
  agents_path="$project_dir/AGENTS.md"
  mkdir -p "$project_dir"

  pushd "$project_dir" >/dev/null
  pwsh -NoProfile -File "$ROOT/new-project.ps1" \
    -Name ps-base-demo \
    -NoGit \
    -NoInstallHooks \
    -NoGitHubActions
  popd >/dev/null

  assert_project_scripts base "$project_dir"
  assert_file_contains "$project_dir/pyproject.toml" 'include = ["src", "tests", "scripts"]'
  # The base profile installs per-tool hooks; only the web/game profiles wrap
  # scripts/check.py in a single pre-push hook.
  assert_file_contains "$project_dir/.pre-commit-config.yaml" 'entry: uv run ruff format --check .'
  assert_file_contains "$project_dir/.pre-commit-config.yaml" 'entry: uv run pyright'
  assert_file_contains "$project_dir/.pre-commit-config.yaml" 'stages: [pre-push]'
  assert_file_contains "$project_dir/pyproject.toml" 'venvPath = "."'
  if [[ -e "$agents_path" ]]; then
    printf 'Expected no AGENTS.md in generated project: %s\n' "$agents_path" >&2
    exit 1
  fi
}

run_bash_web_and_game_install_contract() {
  local tmp_root project_dir log_path game_dir cleanup_command
  tmp_root="$(mktemp -d)"
  printf -v cleanup_command 'cd -- %q >/dev/null 2>&1 || true; rm -rf -- %q' "$PWD" "$tmp_root"
  trap "$cleanup_command" EXIT
  log_path="$tmp_root/npm-args.log"
  : >"$log_path"
  prepend_fake_uv "$tmp_root/bin"
  prepend_fake_npm "$tmp_root/bin" "$log_path"
  project_dir="$tmp_root/bash-web-install-contract"
  mkdir -p "$project_dir"

  pushd "$project_dir" >/dev/null
  "$ROOT/new-project.sh" \
    --profile web \
    --name bash-web-install-contract \
    --no-git \
    --no-install-hooks \
    --no-github-actions
  popd >/dev/null

  [[ -f "$project_dir/README.md" ]] || {
    printf 'Expected README.md: %s\n' "$project_dir/README.md" >&2
    exit 1
  }
  assert_project_scripts web "$project_dir"
  assert_file_contains "$project_dir/.pre-commit-config.yaml" 'entry: uv run scripts/check.py'
  local vitest_version coverage_version dom_version
  dom_version="$(sed -nE 's/^NPM_TESTING_LIBRARY_DOM=([A-Za-z0-9.+-]+)[[:space:]]*$/\1/p' "$ROOT/versions.env" | head -n1)"
  [[ -n "$dom_version" ]] || {
    printf 'versions.env is missing NPM_TESTING_LIBRARY_DOM\n' >&2
    exit 1
  }
  assert_file_contains "$project_dir/frontend/package.json" "\"@testing-library/dom\": \"$dom_version\""
  vitest_version="$(sed -nE 's/^NPM_VITEST=([A-Za-z0-9.+-]+)[[:space:]]*$/\1/p' "$ROOT/versions.env" | head -n1)"
  coverage_version="$(sed -nE 's/^NPM_VITEST_COVERAGE_V8=([A-Za-z0-9.+-]+)[[:space:]]*$/\1/p' "$ROOT/versions.env" | head -n1)"
  [[ -n "$vitest_version" && -n "$coverage_version" ]] || {
    printf 'versions.env is missing NPM_VITEST or NPM_VITEST_COVERAGE_V8\n' >&2
    exit 1
  }
  assert_file_contains "$project_dir/frontend/package.json" "\"@vitest/coverage-v8\": \"$coverage_version\""
  assert_file_contains "$project_dir/frontend/package.json" "\"vitest\": \"$vitest_version\""
  local -a calls
  mapfile -t calls <"$log_path"
  if [[ "${#calls[@]}" -ne 1 || "${calls[0]}" != "install --no-audit --legacy-peer-deps" ]]; then
    printf 'Expected web npm call install --no-audit --legacy-peer-deps, got: %s\n' "${calls[*]}" >&2
    exit 1
  fi

  : >"$log_path"
  game_dir="$tmp_root/bash-game-install-contract"
  mkdir -p "$game_dir"

  pushd "$game_dir" >/dev/null
  "$ROOT/new-project.sh" \
    --profile game \
    --name bash-game-install-contract \
    --no-git \
    --no-install-hooks \
    --no-github-actions
  popd >/dev/null

  mapfile -t calls <"$log_path"
  if [[ "${#calls[@]}" -ne 2 || "${calls[0]}" != "install --no-audit --legacy-peer-deps" || "${calls[1]}" != "exec playwright install chromium" ]]; then
    printf 'Expected game npm calls install --no-audit --legacy-peer-deps then Playwright install, got: %s\n' "${calls[*]}" >&2
    exit 1
  fi

  assert_project_scripts game "$game_dir"
  assert_file_contains "$game_dir/.pre-commit-config.yaml" 'entry: uv run scripts/check.py'
  assert_file_not_contains "$game_dir/frontend/package.json" '"vitest"'
  assert_file_not_contains "$game_dir/frontend/package.json" '"@vitest/coverage-v8"'

  rm -rf -- "$tmp_root"

  [[ ! -d "$tmp_root" ]] || {
    printf 'Expected temporary contract root to be cleaned up: %s\n' "$tmp_root" >&2
    exit 1
  }

  trap - EXIT
}

run_bash_install_contract
run_windows_installer_static_contract
run_base_scaffold_contract
run_powershell_contract_if_available
run_bash_web_and_game_install_contract

printf 'cross-platform contract tests passed\n'
