# Cycle 1: Python + CI Hardening — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every generated project (all profiles, both platforms) gains dependency auditing, secret/hygiene protection, broader ruff rules, SHA-pinned hardened CI, Dependabot, and repo-quality files, with `--no-security` / `--no-vscode` opt-outs.

**Architecture:** All changes live inside the two generator scripts (`new-project.sh`, `new-project.ps1`) as new/extended heredoc templates. No new dependencies. Verification extends the four existing test scripts; no new test files.

**Tech Stack:** Bash, PowerShell 7, uv (`uv audit`, `uv lock --check`), ruff, pre-commit, GitHub Actions YAML, Dependabot config.

**Spec:** `docs/superpowers/specs/2026-08-14-cycle1-python-ci-hardening-design.md`

## Global Constraints

- Ruff `select` additions, exact strings: `"S"`, `"PIE"`, `"TC"`, `"T10"`, `"ERA"` (current prefixes; `TCH` is the deprecated name — never use it).
- Every generated pyproject gains exactly: `[tool.ruff.lint.per-file-ignores]` with `"tests/**" = ["S101"]`, and `docstring-code-format = true` under `[tool.ruff.format]`.
- Check scripts gain `uv lock --check` then `uv audit` (PowerShell: `Invoke-Checked uv lock --check` then `Invoke-Checked uv audit`) immediately before the first `uv run` line of the Python block. `fix.*` scripts are NOT modified.
- Action SHA pins (resolved via `git ls-remote` at planning; use verbatim):
  - `actions/checkout` → `d23441a48e516b6c34aea4fa41551a30e30af803` # v6.1.0
  - `astral-sh/setup-uv` → `fac544c07dec837d0ccb6301d7b5580bf5edae39` # v8.2.0
  - `actions/setup-node` → `249970729cb0ef3589644e2896645e5dc5ba9c38` # v6.5.0
  - `step-security/harden-runner` → `b09bb98e06d4d774595224525879c09bc6e98c40` # v2.20.1
  - `gitleaks/gitleaks-action` → `ff98106e4c7b2bc287b24eaf42907196329070c7` # v2.3.9
- Actionlint download script pinned to tag: `https://raw.githubusercontent.com/rhysd/actionlint/v1.7.12/scripts/download-actionlint.bash`
- pre-commit hygiene repo: `https://github.com/pre-commit/pre-commit-hooks` at `rev: v6.0.0`, hook ids: `check-yaml`, `check-json`, `check-toml`, `end-of-file-fixer`, `trailing-whitespace`, `mixed-line-ending`, `detect-private-key`, `check-merge-conflict`, `check-case-conflict`. No `stages:` key. Placed BEFORE the existing `repo: local` block; the local block stays byte-identical.
- NO gitleaks or actionlint entry in `.pre-commit-config.yaml` (they require Go/Docker locally — design deviation D3 in spec).
- New flags: bash `--no-security`, `--no-vscode` (vars `NO_SECURITY`, `NO_VSCODE`, default 0); PowerShell `[switch]$NoSecurity`, `[switch]$NoVscode`.
- `--no-security` affects ONLY the two audit lines in check scripts. CI hardening, Dependabot, pre-commit, and ruff changes are unconditional.
- New files are always generated (except `.vscode` files gated by `--no-vscode`): `SECURITY.md`, `.github/PULL_REQUEST_TEMPLATE.md`, `.git-blame-ignore-revs`. `.github/dependabot.yml` is generated only when GitHub Actions generation is enabled.
- `.gitignore`: replace the single `.vscode/` line with the three-line pattern `.vscode/*` / `!.vscode/settings.json` / `!.vscode/extensions.json` (always, regardless of `--no-vscode`).
- Bash heredoc quoting rules: `write_text_file "..."` bodies shown below are double-quoted strings — every literal `"` inside them must be written `\"` in the bash source (matches existing style). Where a body below is shown single-quoted in bash source (backtick-containing content), keep it single-quoted.
- Test harness on this machine:
  - Bash tests run via Git Bash: `& "$env:USERPROFILE\scoop\apps\git\current\bin\bash.exe" tests/<script>` from repo root (PowerShell).
  - PowerShell tests: `pwsh -NoProfile -File tests/<script>`.
  - `scaffold_e2e.ps1` and `scaffold_e2e.sh` are slow (real uv+npm installs). Fast contracts: `cross_platform_contract.sh`, `powershell_web_contract.ps1`.
  - Known pre-existing environment quirk: `cross_platform_contract.sh`'s pwsh subsection fails under git-bash (bash-script fake `uv`); Task 1 adds the MINGW/MSYS skip.

## File Structure

All changes to existing files. No new repo files except docs.

| File | Responsibility |
|---|---|
| `new-project.sh` | Bash generator: ruff config, check scripts, flags, gitignore, pre-commit, CI, Dependabot, repo-quality files |
| `new-project.ps1` | PowerShell generator: identical content for base/desktop/web/game |
| `tests/cross_platform_contract.sh` | Fast bash-side contract: content assertions + MINGW skip |
| `tests/scaffold_e2e.sh` | Bash e2e: assertions + real check runs |
| `tests/powershell_web_contract.ps1` | Fast PS-side contract: content assertions + flag variants |
| `tests/scaffold_e2e.ps1` | PS e2e: assertions + real check runs |
| `README.md`, `CHANGELOG.md` | Document new generated content and flags |

---

### Task 1: Bash scaffolder — Python-side hardening + bash contract updates

**Task Position**

- **Feature goal:** Cycle 1 Python + CI hardening of generated projects.
- **Previously:** Baseline `main` at `238f005`; spec + plan committed as planning artifact. All four test suites at their current state (bash contract fails on this machine only in its pwsh subsection — environment quirk fixed in this task).
- **Current:** The bash scaffolder generates hardened Python-side output (ruff rules, check-script audit lines, hygiene pre-commit, gitignore pattern, repo-quality files, new flags), and the bash contract test verifies all of it and runs green on this machine.
- **Next:** Task 2 adds bash CI + Dependabot generation and their contract assertions. It expects `NO_SECURITY`/`NO_VSCODE` parsing and `write_repo_quality_files()` from this task to exist.
- **Do not do yet:** Any CI/Dependabot changes. Any PowerShell changes.

**Files:**
- Modify: `new-project.sh` — defaults block (~24-26), `usage()` (~28-44), `parse_args` (~146-190), base ruff config (~235-252), web/game ruff config (~575-581), base check script (~383-389), game check script (~494-509), web check script (~529-544), base `.gitignore` (~373), web/game `.gitignore` (~483), new `write_repo_quality_files()` (insert after `write_base_scripts`, ~401), web/game pre-commit (~1189-1197), base pre-commit (~1234-1263), call sites in `create_web_project` (~1199) and `create_base_project` (~1265)
- Modify: `tests/cross_platform_contract.sh`
- Modify: `tests/scaffold_e2e.sh`

**Interfaces:**
- Consumes: existing `write_text_file` / `add_text_file` helpers, `$PROFILE`, `$NO_GITHUB_ACTIONS`-style flag pattern.
- Produces (used by Task 2): `NO_SECURITY` and `NO_VSCODE` parsed flags; `write_repo_quality_files()` function; check scripts whose Python block starts with the security lines.

- [ ] **Step 1: Write the failing contract assertions (bash)**

In `tests/cross_platform_contract.sh`:

1a. In `run_powershell_contract_if_available()` (line 144), insert at the top of the function body:

```bash
  if [[ "$(uname -s)" == MINGW* || "$(uname -s)" == MSYS* ]]; then
    printf 'Skipping PowerShell contract: git-bash on Windows (run powershell_web_contract.ps1 instead)\n'
    return
  fi
```

1b. In `run_base_scaffold_contract()` (line 121): remove `--no-github-actions` from the `"$ROOT/new-project.sh"` invocation (keep `--name bash-base-demo --no-git --no-install-hooks`), so CI/Dependabot files are generated for content assertions in Task 2. Then append these assertions after the existing scaffold call (before the AGENTS.md check):

```bash
  assert_file_contains "$project_dir/pyproject.toml" '"S",    # flake8-bandit: security'
  assert_file_contains "$project_dir/pyproject.toml" '"PIE",  # flake8-pie: misc improvements'
  assert_file_contains "$project_dir/pyproject.toml" '"TC",   # flake8-type-checking: typing-only imports'
  assert_file_contains "$project_dir/pyproject.toml" '"T10",  # flake8-debugger: debugger imports'
  assert_file_contains "$project_dir/pyproject.toml" '"ERA"   # eradicate: commented-out code'
  assert_file_contains "$project_dir/pyproject.toml" '"tests/**" = ["S101"]'
  assert_file_contains "$project_dir/pyproject.toml" 'docstring-code-format = true'

  assert_file_contains "$project_dir/scripts/check.sh" 'uv lock --check
uv audit
uv run ruff format --check .'

  assert_file_contains "$project_dir/.pre-commit-config.yaml" 'rev: v6.0.0'
  assert_file_contains "$project_dir/.pre-commit-config.yaml" '- id: check-yaml'
  assert_file_contains "$project_dir/.pre-commit-config.yaml" '- id: detect-private-key'
  assert_file_contains "$project_dir/.pre-commit-config.yaml" '- id: check-case-conflict'
  assert_file_contains "$project_dir/.pre-commit-config.yaml" '- id: ruff-format-check'
  assert_file_not_contains "$project_dir/.pre-commit-config.yaml" 'gitleaks'
  assert_file_not_contains "$project_dir/.pre-commit-config.yaml" 'actionlint'

  for repo_file in "SECURITY.md" ".github/PULL_REQUEST_TEMPLATE.md" ".git-blame-ignore-revs" ".vscode/settings.json" ".vscode/extensions.json"; do
    [[ -f "$project_dir/$repo_file" ]] || {
      printf 'Expected repo quality file: %s\n' "$project_dir/$repo_file" >&2
      exit 1
    }
  done
  assert_file_contains "$project_dir/.gitignore" '!.vscode/settings.json'
  assert_file_contains "$project_dir/.vscode/extensions.json" '"charliermarsh.ruff"'
```

1c. Add a new function after `run_base_scaffold_contract()` for the flag negatives:

```bash
run_no_security_no_vscode_contract() {
  local tmp_root project_dir
  tmp_root="$(mktemp -d)"
  prepend_fake_uv "$tmp_root/bin"
  project_dir="$tmp_root/bash-base-nosec"
  mkdir -p "$project_dir"

  pushd "$project_dir" >/dev/null
  "$ROOT/new-project.sh" \
    --name bash-base-nosec \
    --no-git \
    --no-install-hooks \
    --no-github-actions \
    --no-security \
    --no-vscode
  popd >/dev/null

  assert_file_not_contains "$project_dir/scripts/check.sh" 'uv audit'
  assert_file_contains "$project_dir/scripts/check.sh" 'uv run ruff format --check .'
  if [[ -e "$project_dir/.vscode" ]]; then
    printf 'Expected no .vscode directory with --no-vscode\n' >&2
    exit 1
  fi
  [[ -f "$project_dir/SECURITY.md" ]] || {
    printf 'Expected SECURITY.md even with --no-security/--no-vscode\n' >&2
    exit 1
  }
}
```

Call it at the bottom runner list:

```bash
run_bash_install_contract
run_windows_installer_static_contract
run_base_scaffold_contract
run_no_security_no_vscode_contract
run_powershell_contract_if_available
```

- [ ] **Step 2: Run the contract, verify the expected failures**

Run: `& "$env:USERPROFILE\scoop\apps\git\current\bin\bash.exe" tests/cross_platform_contract.sh`
Expected: FAIL — first failure is `Expected .../pyproject.toml to contain: "S",    # flake8-bandit: security` (or an unknown-option error for `--no-security`, depending on which assertion runs first — both prove the work is missing). Also confirm the new MINGW skip line prints `Skipping PowerShell contract: ...` instead of the pwsh error.

- [ ] **Step 3: Implement the bash scaffolder changes**

3a. Defaults block (~line 24-26): add after `NO_GITHUB_ACTIONS=0`:

```bash
NO_SECURITY=0
NO_VSCODE=0
```

3b. `usage()` (~line 41): add after the `--no-github-actions` line:

```
  --no-security             Skip uv lock --check and uv audit in check scripts.
  --no-vscode               Skip .vscode settings and extensions files.
```

3c. `parse_args` (~line 177-180): add after the `--no-github-actions)` case:

```bash
      --no-security)
        NO_SECURITY=1
        ;;
      --no-vscode)
        NO_VSCODE=1
        ;;
```

3d. Base ruff config in `write_base_common_files` (~235-252). Replace the select list tail and add per-file-ignores + format option. New block (remember `\"` escaping in the double-quoted bash string):

```bash
select = [
    \"E\",    # pycodestyle errors
    \"F\",    # Pyflakes
    \"I\",    # import sorting
    \"B\",    # bugbear: likely bugs
    \"UP\",   # pyupgrade: modern Python syntax
    \"SIM\",  # simplifications
    \"C4\",   # cleaner comprehensions
    \"PT\",   # pytest style
    \"RUF\",  # Ruff-specific rules
    \"S\",    # flake8-bandit: security
    \"PIE\",  # flake8-pie: misc improvements
    \"TC\",   # flake8-type-checking: typing-only imports
    \"T10\",  # flake8-debugger: debugger imports
    \"ERA\"   # eradicate: commented-out code
]
ignore = []

[tool.ruff.lint.per-file-ignores]
\"tests/**\" = [\"S101\"]

[tool.ruff.format]
quote-style = \"double\"
indent-style = \"space\"
line-ending = \"auto\"
docstring-code-format = true
```

3e. Web/game ruff config in `write_web_backend_pyproject_config` (~575-581). Replace:

```bash
select = [\"E\", \"F\", \"I\", \"B\", \"UP\", \"SIM\", \"C4\", \"PT\", \"RUF\"]
ignore = []
```

with:

```bash
select = [\"E\", \"F\", \"I\", \"B\", \"UP\", \"SIM\", \"C4\", \"PT\", \"RUF\", \"S\", \"PIE\", \"TC\", \"T10\", \"ERA\"]
ignore = []

[tool.ruff.lint.per-file-ignores]
\"tests/**\" = [\"S101\"]
```

and add `docstring-code-format = true` after `line-ending = \"auto\"` in its `[tool.ruff.format]` section.

3f. Base check script in `write_base_scripts` (~383-389). Replace the single `write_text_file "scripts/check.sh"` call with:

```bash
  if [[ "$NO_SECURITY" -eq 0 ]]; then
    write_text_file "scripts/check.sh" '#!/usr/bin/env bash
set -euo pipefail

uv lock --check
uv audit
uv run ruff format --check .
uv run ruff check .
uv run pyright
uv run pytest'
  else
    write_text_file "scripts/check.sh" '#!/usr/bin/env bash
set -euo pipefail

uv run ruff format --check .
uv run ruff check .
uv run pyright
uv run pytest'
  fi
```

Leave `scripts/fix.sh` and the `chmod` untouched.

3g. Game check script (~494-509). Wrap in the same `if [[ "$NO_SECURITY" -eq 0 ]]` conditional. Security-on body:

```bash
    write_text_file "scripts/check.sh" '#!/usr/bin/env bash
set -euo pipefail

pushd backend >/dev/null
uv lock --check
uv audit
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
```

The else branch is identical minus the `uv lock --check` and `uv audit` lines.

3h. Web check script (~529-544). Same pattern as 3g with the web frontend block (`npm run test` / `npm run typecheck` / `npm run lint` / `npm run build`).

3i. `.gitignore` fixes — in the base `.gitignore` (~line 373) and web/game `.gitignore` (~line 483), replace the line `.vscode/` with:

```
.vscode/*
!.vscode/settings.json
!.vscode/extensions.json
```

3j. New function after `write_base_scripts` (~line 401):

```bash
write_repo_quality_files() {
  write_text_file "SECURITY.md" '# Security Policy

## Reporting a Vulnerability

Report security issues privately to the repository maintainer.
Please do not open public issues for security problems.'

  mkdir -p ".github"
  write_text_file ".github/PULL_REQUEST_TEMPLATE.md" '## Summary

<!-- What changed and why -->

## Checks

- [ ] `./scripts/check.sh` passes (or `.\scripts\check.ps1` on Windows)'

  write_text_file ".git-blame-ignore-revs" '# Commits excluded from `git blame` (e.g. bulk formatting commits).
# Enable with: git config blame.ignoreRevsFile .git-blame-ignore-revs'

  if [[ "$NO_VSCODE" -eq 0 ]]; then
    mkdir -p ".vscode"
    write_text_file ".vscode/settings.json" '{
  "[python]": {
    "editor.defaultFormatter": "charliermarsh.ruff",
    "editor.codeActionsOnSave": {
      "source.fixAll.ruff": "explicit",
      "source.organizeImports.ruff": "explicit"
    }
  }
}'
    local extensions='["ms-python.python", "charliermarsh.ruff"]'
    if [[ "$PROFILE" == "web" || "$PROFILE" == "game" ]]; then
      extensions='["ms-python.python", "charliermarsh.ruff", "dbaeumer.vscode-eslint"]'
    fi
    write_text_file ".vscode/extensions.json" "$extensions"
  fi
}
```

3k. Call sites: in `create_web_project`, add `write_repo_quality_files` on its own line immediately before `write_web_ci` (~line 1199). In `create_base_project`, add it immediately after `write_base_scripts` (~line 1265).

3l. Pre-commit configs. Web/game (~1189): replace `write_text_file ".pre-commit-config.yaml" 'repos:` + following block with:

```bash
  write_text_file ".pre-commit-config.yaml" 'repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v6.0.0
    hooks:
      - id: check-yaml
      - id: check-json
      - id: check-toml
      - id: end-of-file-fixer
      - id: trailing-whitespace
      - id: mixed-line-ending
      - id: detect-private-key
      - id: check-merge-conflict
      - id: check-case-conflict

  - repo: local
    hooks:
      - id: project-check
        name: project check
        entry: bash scripts/check.sh
        language: system
        pass_filenames: false
        stages: [pre-push]'
```

Base (~1234): prepend the identical `pre-commit/pre-commit-hooks` block (same 15 lines ending with a blank line) before `  - repo: local`; the existing four local hooks stay byte-identical.

- [ ] **Step 4: Run the contract, verify pass**

Run: `& "$env:USERPROFILE\scoop\apps\git\current\bin\bash.exe" tests/cross_platform_contract.sh`
Expected: `cross-platform contract tests passed` (with the MINGW skip line), exit 0.

- [ ] **Step 5: Extend `tests/scaffold_e2e.sh` and run it**

5a. In `run_scaffold_case`, after `assert_pyright_venv_config` and before the web-specific block, add:

```bash
  local pyproject_path="$project_dir/pyproject.toml"
  if [[ "$profile" == "web" || "$profile" == "game" ]]; then
    pyproject_path="$project_dir/backend/pyproject.toml"
  fi
  assert_file_contains "$pyproject_path" '"ERA"'
  assert_file_contains "$pyproject_path" '"tests/**" = ["S101"]'
  assert_file_contains "$pyproject_path" 'docstring-code-format = true'
  assert_file_contains "$project_dir/scripts/check.sh" 'uv lock --check
uv audit'
  assert_file_contains "$project_dir/.pre-commit-config.yaml" 'rev: v6.0.0'
  [[ -f "$project_dir/SECURITY.md" ]] || { printf 'Expected SECURITY.md\n' >&2; exit 1; }
  [[ -f "$project_dir/.vscode/settings.json" ]] || { printf 'Expected .vscode/settings.json\n' >&2; exit 1; }
```

5b. Run: `& "$env:USERPROFILE\scoop\apps\git\current\bin\bash.exe" tests/scaffold_e2e.sh`
Expected: `base scaffold e2e passed`, `web scaffold e2e passed`, exit 0 — including real `uv lock --check` + `uv audit` executions inside `run_project_checks`. If the run fails for git-bash/POSIX-path environment reasons (e.g. `UV_CACHE_DIR=/tmp/...` confusing Windows uv.exe), record the exact failure in the task report as an environment limitation: content coverage stands in via the contract suite, and the identical generated semantics are proven by `scaffold_e2e.ps1` in Task 4. Do not silently skip — document.

- [ ] **Step 6: Commit**

```bash
git add new-project.sh tests/cross_platform_contract.sh tests/scaffold_e2e.sh
git commit -m "feat(bash): harden generated python checks, hooks, and repo files"
```

**Task Boundary Verification**

- Fast: `& "$env:USERPROFILE\scoop\apps\git\current\bin\bash.exe" tests/cross_platform_contract.sh` → exit 0.
- Slow (attempt + document): `& "$env:USERPROFILE\scoop\apps\git\current\bin\bash.exe" tests/scaffold_e2e.sh` → exit 0 or documented environment limitation.
- Expected known failures: none.
- Next task may assume: flags parsed; `write_repo_quality_files()` exists and is called by both bash flows; bash CI generation (`write_base_ci`, `write_web_ci`) untouched.

---

### Task 2: Bash CI + Dependabot + CI contract assertions

**Task Position**

- **Previously:** Task 1 delivered hardened bash Python-side output, flags, `write_repo_quality_files()`, and the bash contract runs green on this machine (with MINGW skip).
- **Current:** All three bash CI heredocs become SHA-pinned, concurrent, hardened, actionlint- and gitleaks-augmented, with a `uv audit` step; Dependabot config is generated; the bash contract asserts the CI content.
- **Next:** Task 3 ports every Python-side change to `new-project.ps1`. It expects the final generated-file vocabulary from Tasks 1-2 to be stable.
- **Do not do yet:** Any PowerShell changes.

**Files:**
- Modify: `new-project.sh` — `write_base_ci` (~886-924), game CI (~930-1003), web CI (~1005-1071)
- Modify: `tests/cross_platform_contract.sh`

**Interfaces:**
- Consumes: `NO_GITHUB_ACTIONS` gate; Global Constraints SHA table.
- Produces: canonical CI YAML bodies that Task 4 reproduces byte-for-byte in `new-project.ps1`.

- [ ] **Step 1: Write the failing CI contract assertions**

In `tests/cross_platform_contract.sh`, inside `run_base_scaffold_contract()` after the repo-quality assertions from Task 1, add:

```bash
  local ci_path="$project_dir/.github/workflows/ci.yml"
  local dependabot_path="$project_dir/.github/dependabot.yml"

  assert_file_contains "$ci_path" 'concurrency:'
  assert_file_contains "$ci_path" 'cancel-in-progress: true'
  assert_file_contains "$ci_path" 'harden-runner@b09bb98e06d4d774595224525879c09bc6e98c40 # v2.20.1'
  assert_file_contains "$ci_path" 'actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803 # v6.1.0'
  assert_file_contains "$ci_path" 'astral-sh/setup-uv@fac544c07dec837d0ccb6301d7b5580bf5edae39 # v8.2.0'
  assert_file_contains "$ci_path" 'actionlint/v1.7.12/scripts/download-actionlint.bash'
  assert_file_contains "$ci_path" '- name: Dependency audit'
  assert_file_contains "$ci_path" 'run: uv audit'
  assert_file_contains "$ci_path" 'gitleaks/gitleaks-action@ff98106e4c7b2bc287b24eaf42907196329070c7 # v2.3.9'
  assert_file_contains "$ci_path" 'fetch-depth: 0'
  assert_file_not_contains "$ci_path" 'actions/checkout@v6'
  assert_file_not_contains "$ci_path" 'setup-uv@v8'
  assert_file_not_contains "$ci_path" 'setup-node@v6'

  assert_file_contains "$dependabot_path" 'package-ecosystem: uv'
  assert_file_contains "$dependabot_path" 'package-ecosystem: github-actions'
  assert_file_not_contains "$dependabot_path" 'package-ecosystem: npm'
```

- [ ] **Step 2: Run, verify failure**

Run: `& "$env:USERPROFILE\scoop\apps\git\current\bin\bash.exe" tests/cross_platform_contract.sh`
Expected: FAIL on `Expected .../ci.yml to contain: concurrency:`.

- [ ] **Step 3: Implement the three CI bodies + Dependabot**

3a. Replace `write_base_ci`'s heredoc with (single-quoted heredoc; `${{ }}` is literal):

```bash
write_base_ci() {
  [[ "$NO_GITHUB_ACTIONS" -eq 0 ]] || return 0
  mkdir -p ".github/workflows"
  write_text_file ".github/workflows/ci.yml" 'name: ci

on:
  push:
  pull_request:

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  check:
    runs-on: ubuntu-latest

    steps:
      - name: Harden runner
        uses: step-security/harden-runner@b09bb98e06d4d774595224525879c09bc6e98c40 # v2.20.1

      - uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803 # v6.1.0

      - name: Lint workflow files
        run: |
          bash <(curl -fsSL https://raw.githubusercontent.com/rhysd/actionlint/v1.7.12/scripts/download-actionlint.bash)
          ./actionlint

      - name: Install uv
        uses: astral-sh/setup-uv@fac544c07dec837d0ccb6301d7b5580bf5edae39 # v8.2.0
        with:
          enable-cache: true

      - name: Install Python
        run: uv python install

      - name: Sync dependencies
        run: uv sync --locked --dev

      - name: Dependency audit
        run: uv audit

      - name: Ruff format check
        run: uv run --locked ruff format --check .

      - name: Ruff lint
        run: uv run --locked ruff check .

      - name: Pyright
        run: uv run --locked pyright

      - name: Pytest
        run: uv run --locked pytest

  gitleaks:
    runs-on: ubuntu-latest

    steps:
      - name: Harden runner
        uses: step-security/harden-runner@b09bb98e06d4d774595224525879c09bc6e98c40 # v2.20.1

      - uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803 # v6.1.0
        with:
          fetch-depth: 0

      - uses: gitleaks/gitleaks-action@ff98106e4c7b2bc287b24eaf42907196329070c7 # v2.3.9
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}'

  write_text_file ".github/dependabot.yml" 'version: 2
updates:
  - package-ecosystem: uv
    directory: /
    schedule:
      interval: weekly

  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly'
}
```

3b. Game CI (~930-1003) and web CI (~1005-1071): apply the identical transformation. Both bodies get, in this order: the `concurrency:` block after `on:`; `Harden runner` as the first step; SHA-pinned `checkout` + `Lint workflow files` step (same two lines as base); SHA-pinned `setup-uv`; `Dependency audit` step with `working-directory: backend` inserted immediately after the `Install backend dependencies` (`uv sync --locked --dev`) step; all backend `working-directory: backend` steps unchanged otherwise; SHA-pinned `actions/setup-node@249970729cb0ef3589644e2896645e5dc5ba9c38 # v6.5.0`; frontend steps unchanged; then the same `gitleaks:` job appended at the end. The game body additionally keeps its existing Playwright install step (`npx playwright install --with-deps chromium`) and frontend `test:e2e` steps exactly as they are.

3c. Web/game Dependabot — inside `write_web_ci`, after the game/web `ci.yml` write, add (both branches share it; write it once after the `if/else` closes, before the closing brace):

```bash
  write_text_file ".github/dependabot.yml" 'version: 2
updates:
  - package-ecosystem: uv
    directory: /backend
    schedule:
      interval: weekly

  - package-ecosystem: npm
    directory: /frontend
    schedule:
      interval: weekly

  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly'
}
```

Note: web/game uv directory is `/backend` (lockfile lives there), which differs from base's `/`.

- [ ] **Step 4: Run the contract, verify pass**

Run: `& "$env:USERPROFILE\scoop\apps\git\current\bin\bash.exe" tests/cross_platform_contract.sh`
Expected: `cross-platform contract tests passed`, exit 0.

- [ ] **Step 5: YAML sanity spot-check**

Generate a base project manually and confirm actionlint-clean YAML locally (fast, no network beyond the one download):

```powershell
$tmp = Join-Path $env:TEMP ("rs-ci-check-" + [guid]::NewGuid().ToString("N").Substring(0,8))
New-Item -ItemType Directory -Path $tmp | Out-Null
Push-Location $tmp
& "$env:USERPROFILE\scoop\apps\git\current\bin\bash.exe" ..\..\..\..\Documents\Development\repoSeed\new-project.sh --name ci-check --no-git --no-install-hooks
Pop-Location
Get-Content "$tmp\.github\workflows\ci.yml" -Raw | Out-Null   # readable inspection
Remove-Item -Recurse -Force $tmp
```

Inspect that the file contains both jobs and valid indentation (visual check of the generated YAML is sufficient; actionlint itself runs in generated CI).

- [ ] **Step 6: Commit**

```bash
git add new-project.sh tests/cross_platform_contract.sh
git commit -m "feat(bash): harden generated CI and add dependabot"
```

**Task Boundary Verification**

- Fast: `& "$env:USERPROFILE\scoop\apps\git\current\bin\bash.exe" tests/cross_platform_contract.sh` → exit 0.
- Expected known failures: none.
- Next task may assume: canonical bash CI/Dependabot bodies final; bash scaffolder complete for cycle 1.

---

### Task 3: PowerShell scaffolder — Python-side hardening + PS contract updates

**Task Position**

- **Previously:** Tasks 1-2 finished the bash scaffolder completely (Python-side + CI + Dependabot) with green bash contract.
- **Current:** `new-project.ps1` gains every Python-side change (ruff, check scripts, flags, gitignore, pre-commit, repo-quality files) with base/desktop/web/game coverage; `powershell_web_contract.ps1` verifies content + flag negatives.
- **Next:** Task 4 ports CI + Dependabot to `new-project.ps1` and runs the full slow PS e2e.
- **Do not do yet:** CI/Dependabot in ps1 (Task 4). Any bash changes (done).

**Files:**
- Modify: `new-project.ps1` — param block (line 12-14 area), web/game ruff config (~251-256), base/desktop ruff config (~1164-1181), game check (~721-727), web check (~745-784), base check (~1369-1372), web/game `.gitignore` (~690), base `.gitignore` (~1308), new `Write-RepoQualityFiles` function + call sites (web flow after ~925; base flow after ~1349), web pre-commit (~915-925), base pre-commit (~1318-1349)
- Modify: `tests/powershell_web_contract.ps1`

**Interfaces:**
- Consumes: `$Profile`, `$NoSecurity`, `$NoVscode`, existing `Write-TextFile` / `Add-TextFile`.
- Produces: PS-generated Python-side artifacts byte-equivalent to bash ones (same rule strings, same check lines with `Invoke-Checked` prefix, same pre-commit block, same new files).

- [ ] **Step 1: Write the failing PS contract assertions**

In `tests/powershell_web_contract.ps1`:

1a. After the existing vite config assertions (~line 134), add:

```powershell
    $BackendPyproject = Join-Path $ProjectDir "backend/pyproject.toml"
    Assert-Contains -Path $BackendPyproject -Expected '"S", "PIE", "TC", "T10", "ERA"'
    Assert-Contains -Path $BackendPyproject -Expected '"tests/**" = ["S101"]'
    Assert-Contains -Path $BackendPyproject -Expected 'docstring-code-format = true'

    Assert-InOrder -Path $CheckScript -Expected @(
        'Invoke-Checked uv lock --check'
        'Invoke-Checked uv audit'
        'Invoke-Checked uv run ruff format --check .'
    )
    Assert-NotContains -Path $FixScript -Unexpected 'uv audit'
    Assert-NotContains -Path $FixScript -Unexpected 'uv lock --check'

    Assert-Contains -Path $PreCommit -Expected 'rev: v6.0.0'
    Assert-Contains -Path $PreCommit -Expected '- id: check-yaml'
    Assert-Contains -Path $PreCommit -Expected '- id: detect-private-key'
    Assert-Contains -Path $PreCommit -Expected 'powershell -ExecutionPolicy Bypass -File scripts/check.ps1'
    Assert-NotContains -Path $PreCommit -Unexpected 'gitleaks'
    Assert-NotContains -Path $PreCommit -Unexpected 'actionlint'

    foreach ($RepoFile in @("SECURITY.md", ".github/PULL_REQUEST_TEMPLATE.md", ".git-blame-ignore-revs", ".vscode/settings.json", ".vscode/extensions.json")) {
        if (-not (Test-Path -LiteralPath (Join-Path $ProjectDir $RepoFile))) {
            throw "Expected repo quality file: $RepoFile"
        }
    }
    Assert-Contains -Path (Join-Path $ProjectDir ".gitignore") -Expected '!.vscode/settings.json'
    Assert-Contains -Path (Join-Path $ProjectDir ".vscode/extensions.json") -Expected 'dbaeumer.vscode-eslint'
```

1b. At the end of the `try` block (after the existing CI assertions, before `Write-Host "PowerShell web contract passed"`), add a second scaffold with the new flags:

```powershell
    $NosecDir = Join-Path $TmpRoot "ps-web-nosec"
    New-Item -ItemType Directory -Path $NosecDir -Force | Out-Null
    Push-Location $NosecDir
    try {
        & "$PSScriptRoot\..\new-project.ps1" -Name ps-web-nosec -Profile web -NoGit -NoInstallHooks -NoSecurity -NoVscode
    }
    finally {
        Pop-Location
    }
    $NosecCheck = Join-Path $NosecDir "scripts/check.ps1"
    Assert-NotContains -Path $NosecCheck -Unexpected 'uv audit'
    Assert-NotContains -Path $NosecCheck -Unexpected 'uv lock --check'
    Assert-Contains -Path $NosecCheck -Expected 'Invoke-Checked uv run ruff format --check .'
    if (Test-Path -LiteralPath (Join-Path $NosecDir ".vscode")) {
        throw "Expected no .vscode directory with -NoVscode"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $NosecDir "SECURITY.md"))) {
        throw "Expected SECURITY.md even with -NoSecurity/-NoVscode"
    }
```

- [ ] **Step 2: Run, verify failure**

Run: `pwsh -NoProfile -File tests/powershell_web_contract.ps1`
Expected: FAIL on `Expected ...\backend\pyproject.toml to contain: "S", "PIE", "TC", "T10", "ERA"` (or a `-NoSecurity` parameter-bind error on the second scaffold — both prove the work is missing).

- [ ] **Step 3: Implement the PowerShell changes**

3a. Param block: add after `[switch]$NoGitHubActions`:

```powershell
    [switch]$NoSecurity,
    [switch]$NoVscode
```

3b. Web/game ruff config (~251-256, inside the `@"..."@` here-string): replace the single-line select with:

```
select = ["E", "F", "I", "B", "UP", "SIM", "C4", "PT", "RUF", "S", "PIE", "TC", "T10", "ERA"]
ignore = []

[tool.ruff.lint.per-file-ignores]
"tests/**" = ["S101"]
```

and add `docstring-code-format = true` after `line-ending = "auto"` in its `[tool.ruff.format]` section.

3c. Base/desktop ruff config (~1165-1181): mirror Task 1 step 3d exactly (same comments, same ordering; plain quotes here — the ps1 here-string needs no escaping):

```
select = [
    "E",    # pycodestyle errors
    "F",    # Pyflakes
    "I",    # import sorting
    "B",    # bugbear: likely bugs
    "UP",   # pyupgrade: modern Python syntax
    "SIM",  # simplifications
    "C4",   # cleaner comprehensions
    "PT",   # pytest style
    "RUF",  # Ruff-specific rules
    "S",    # flake8-bandit: security
    "PIE",  # flake8-pie: misc improvements
    "TC",   # flake8-type-checking: typing-only imports
    "T10",  # flake8-debugger: debugger imports
    "ERA"   # eradicate: commented-out code
]
ignore = []

[tool.ruff.lint.per-file-ignores]
"tests/**" = ["S101"]

[tool.ruff.format]
quote-style = "double"
indent-style = "space"
line-ending = "auto"
docstring-code-format = true
```

3d. Check scripts — three sites. Game (~721-727) and web (~745-784): inside the `Push-Location backend` `try {` block, before `Invoke-Checked uv run ruff format --check .`, insert (conditionally):

```powershell
    Invoke-Checked uv lock --check
    Invoke-Checked uv audit
```

Implementation shape per site (matching the file's branching style):

```powershell
        $checkBody = @'
$ErrorActionPreference = "Stop"

function Invoke-Checked {
    ...
}

$Npm = ...

Push-Location backend
try {
__SECURITY_CHECKS__    Invoke-Checked uv run ruff format --check .
    ...
'@
        $securityChecks = "    Invoke-Checked uv lock --check`n    Invoke-Checked uv audit`n"
        if ($NoSecurity) { $securityChecks = "" }
        $checkBody = $checkBody.Replace("__SECURITY_CHECKS__", $securityChecks)
        Write-TextFile -Path (Join-Path "scripts" "check.ps1") -Content $checkBody
```

Use this exact marker technique for the game, web, and base check-script sites (base site ~1369: marker goes before `Invoke-Checked uv run ruff format --check .` after the function definition; there is no `Push-Location backend`). This keeps the bodies single-source. The marker must be removed from the final output in both branches (verified by Step 1's `Assert-InOrder`, which fails if `__SECURITY_CHECKS__` text survives).

3e. `.gitignore` — both sites (~690 web/game, ~1308 base): replace `.vscode/` with:

```
.vscode/*
!.vscode/settings.json
!.vscode/extensions.json
```

3f. New function `Write-RepoQualityFiles` (place near `Write-TextFile` definition or before the web flow; follow the file's function style):

```powershell
function Write-RepoQualityFiles {
    Write-TextFile -Path "SECURITY.md" -Content @'
# Security Policy

## Reporting a Vulnerability

Report security issues privately to the repository maintainer.
Please do not open public issues for security problems.
'@

    New-Item -ItemType Directory -Path ".github" -Force | Out-Null
    Write-TextFile -Path (Join-Path ".github" "PULL_REQUEST_TEMPLATE.md") -Content @'
## Summary

<!-- What changed and why -->

## Checks

- [ ] `./scripts/check.sh` passes (or `.\scripts\check.ps1` on Windows)
'@

    Write-TextFile -Path ".git-blame-ignore-revs" -Content @'
# Commits excluded from `git blame` (e.g. bulk formatting commits).
# Enable with: git config blame.ignoreRevsFile .git-blame-ignore-revs
'@

    if (-not $NoVscode) {
        New-Item -ItemType Directory -Path ".vscode" -Force | Out-Null
        Write-TextFile -Path (Join-Path ".vscode" "settings.json") -Content @'
{
  "[python]": {
    "editor.defaultFormatter": "charliermarsh.ruff",
    "editor.codeActionsOnSave": {
      "source.fixAll.ruff": "explicit",
      "source.organizeImports.ruff": "explicit"
    }
  }
}
'@
        $extensions = '["ms-python.python", "charliermarsh.ruff"]'
        if ($Profile -in @("web", "game")) {
            $extensions = '["ms-python.python", "charliermarsh.ruff", "dbaeumer.vscode-eslint"]'
        }
        Write-TextFile -Path (Join-Path ".vscode" "extensions.json") -Content $extensions
    }
}
```

Call sites: web flow immediately after the `.pre-commit-config.yaml` write (~925); base flow immediately after its `.pre-commit-config.yaml` write (~1349).

3g. Pre-commit configs — both sites: prepend the identical hygiene repo block from Task 1 step 3l (same 15 lines + blank line) before `  - repo: local` in both `@'...'@` here-strings (~915 web/game, ~1318 base). Existing local hooks unchanged.

- [ ] **Step 4: Run the PS contract, verify pass**

Run: `pwsh -NoProfile -File tests/powershell_web_contract.ps1`
Expected: `PowerShell web contract passed`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add new-project.ps1 tests/powershell_web_contract.ps1
git commit -m "feat(ps1): harden generated python checks, hooks, and repo files"
```

**Task Boundary Verification**

- Fast: `pwsh -NoProfile -File tests/powershell_web_contract.ps1` → exit 0.
- Cross-check bash unchanged: `& "$env:USERPROFILE\scoop\apps\git\current\bin\bash.exe" tests/cross_platform_contract.sh` → exit 0.
- Expected known failures: none.
- Next task may assume: PS Python-side artifacts final; `Write-RepoQualityFiles` exists; marker technique proven.

---

### Task 4: PowerShell CI + Dependabot + full PS e2e

**Task Position**

- **Previously:** Task 3 delivered the PS Python-side hardening with green fast contract.
- **Current:** PS CI bodies (base/desktop, web, game) and Dependabot reach byte-parity with the bash Task 2 outputs; the slow real-tooling e2e proves everything executes (real `uv lock --check`, `uv audit`, ruff with new rules, pytest, vitest, tsc, eslint, build).
- **Next:** Task 5 documents and runs the whole verification matrix.
- **Do not do yet:** README/CHANGELOG (Task 5).

**Files:**
- Modify: `new-project.ps1` — game CI (~931-1006), web CI (~1009-1077), base/desktop CI (~1452-1488)
- Modify: `tests/powershell_web_contract.ps1` (CI + Dependabot assertions)
- Modify: `tests/scaffold_e2e.ps1` (assertions for new content)

**Interfaces:**
- Consumes: canonical CI YAML + Dependabot bodies from Task 2 (Global Constraints SHA table).
- Produces: cycle-complete generators on both platforms.

- [ ] **Step 1: Write the failing assertions**

1a. `tests/powershell_web_contract.ps1` — after the Task 3 assertions, add:

```powershell
    Assert-Contains -Path $CiYaml -Expected 'concurrency:'
    Assert-Contains -Path $CiYaml -Expected 'cancel-in-progress: true'
    Assert-Contains -Path $CiYaml -Expected 'harden-runner@b09bb98e06d4d774595224525879c09bc6e98c40 # v2.20.1'
    Assert-Contains -Path $CiYaml -Expected 'actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803 # v6.1.0'
    Assert-Contains -Path $CiYaml -Expected 'astral-sh/setup-uv@fac544c07dec837d0ccb6301d7b5580bf5edae39 # v8.2.0'
    Assert-Contains -Path $CiYaml -Expected 'actions/setup-node@249970729cb0ef3589644e2896645e5dc5ba9c38 # v6.5.0'
    Assert-Contains -Path $CiYaml -Expected 'actionlint/v1.7.12/scripts/download-actionlint.bash'
    Assert-Contains -Path $CiYaml -Expected '- name: Dependency audit'
    Assert-Contains -Path $CiYaml -Expected 'gitleaks/gitleaks-action@ff98106e4c7b2bc287b24eaf42907196329070c7 # v2.3.9'
    Assert-Contains -Path $CiYaml -Expected 'fetch-depth: 0'
    Assert-NotContains -Path $CiYaml -Unexpected '@v6'
    Assert-NotContains -Path $CiYaml -Unexpected 'setup-uv@v8'

    $Dependabot = Join-Path $ProjectDir ".github/dependabot.yml"
    Assert-Contains -Path $Dependabot -Expected 'package-ecosystem: uv'
    Assert-Contains -Path $Dependabot -Expected 'directory: /backend'
    Assert-Contains -Path $Dependabot -Expected 'package-ecosystem: npm'
    Assert-Contains -Path $Dependabot -Expected 'directory: /frontend'
    Assert-Contains -Path $Dependabot -Expected 'package-ecosystem: github-actions'
```

Note: `Assert-NotContains '@v6'` — verify no false positive against `# v6.1.0` comments (the `@` makes it specific to `uses:` tags; `node-version: 24` and `ubuntu-latest` are unaffected).

1b. `tests/scaffold_e2e.ps1` — after the existing CI assertions (~line 133), add:

```powershell
    Assert-Contains -Path $CiYaml -Expected 'concurrency:'
    Assert-Contains -Path $CiYaml -Expected '- name: Dependency audit'
    Assert-Contains -Path $CiYaml -Expected 'gitleaks/gitleaks-action@ff98106e4c7b2bc287b24eaf42907196329070c7 # v2.3.9'

    $BackendPyproject = Join-Path $ProjectDir "backend/pyproject.toml"
    Assert-Contains -Path $BackendPyproject -Expected '"S", "PIE", "TC", "T10", "ERA"'
    Assert-Contains -Path $BackendPyproject -Expected 'docstring-code-format = true'

    Assert-InOrder -Path $CheckScript -Expected @(
        'Invoke-Checked uv lock --check'
        'Invoke-Checked uv audit'
        'Invoke-Checked uv run ruff format --check .'
    )

    Assert-Contains -Path (Join-Path $ProjectDir ".github/dependabot.yml") -Expected 'package-ecosystem: npm'
```

- [ ] **Step 2: Run the fast contract, verify failure**

Run: `pwsh -NoProfile -File tests/powershell_web_contract.ps1`
Expected: FAIL on `Expected ...\ci.yml to contain: concurrency:`.

- [ ] **Step 3: Implement the three PS CI bodies + Dependabot**

Replace each `Write-TextFile -Path $ciPath -Content @'...'@` body with the exact YAML from Task 2 steps 3a/3b (base: same as bash `write_base_ci` body; game: bash game body; web: bash web body — identical text; these are literal `@'...'@` here-strings so `${{ }}` is safe). Then write `.github/dependabot.yml` right after each CI write:

- base/desktop CI block (~1452-1488): base dependabot (uv at `/`, github-actions at `/`) — same body as Task 2 step 3a.
- game (~931) and web (~1009) CI blocks: web/game dependabot (uv at `/backend`, npm at `/frontend`, github-actions at `/`) — same body as Task 2 step 3c.

All three CI writes are already inside `if (-not $NoGitHubActions)` guards; the dependabot writes go inside the same guards.

- [ ] **Step 4: Run the fast contract, verify pass**

Run: `pwsh -NoProfile -File tests/powershell_web_contract.ps1`
Expected: `PowerShell web contract passed`, exit 0.

- [ ] **Step 5: Run the slow PS e2e (real tooling)**

Run: `pwsh -NoProfile -File tests/scaffold_e2e.ps1`
Expected: `PowerShell web scaffold e2e passed`, exit 0 — includes real `uv lock --check`, `uv audit`, `ruff check` with the new rule set on the generated FastAPI backend, plus vitest/tsc/eslint/vite build on the frontend, across check → fix → check.

- [ ] **Step 6: Commit**

```bash
git add new-project.ps1 tests/powershell_web_contract.ps1 tests/scaffold_e2e.ps1
git commit -m "feat(ps1): harden generated CI and add dependabot"
```

**Task Boundary Verification**

- Fast: `pwsh -NoProfile -File tests/powershell_web_contract.ps1` → exit 0.
- Slow: `pwsh -NoProfile -File tests/scaffold_e2e.ps1` → exit 0.
- Bash still green: `& "$env:USERPROFILE\scoop\apps\git\current\bin\bash.exe" tests/cross_platform_contract.sh` → exit 0.
- Expected known failures: none.

---

### Task 5: Docs, changelog, and full verification matrix

**Task Position**

- **Previously:** Tasks 1-4 completed both generators; all four suites green (bash e2e either green or documented environment-limited).
- **Current:** RepoSeed's own README/CHANGELOG describe the new generated content and flags; the full matrix is rerun against the final state.
- **Next:** Final whole-branch review (Gate 3).
- **Do not do yet:** Anything beyond docs + verification.

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`

**Interfaces:** None.

- [ ] **Step 1: Update README.md**

1a. In "What it creates" (after the pytest bullet), add bullets:

```markdown
- **`uv lock --check` + `uv audit`** dependency lock verification and vulnerability scanning in every check run
- **Secret scanning** via Gitleaks in CI, plus pre-commit hygiene and private-key detection hooks
- **SHA-pinned, hardened CI** (Harden Runner monitor mode, actionlint, concurrency cancellation) with Dependabot update PRs
- **Editor defaults** at `.vscode/settings.json` / `.vscode/extensions.json` (Ruff format-on-save)
- **Repo hygiene files**: `SECURITY.md`, PR template, `.git-blame-ignore-revs`
```

1b. In the Bash options list (after `--no-github-actions`), add:

```markdown
* `--no-security`: skip `uv lock --check` and `uv audit` in the generated check scripts (CI hardening is unaffected).
* `--no-vscode`: skip the `.vscode` settings and extensions files.
```

In the PowerShell options list, add the `-NoSecurity` / `-NoVscode` equivalents.

1c. Add a short "Notes" paragraph under Requirements: gitleaks-action is free for personal accounts (organizations request a free license key from gitleaks); `uv audit` requires a current uv release.

- [ ] **Step 2: Update CHANGELOG.md**

Under `## [Unreleased]` add a `### Added` section:

```markdown
### Added

- Generated projects now include `uv lock --check` and `uv audit` in their
  check scripts, security and dead-code ruff rules (`S`, `PIE`, `TC`, `T10`,
  `ERA`) with a tests `S101` ignore, pre-commit hygiene hooks
  (`pre-commit-hooks` v6.0.0), SHA-pinned hardened CI (Harden Runner monitor
  mode, actionlint, concurrency cancellation, Gitleaks job, dependency audit
  step), weekly Dependabot updates (uv, npm for web/game, GitHub Actions),
  `SECURITY.md`, a PR template, `.git-blame-ignore-revs`, and shared
  `.vscode` settings. New opt-out flags: `--no-security` / `-NoSecurity`
  (audit lines only) and `--no-vscode` / `-NoVscode`.
- Bash contract test now skips its pwsh subsection under git-bash on Windows
  (the PowerShell-native `powershell_web_contract.ps1` covers that path).
```

- [ ] **Step 3: Run the full verification matrix**

Run all four, in this order, and record results:

```powershell
& "$env:USERPROFILE\scoop\apps\git\current\bin\bash.exe" tests/cross_platform_contract.sh   # exit 0
pwsh -NoProfile -File tests/powershell_web_contract.ps1                                      # exit 0
pwsh -NoProfile -File tests/scaffold_e2e.ps1                                                 # exit 0
& "$env:USERPROFILE\scoop\apps\git\current\bin\bash.exe" tests/scaffold_e2e.sh               # exit 0 or documented env limitation
```

- [ ] **Step 4: Commit**

```bash
git add README.md CHANGELOG.md
git commit -m "docs: describe cycle 1 python and CI hardening"
```

**Task Boundary Verification**

- All four suites per Step 3 matrix; bash e2e documented if environment-blocked.
- Expected known failures: none.
- Resulting state: cycle 1 implementation complete; final whole-branch review pending.

---

## Acceptance Coverage Map (spec scenario → proof)

| Spec scenario | Proof |
|---|---|
| Ruff rules + S101 ignore + docstring-code-format (base) | T1 contract assertions; e2e real ruff run |
| Ruff rules (web/game, both platforms) | T1/T3 contract + e2e ruff runs |
| New rules pass on generated code | T1 Step 5 / T4 Step 5 real check runs |
| Check scripts audit + ordering | T1/T3 `Assert_InOrder`-style multiline asserts; e2e execution |
| `--no-security` omits only audit lines | T1 Step 1c / T3 Step 1b negative scaffolds |
| fix scripts unchanged | T3 Step 1a `Assert-NotContains` on fix.ps1; bash fix body untouched (review) |
| Pre-commit hygiene block | T1/T3 contract assertions |
| CI SHA pins | T2/T4 contract assertions + `@v6`/`@v8` negatives |
| CI concurrency/harden-runner/actionlint/audit/gitleaks | T2/T4 contract assertions |
| Dependabot incl. npm + `/backend` | T2/T4 contract assertions |
| Dependabot skipped with `--no-github-actions` | Existing flag plumbing (writes inside same guard); bash nosec scaffold in T1 keeps `--no-github-actions` and passes without dependabot assertions |
| New repo files exist | T1/T3 file-existence loops |
| `--no-vscode` skips editor files | T1 Step 1c / T3 Step 1b |
| Full pipeline green | T5 matrix |

## Explicit Exclusions

- No frontend tooling changes (package.json, vite.config.ts, eslint config, tsconfig untouched).
- No `fix.*` script changes.
- No gitleaks/actionlint pre-commit hooks.
- No CODEOWNERS, issue templates, docs skeleton, `--strict` mode.
- No changes to install scripts or template files under `templates/`.
