#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

# Reads one KEY from versions.env so the linters match the versions RepoSeed
# installs into generated projects.
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

ruff_version="$(pinned PY_RUFF)"
pyright_version="$(pinned PY_PYRIGHT)"

cd "$ROOT"

# Same rule set and line length as generated projects; py310 is the templates'
# requires-python floor.
uvx "ruff@$ruff_version" format --check --line-length 100 --target-version py310 templates/scripts
uvx "ruff@$ruff_version" check --line-length 100 --target-version py310 \
  --select E,F,I,B,UP,SIM,C4,PT,RUF templates/scripts
uvx --from "pyright==$pyright_version" pyright -p tests/pyright-script-templates.json

printf 'script template lint passed\n'
