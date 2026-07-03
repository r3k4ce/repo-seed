#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT/new-project.sh"
INSTALLER="$ROOT/install.sh"

assert_file() {
  local path="$1"
  local message="$2"

  if [[ ! -f "$path" ]]; then
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

assert_not_contains() {
  local text="$1"
  local needle="$2"
  local message="$3"

  if [[ "$text" == *"$needle"* ]]; then
    printf 'Assertion failed: %s\nUnexpected: %s\n' "$message" "$needle" >&2
    exit 1
  fi
}

assert_file "$SCRIPT" "new-project.sh must exist."
assert_file "$INSTALLER" "install.sh must exist."
bash -n "$SCRIPT"
bash -n "$INSTALLER"

script_text="$(<"$SCRIPT")"

assert_contains "$script_text" 'PROFILE="base"' "Base profile should be the default."
assert_contains "$script_text" 'base|web|game' "Bash port should support base, web, and game profiles."
assert_not_contains "$script_text" 'desktop)' "Bash port should not implement the desktop profile."

for flag in '--name' '--python' '--type-mode' '--profile' '--no-git' '--no-install-hooks' '--no-github-actions'; do
  assert_contains "$script_text" "$flag" "Missing GNU flag $flag."
done

assert_contains "$script_text" 'scripts/check.sh' "Generated project checks should use bash scripts."
assert_contains "$script_text" 'scripts/fix.sh' "Generated project fixes should use bash scripts."
assert_not_contains "$script_text" 'scripts/check.ps1' "Bash-generated projects should not reference PowerShell check scripts."
assert_not_contains "$script_text" 'scripts/fix.ps1' "Bash-generated projects should not reference PowerShell fix scripts."
assert_contains "$script_text" 'entry: bash scripts/check.sh' "Web/game pre-push hook should call the bash check script."
assert_contains "$script_text" 'npx playwright install --with-deps chromium' "Game CI should install Playwright Chromium."

template_names=(
  "agents/base.md"
  "agents/profiles/base.md"
  "agents/profiles/web.md"
  "agents/profiles/game.md"
  "game/frontend_main.ts"
  "game/backend_main.py"
  "game/scene.ts"
  "game/test_game_api.py"
  "game/playwright.config.ts"
  "game/game-smoke.spec.ts"
  "web/App.test.tsx"
  "web/test_setup.ts"
)

for template_name in "${template_names[@]}"; do
  assert_file "$ROOT/templates/$template_name" "Missing template: $template_name"
  assert_contains "$script_text" "$template_name" "Bash script should reference template: $template_name"
done

readme_text="$(<"$ROOT/README.md")"
assert_contains "$readme_text" './new-project.sh' "README should document the bash entrypoint."
assert_contains "$readme_text" './install.sh' "README should document the Bash installer."
assert_contains "$readme_text" 'reposeed' "README should document the installed Bash command."
assert_contains "$readme_text" './scripts/check.sh' "README should document generated bash check scripts."

printf 'Bash static checks passed.\n'
