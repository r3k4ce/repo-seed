#!/usr/bin/env bash
set -euo pipefail

# Template references used by supported profiles:
# agents/base.md
# agents/profiles/base.md
# agents/profiles/web.md
# agents/profiles/game.md
# web/App.test.tsx
# web/test_setup.ts
# game/frontend_main.ts
# game/backend_main.py
# game/scene.ts
# game/test_game_api.py
# game/playwright.config.ts
# game/game-smoke.spec.ts

NAME="$(basename "$(pwd -P)")"
PYTHON_VERSION="3.12"
TYPE_MODE="standard"
PROFILE="base"
NO_GIT=0
NO_INSTALL_HOOKS=0
NO_GITHUB_ACTIONS=0

usage() {
  cat <<'EOF'
Usage: new-project.sh [options]

Seed a clean, checked, agent-ready repo from the current directory.

Options:
  --name VALUE              Project name. Defaults to the current directory name.
  --python VALUE            Python version for uv init. Defaults to 3.12.
  --type-mode VALUE         Pyright mode: off, basic, standard, strict. Defaults to standard.
  --profile VALUE           Scaffold profile: base, web, game. Defaults to base.
  --no-git                  Skip git initialization.
  --no-install-hooks        Skip pre-commit and pre-push hook installation.
  --no-github-actions       Skip GitHub Actions workflow generation.
  -h, --help                Show this help.
EOF
}

die() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

warn() {
  printf 'Warning: %s\n' "$1" >&2
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

invoke_checked() {
  "$@"
}

write_text_file() {
  local path="$1"
  local content="${2-}"
  local parent

  parent="$(dirname "$path")"
  mkdir -p "$parent"
  content="${content//$'\r\n'/$'\n'}"
  content="${content//$'\r'/$'\n'}"
  printf '%s\n' "${content%$'\n'}" >"$path"
}

add_text_file() {
  local path="$1"
  local append="${2-}"
  local parent existing combined

  parent="$(dirname "$path")"
  mkdir -p "$parent"
  append="${append//$'\r\n'/$'\n'}"
  append="${append//$'\r'/$'\n'}"
  while [[ "$append" == $'\n'* ]]; do
    append="${append#$'\n'}"
  done

  if [[ -f "$path" ]]; then
    existing="$(<"$path")"
    existing="${existing//$'\r\n'/$'\n'}"
    existing="${existing//$'\r'/$'\n'}"
    if [[ -z "${existing//[[:space:]]/}" ]]; then
      combined="$append"
    else
      combined="${existing%$'\n'}"$'\n'"$append"
    fi
    printf '%s\n' "${combined%$'\n'}" >"$path"
  else
    write_text_file "$path" "$append"
  fi
}

read_template() {
  local name="$1"
  local path="$SCRIPT_ROOT/templates/$name"

  [[ -f "$path" ]] || die "Missing template: $name"
  cat "$path"
}

expand_text() {
  local text="$1"
  text="${text//__PROJECT_NAME__/$PROJECT_NAME}"
  text="${text//__PACKAGE_NAME__/$PACKAGE_NAME}"
  text="${text//__PYTHON_VERSION__/$PYTHON_VERSION}"
  printf '%s' "$text"
}

write_template_file() {
  local template_name="$1"
  local path="$2"
  local content

  content="$(read_template "$template_name")"
  write_text_file "$path" "$(expand_text "$content")"
}

write_agents_file() {
  local profile_name="$1"
  local base snippet

  base="$(expand_text "$(read_template "agents/base.md")")"
  snippet="$(expand_text "$(read_template "agents/profiles/$profile_name.md")")"
  write_text_file "AGENTS.md" "${base%$'\n'}"$'\n\n'"$snippet"
}

require_uv() {
  if ! command_exists uv; then
    die "uv was not found on PATH. Install uv first, then rerun this script."
  fi
}

require_npm() {
  if ! command_exists npm; then
    die "npm was not found on PATH. Install Node.js first, then rerun this script."
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)
        [[ $# -ge 2 ]] || die "--name requires a value."
        NAME="$2"
        shift 2
        ;;
      --python)
        [[ $# -ge 2 ]] || die "--python requires a value."
        PYTHON_VERSION="$2"
        shift 2
        ;;
      --type-mode)
        [[ $# -ge 2 ]] || die "--type-mode requires a value."
        TYPE_MODE="$2"
        shift 2
        ;;
      --profile)
        [[ $# -ge 2 ]] || die "--profile requires a value."
        PROFILE="$2"
        shift 2
        ;;
      --no-git)
        NO_GIT=1
        shift
        ;;
      --no-install-hooks)
        NO_INSTALL_HOOKS=1
        shift
        ;;
      --no-github-actions)
        NO_GITHUB_ACTIONS=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
  done
}

validate_args() {
  case "$TYPE_MODE" in
    off|basic|standard|strict) ;;
    *) die "--type-mode must be one of: off, basic, standard, strict." ;;
  esac

  case "$PROFILE" in
    base|web|game) ;;
    *) die "--profile must be one of: base, web, game." ;;
  esac
}

init_common_values() {
  PROJECT_NAME="$(printf '%s' "$NAME" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
  if [[ -z "${PROJECT_NAME//[[:space:]]/}" ]]; then
    PROJECT_NAME="python-project"
  fi

  PACKAGE_NAME="${PROJECT_NAME//-/_}"
  RUFF_TARGET="py312"
  if [[ "$PYTHON_VERSION" =~ ([0-9]+)\.([0-9]+) ]]; then
    RUFF_TARGET="py${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
  fi
}

timestamp_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

timestamp_local() {
  local stamp offset
  stamp="$(date +"%Y-%m-%dT%H:%M:%S")"
  offset="$(date +"%z")"
  printf '%s%s:%s' "$stamp" "${offset:0:3}" "${offset:3:2}"
}

write_base_common_files() {
  add_text_file "pyproject.toml" "

[tool.ruff]
line-length = 100
target-version = \"$RUFF_TARGET\"

[tool.ruff.lint]
select = [
    \"E\",    # pycodestyle errors
    \"F\",    # Pyflakes
    \"I\",    # import sorting
    \"B\",    # bugbear: likely bugs
    \"UP\",   # pyupgrade: modern Python syntax
    \"SIM\",  # simplifications
    \"C4\",   # cleaner comprehensions
    \"PT\",   # pytest style
    \"RUF\"   # Ruff-specific rules
]
ignore = []

[tool.ruff.format]
quote-style = \"double\"
indent-style = \"space\"
line-ending = \"auto\"

[tool.pyright]
include = [\"src\", \"tests\"]
exclude = [
    \".venv\",
    \".pytest_cache\",
    \".ruff_cache\",
    \"build\",
    \"dist\",
    \"**/__pycache__\",
    \"**/*.egg-info\"
]
typeCheckingMode = \"$TYPE_MODE\"
pythonVersion = \"$PYTHON_VERSION\"
reportMissingTypeStubs = false
venvPath = \".\"
venv = \".venv\"

[tool.pytest.ini_options]
minversion = \"8.0\"
addopts = \"-ra --strict-markers --strict-config --cov --cov-report=term-missing:skip-covered --cov-report=xml\"
testpaths = [\"tests\"]

[tool.coverage.run]
branch = true
source = [\"src\"]
omit = [
    \".venv/*\",
    \"tests/*\"
]

[tool.coverage.report]
show_missing = true
skip_covered = true
fail_under = 80
exclude_also = [
    \"if TYPE_CHECKING:\",
    \"if __name__ == .__main__.:\",
    \"raise NotImplementedError\"
]
"

  write_text_file ".editorconfig" "root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true
indent_style = space
indent_size = 4

[*.{yml,yaml,toml,json,md}]
indent_size = 2"

  write_text_file ".gitattributes" "* text=auto

# Source/config files: always LF
*.py text eol=lf
*.pyi text eol=lf
*.toml text eol=lf
*.lock text eol=lf
*.yml text eol=lf
*.yaml text eol=lf
*.json text eol=lf
*.md text eol=lf
*.txt text eol=lf
*.sh text eol=lf
*.sql text eol=lf
*.html text eol=lf
*.css text eol=lf
*.js text eol=lf
*.ts text eol=lf

# Windows command scripts
*.bat text eol=crlf
*.cmd text eol=crlf

# Binary files
*.png binary
*.jpg binary
*.jpeg binary
*.gif binary
*.webp binary
*.ico binary
*.pdf binary
*.zip binary
*.gz binary
*.sqlite binary
*.db binary"

  add_text_file ".gitignore" "

# Python
__pycache__/
*.py[cod]
*.pyo
*.pyd

# Environments
.venv/
.env
.env.*
!.env.example

# Tool caches
.pytest_cache/
.ruff_cache/
.mypy_cache/
.pyright/
.coverage
coverage.xml
htmlcov/

# Builds
build/
dist/
*.egg-info/

# Editors / OS
.vscode/
.idea/
.DS_Store
Thumbs.db"

  write_text_file ".env.example" "# Add required environment variable names here. Never commit real secrets."
}

write_base_scripts() {
  mkdir -p "scripts"
  write_text_file "scripts/check.sh" '#!/usr/bin/env bash
set -euo pipefail

uv run ruff format --check .
uv run ruff check .
uv run pyright
uv run pytest'

  write_text_file "scripts/fix.sh" '#!/usr/bin/env bash
set -euo pipefail

uv run ruff check . --fix
uv run ruff format .
uv run ruff check .
uv run pyright
uv run pytest'

  chmod +x "scripts/check.sh" "scripts/fix.sh"
}

write_web_common_files() {
  write_text_file ".editorconfig" "root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true
indent_style = space
indent_size = 2

[*.py]
indent_size = 4"

  write_text_file ".gitattributes" "* text=auto

*.py text eol=lf
*.pyi text eol=lf
*.toml text eol=lf
*.lock text eol=lf
*.yml text eol=lf
*.yaml text eol=lf
*.json text eol=lf
*.md text eol=lf
*.txt text eol=lf
*.sh text eol=lf
*.html text eol=lf
*.css text eol=lf
*.js text eol=lf
*.jsx text eol=lf
*.ts text eol=lf
*.tsx text eol=lf

*.bat text eol=crlf
*.cmd text eol=crlf

*.png binary
*.jpg binary
*.jpeg binary
*.gif binary
*.webp binary
*.ico binary
*.pdf binary
*.zip binary
*.gz binary
*.sqlite binary
*.db binary"

  add_text_file ".gitignore" "

# Python
__pycache__/
*.py[cod]
*.pyo
*.pyd

# Environments
.venv/
.env
.env.*
!.env.example

# Frontend
node_modules/
dist/

# Tool caches
.pytest_cache/
.ruff_cache/
.mypy_cache/
.pyright/
.coverage
coverage.xml
htmlcov/

# Builds
build/
*.egg-info/

# Editors / OS
.vscode/
.idea/
.DS_Store
Thumbs.db"

  write_text_file ".env.example" "# Add required environment variable names here. Never commit real secrets."
}

write_web_scripts() {
  mkdir -p "scripts"
  write_text_file "scripts/check.sh" '#!/usr/bin/env bash
set -euo pipefail

pushd backend >/dev/null
uv run ruff format --check .
uv run ruff check .
uv run pyright
uv run pytest
popd >/dev/null

pushd frontend >/dev/null
npm run test --if-present
npm run test:e2e --if-present
npm run lint
npm run build
popd >/dev/null'

  write_text_file "scripts/fix.sh" '#!/usr/bin/env bash
set -euo pipefail

pushd backend >/dev/null
uv run ruff check . --fix
uv run ruff format .
uv run ruff check .
uv run pyright
uv run pytest
popd >/dev/null

pushd frontend >/dev/null
npm run test --if-present
npm run test:e2e --if-present
npm run lint
npm run build
popd >/dev/null'

  chmod +x "scripts/check.sh" "scripts/fix.sh"
}

write_web_backend_pyproject_config() {
  add_text_file "backend/pyproject.toml" "

[tool.ruff]
line-length = 100
target-version = \"$RUFF_TARGET\"

[tool.ruff.lint]
select = [\"E\", \"F\", \"I\", \"B\", \"UP\", \"SIM\", \"C4\", \"PT\", \"RUF\"]
ignore = []

[tool.ruff.format]
quote-style = \"double\"
indent-style = \"space\"
line-ending = \"auto\"

[tool.pyright]
include = [\"src\", \"tests\"]
exclude = [
    \".venv\",
    \".pytest_cache\",
    \".ruff_cache\",
    \"build\",
    \"dist\",
    \"**/__pycache__\",
    \"**/*.egg-info\"
]
typeCheckingMode = \"$TYPE_MODE\"
pythonVersion = \"$PYTHON_VERSION\"
reportMissingTypeStubs = false
venvPath = \".\"
venv = \".venv\"

[tool.pytest.ini_options]
minversion = \"8.0\"
addopts = \"-ra --strict-markers --strict-config --cov --cov-report=term-missing:skip-covered --cov-report=xml\"
testpaths = [\"tests\"]

[tool.coverage.run]
branch = true
source = [\"src\"]
omit = [\".venv/*\", \"tests/*\"]

[tool.coverage.report]
show_missing = true
skip_covered = true
fail_under = 80
exclude_also = [
    \"if TYPE_CHECKING:\",
    \"if __name__ == .__main__.:\",
    \"raise NotImplementedError\"
]
"
}

write_frontend_files() {
  local web_template_prefix="$1"
  local frontend_entry

  mkdir -p "frontend/src"

  if [[ "$PROFILE" == "game" ]]; then
    write_text_file "frontend/package.json" "{
  \"name\": \"$PROJECT_NAME-frontend\",
  \"private\": true,
  \"version\": \"0.1.0\",
  \"type\": \"module\",
  \"scripts\": {
    \"dev\": \"vite\",
    \"build\": \"tsc -b && vite build\",
    \"lint\": \"eslint .\",
    \"typecheck\": \"tsc --noEmit\",
    \"test:e2e\": \"playwright test\",
    \"preview\": \"vite preview\"
  },
  \"dependencies\": {
    \"phaser\": \"latest\"
  },
  \"devDependencies\": {
    \"vite\": \"latest\",
    \"@playwright/test\": \"latest\",
    \"typescript\": \"latest\",
    \"eslint\": \"latest\",
    \"@eslint/js\": \"latest\",
    \"typescript-eslint\": \"latest\",
    \"globals\": \"latest\"
  }
}"
  else
    write_text_file "frontend/package.json" "{
  \"name\": \"$PROJECT_NAME-frontend\",
  \"private\": true,
  \"version\": \"0.1.0\",
  \"type\": \"module\",
  \"scripts\": {
    \"dev\": \"vite\",
    \"build\": \"tsc -b && vite build\",
    \"lint\": \"eslint .\",
    \"typecheck\": \"tsc --noEmit\",
    \"test\": \"vitest run\",
    \"preview\": \"vite preview\"
  },
  \"dependencies\": {
    \"@vitejs/plugin-react\": \"latest\",
    \"vite\": \"latest\",
    \"typescript\": \"latest\",
    \"react\": \"latest\",
    \"react-dom\": \"latest\",
    \"@types/react\": \"latest\",
    \"@types/react-dom\": \"latest\",
    \"eslint\": \"latest\",
    \"@eslint/js\": \"latest\",
    \"typescript-eslint\": \"latest\",
    \"eslint-plugin-react-hooks\": \"latest\",
    \"eslint-plugin-react-refresh\": \"latest\",
    \"globals\": \"latest\"
  },
  \"devDependencies\": {
    \"vitest\": \"latest\",
    \"jsdom\": \"latest\",
    \"@testing-library/react\": \"latest\",
    \"@testing-library/jest-dom\": \"latest\"
  }
}"
  fi

  frontend_entry="/src/main.tsx"
  [[ "$PROFILE" == "game" ]] && frontend_entry="/src/main.ts"
  write_text_file "frontend/index.html" "<!doctype html>
<html lang=\"en\">
  <head>
    <meta charset=\"UTF-8\" />
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\" />
    <title>$PROJECT_NAME</title>
  </head>
  <body>
    <div id=\"root\"></div>
    <script type=\"module\" src=\"$frontend_entry\"></script>
  </body>
</html>"

  write_text_file "frontend/tsconfig.json" '{
  "files": [],
  "references": [
    { "path": "./tsconfig.app.json" },
    { "path": "./tsconfig.node.json" }
  ]
}'

  if [[ "$PROFILE" == "game" ]]; then
    write_text_file "frontend/tsconfig.app.json" '{
  "compilerOptions": {
    "tsBuildInfoFile": "./node_modules/.tmp/tsconfig.app.tsbuildinfo",
    "target": "ES2022",
    "useDefineForClassFields": true,
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "allowImportingTsExtensions": true,
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "noEmit": true,
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true,
    "skipLibCheck": true
  },
  "include": ["src"]
}'
  else
    write_text_file "frontend/tsconfig.app.json" '{
  "compilerOptions": {
    "tsBuildInfoFile": "./node_modules/.tmp/tsconfig.app.tsbuildinfo",
    "target": "ES2022",
    "useDefineForClassFields": true,
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "allowImportingTsExtensions": true,
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "noEmit": true,
    "jsx": "react-jsx",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true,
    "skipLibCheck": true
  },
  "include": ["src"]
}'
  fi

  write_text_file "frontend/tsconfig.node.json" '{
  "compilerOptions": {
    "tsBuildInfoFile": "./node_modules/.tmp/tsconfig.node.tsbuildinfo",
    "target": "ES2023",
    "lib": ["ES2023"],
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "allowImportingTsExtensions": true,
    "noEmit": true,
    "strict": true,
    "skipLibCheck": true
  },
  "include": ["vite.config.ts", "eslint.config.js"]
}'

  if [[ "$PROFILE" == "game" ]]; then
    write_text_file "frontend/vite.config.ts" 'import { defineConfig } from "vite";

export default defineConfig({
  build: {
    chunkSizeWarningLimit: 2000,
  },
  server: {
    proxy: {
      "/api": "http://127.0.0.1:8000",
    },
  },
});'
    write_text_file "frontend/eslint.config.js" 'import js from "@eslint/js";
import globals from "globals";
import tseslint from "typescript-eslint";

export default tseslint.config(
  { ignores: ["dist"] },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    files: ["**/*.ts"],
    languageOptions: {
      ecmaVersion: 2022,
      globals: globals.browser,
    },
  },
);'
    write_template_file "game/frontend_main.ts" "frontend/src/main.ts"
  else
    write_text_file "frontend/vite.config.ts" 'import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  build: {
    chunkSizeWarningLimit: 2000,
  },
  server: {
    proxy: {
      "/api": "http://127.0.0.1:8000",
    },
  },
  test: {
    environment: "jsdom",
    setupFiles: "./src/test/setup.ts",
  },
});'
    write_text_file "frontend/eslint.config.js" 'import js from "@eslint/js";
import globals from "globals";
import reactHooks from "eslint-plugin-react-hooks";
import reactRefresh from "eslint-plugin-react-refresh";
import tseslint from "typescript-eslint";

export default tseslint.config(
  { ignores: ["dist"] },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    files: ["**/*.{ts,tsx}"],
    languageOptions: {
      ecmaVersion: 2022,
      globals: globals.browser,
    },
    plugins: {
      "react-hooks": reactHooks,
      "react-refresh": reactRefresh,
    },
    rules: {
      ...reactHooks.configs.recommended.rules,
      "react-refresh/only-export-components": ["warn", { allowConstantExport: true }],
    },
  },
);'
    write_template_file "web/frontend_main.tsx" "frontend/src/main.tsx"
    write_template_file "web/App.tsx" "frontend/src/App.tsx"
    write_template_file "web/App.test.tsx" "frontend/src/App.test.tsx"
    write_template_file "web/test_setup.ts" "frontend/src/test/setup.ts"
  fi

  write_text_file "frontend/src/vite-env.d.ts" '/// <reference types="vite/client" />'
  write_template_file "$web_template_prefix/style.css" "frontend/src/style.css"

  if [[ "$PROFILE" == "game" ]]; then
    mkdir -p "frontend/src/game"
    write_template_file "game/scene.ts" "frontend/src/game/GameScene.ts"
    write_template_file "game/playwright.config.ts" "frontend/playwright.config.ts"
    write_template_file "game/game-smoke.spec.ts" "frontend/tests/game-smoke.spec.ts"
  fi
}

write_base_ci() {
  [[ "$NO_GITHUB_ACTIONS" -eq 0 ]] || return 0
  mkdir -p ".github/workflows"
  write_text_file ".github/workflows/ci.yml" 'name: ci

on:
  push:
  pull_request:

jobs:
  check:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v6

      - name: Install uv
        uses: astral-sh/setup-uv@v8.2.0
        with:
          enable-cache: true

      - name: Install Python
        run: uv python install

      - name: Sync dependencies
        run: uv sync --locked --dev

      - name: Ruff format check
        run: uv run --locked ruff format --check .

      - name: Ruff lint
        run: uv run --locked ruff check .

      - name: Pyright
        run: uv run --locked pyright

      - name: Pytest
        run: uv run --locked pytest'
}

write_web_ci() {
  [[ "$NO_GITHUB_ACTIONS" -eq 0 ]] || return 0
  mkdir -p ".github/workflows"
  write_text_file ".github/workflows/ci.yml" 'name: ci

on:
  push:
  pull_request:

jobs:
  check:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v6

      - name: Install uv
        uses: astral-sh/setup-uv@v8.2.0
        with:
          enable-cache: true

      - name: Install Python
        run: uv python install

      - name: Install backend dependencies
        working-directory: backend
        run: uv sync --locked --dev

      - name: Ruff format check
        working-directory: backend
        run: uv run --locked ruff format --check .

      - name: Ruff lint
        working-directory: backend
        run: uv run --locked ruff check .

      - name: Pyright
        working-directory: backend
        run: uv run --locked pyright

      - name: Pytest
        working-directory: backend
        run: uv run --locked pytest

      - name: Set up Node
        uses: actions/setup-node@v6
        with:
          node-version: 24
          cache: npm
          cache-dependency-path: frontend/package-lock.json

      - name: Install frontend dependencies
        working-directory: frontend
        run: npm ci

      - name: Install Playwright Chromium
        working-directory: frontend
        run: |
          if node -e "process.exit(require('./package.json').scripts['test:e2e'] ? 0 : 1)"; then
            npx playwright install --with-deps chromium
          fi

      - name: Frontend test
        working-directory: frontend
        run: npm run test --if-present

      - name: Frontend browser test
        working-directory: frontend
        run: npm run test:e2e --if-present

      - name: Frontend lint
        working-directory: frontend
        run: npm run lint

      - name: Frontend build
        working-directory: frontend
        run: npm run build'
}

install_base_hooks() {
  [[ "$NO_INSTALL_HOOKS" -eq 0 ]] || return 0
  if [[ -d ".git" ]]; then
    printf 'Installing pre-commit and pre-push hooks...\n'
    invoke_checked uv run pre-commit install
    invoke_checked uv run pre-commit install --hook-type pre-push
  else
    warn "No .git directory found. Skipping hook installation."
  fi
}

install_web_hooks() {
  [[ "$NO_INSTALL_HOOKS" -eq 0 ]] || return 0
  if [[ -d ".git" ]]; then
    printf 'Installing pre-push hook...\n'
    invoke_checked uv --project backend run pre-commit install --hook-type pre-push
  else
    warn "No .git directory found. Skipping hook installation."
  fi
}

create_web_or_game_project() {
  local backend_project_name="$PROJECT_NAME-backend"
  local backend_package_name="${PACKAGE_NAME}_backend"
  local web_template_prefix="web"
  local frontend_description="React TypeScript frontend"
  local memory_summary="Created initial web app scaffold."
  local memory_changed="Initial FastAPI backend, React TypeScript frontend, checks, CI, hooks, AGENTS.md, and memory file."
  local backend_test_template="web/test_health.py"
  local backend_test_path="test_health.py"
  local frontend_setup_extra=""

  require_npm

  if [[ "$PROFILE" == "game" ]]; then
    web_template_prefix="game"
    frontend_description="Phaser game frontend"
    memory_summary="Created initial game scaffold."
    memory_changed="Initial FastAPI backend, Phaser frontend, checks, CI, hooks, AGENTS.md, and memory file."
    backend_test_template="game/test_game_api.py"
    backend_test_path="test_game_api.py"
    frontend_setup_extra="    pushd frontend >/dev/null; npm exec playwright install chromium; popd >/dev/null"
  fi

  for existing_path in backend frontend package.json pyproject.toml; do
    if [[ -e "$existing_path" ]]; then
      die "$existing_path already exists. Run this only in a fresh project directory."
    fi
  done

  printf 'Creating %s project: %s (FastAPI backend, %s)\n' "$PROFILE" "$PROJECT_NAME" "$frontend_description"

  if [[ "$NO_GIT" -eq 0 ]]; then
    if command_exists git; then
      invoke_checked git init
    else
      warn "git was not found on PATH. Skipping git init."
    fi
  fi

  invoke_checked uv init --package --name "$backend_project_name" --python "$PYTHON_VERSION" --vcs none backend

  pushd backend >/dev/null
  invoke_checked uv add fastapi uvicorn python-dotenv
  invoke_checked uv add --dev ruff pytest pytest-cov pyright pre-commit
  popd >/dev/null

  write_text_file "backend/src/$backend_package_name/__init__.py" "def project_name() -> str:
    return \"$PROJECT_NAME\""
  write_template_file "$web_template_prefix/backend_main.py" "backend/src/$backend_package_name/main.py"
  write_template_file "$backend_test_template" "backend/tests/$backend_test_path"
  write_web_backend_pyproject_config
  write_frontend_files "$web_template_prefix"

  pushd frontend >/dev/null
  invoke_checked npm install
  if [[ "$PROFILE" == "game" ]]; then
    invoke_checked npm exec playwright install chromium
  fi
  popd >/dev/null

  write_web_common_files
  write_web_scripts
  write_text_file "README.md" "# $PROJECT_NAME

## Setup

    pushd backend >/dev/null; uv sync --dev; popd >/dev/null
    pushd frontend >/dev/null; npm install; popd >/dev/null
$frontend_setup_extra
Copy .env.example to .env only when real secrets are needed. Never commit .env.

## Commands

Backend source lives in backend/src/$backend_package_name/. Frontend source lives in frontend/src/.

    ./scripts/check.sh
    ./scripts/fix.sh
    pushd backend >/dev/null; uv run uvicorn $backend_package_name.main:app --reload; popd >/dev/null
    pushd frontend >/dev/null; npm run dev; popd >/dev/null

## Docs

Project memory lives in docs/project-memory.yaml."

  write_text_file "docs/project-memory.yaml" "entries:
  - time_utc: \"$(timestamp_utc)\"
    time_local: \"$(timestamp_local)\"
    summary: \"$memory_summary\"
    changed:
      - \"$memory_changed\"
    verification:
      - 'Not run yet; run ./scripts/check.sh before first commit.'"

  write_agents_file "$PROFILE"
  write_text_file ".pre-commit-config.yaml" 'repos:
  - repo: local
    hooks:
      - id: project-check
        name: project check
        entry: bash scripts/check.sh
        language: system
        pass_filenames: false
        stages: [pre-push]'

  write_web_ci
  install_web_hooks

  printf '\nDone. Next: ./scripts/check.sh\n'
}

create_base_project() {
  if [[ -e "pyproject.toml" ]]; then
    die "pyproject.toml already exists. Run this only in a fresh project directory."
  fi

  printf 'Creating Python project: %s (%s, Python %s, pyright %s, profile %s)\n' "$PROJECT_NAME" "$PACKAGE_NAME" "$PYTHON_VERSION" "$TYPE_MODE" "$PROFILE"

  local init_args=(init --package --name "$PROJECT_NAME" --python "$PYTHON_VERSION")
  if [[ "$NO_GIT" -eq 1 ]]; then
    init_args+=(--vcs none)
  fi
  invoke_checked uv "${init_args[@]}"

  printf 'Adding dev tooling...\n'
  invoke_checked uv add --dev ruff pytest pytest-cov pyright pre-commit

  printf 'Adding runtime dependencies...\n'
  invoke_checked uv add python-dotenv

  mkdir -p "tests"
  write_text_file "src/$PACKAGE_NAME/__init__.py" "def project_name() -> str:
    return \"$PROJECT_NAME\""
  write_text_file "tests/test_smoke.py" "from $PACKAGE_NAME import project_name


def test_project_name() -> None:
    assert project_name() == \"$PROJECT_NAME\""

  write_base_common_files
  write_text_file ".pre-commit-config.yaml" 'repos:
  - repo: local
    hooks:
      - id: ruff-format-check
        name: ruff format check
        entry: uv run ruff format --check .
        language: system
        pass_filenames: false
        stages: [pre-commit]

      - id: ruff-check
        name: ruff check
        entry: uv run ruff check .
        language: system
        pass_filenames: false
        stages: [pre-commit]

      - id: pyright
        name: pyright type check
        entry: uv run pyright
        language: system
        pass_filenames: false
        stages: [pre-push]

      - id: pytest
        name: pytest
        entry: uv run pytest
        language: system
        pass_filenames: false
        stages: [pre-push]'

  write_base_scripts
  write_text_file "README.md" "# $PROJECT_NAME

## Setup

    uv sync --dev

Copy .env.example to .env only when real secrets are needed. Never commit .env.

## Commands

Source code lives in src/$PACKAGE_NAME/. Tests live in tests/.

    ./scripts/check.sh
    ./scripts/fix.sh

## Docs

Project memory lives in docs/project-memory.yaml."

  write_text_file "docs/project-memory.yaml" "entries:
  - time_utc: \"$(timestamp_utc)\"
    time_local: \"$(timestamp_local)\"
    summary: \"Created initial $PROFILE scaffold.\"
    changed:
      - \"Initial $PROFILE project, tests, checks, CI, hooks, AGENTS.md, and memory file.\"
    verification:
      - 'Not run yet; run ./scripts/check.sh before first commit.'"

  write_agents_file "$PROFILE"
  write_base_ci
  install_base_hooks

  printf '\nDone. Next: ./scripts/check.sh\n'
}

main() {
  SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  PROJECT_ROOT="$(pwd -P)"
  HOME_ROOT="$(cd "$HOME" && pwd -P)"

  [[ -d "$PROJECT_ROOT" ]] || die "Current location is not a valid filesystem directory."
  if [[ "$PROJECT_ROOT" == "$HOME_ROOT" ]]; then
    die "Refusing to scaffold directly in HOME: $HOME_ROOT. Create and enter a project directory first."
  fi

  parse_args "$@"
  validate_args
  init_common_values
  require_uv

  if [[ "$PROFILE" == "web" || "$PROFILE" == "game" ]]; then
    create_web_or_game_project
  else
    create_base_project
  fi
}

main "$@"
