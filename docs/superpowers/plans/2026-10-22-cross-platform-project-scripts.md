# Cross-Platform Project Scripts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every generated project gets `scripts/check.py` and `scripts/fix.py`, identical from both scaffolders, run with `uv run scripts/<task>.py` on Linux and Windows.

**Architecture:** Six self-contained Python templates under `templates/scripts/<profile>/`, each with a byte-identical `run()` helper and a profile-specific `main()`. Both scaffolders copy the profile's pair with their existing template writers and stop writing `.sh`/`.ps1` scripts. A new contract test pins the templates' steps and runner behavior using fake `uv`/`npm`.

**Tech Stack:** Python 3.10+ standard library, PEP 723 inline script metadata, Bash, PowerShell 7, uv, ruff, pyright, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-22-cross-platform-project-scripts-design.md`

## Global Constraints

- Generated commands are exactly `uv run scripts/check.py` and `uv run scripts/fix.py`.
- Templates use the standard library only and start with a PEP 723 block: `requires-python = ">=3.10"`, `dependencies = []`.
- Shared helper markers are exactly `# --- shared helper ---` and `# --- end shared helper ---`; the block between them is byte-identical in all six templates.
- Missing-tool message is exactly `error: '<name>' was not found on PATH`.
- Each step prints `> <command joined by single spaces>` before it runs.
- First failing step stops the script; the script exits with that step's code.
- `VIRTUAL_ENV` is removed from the environment of every child command.
- Templates pass ruff with `E,F,I,B,UP,SIM,C4,PT,RUF`, line length 100, and pyright strict at Python 3.10.
- `desktop` uses the `base` templates.
- The `web`/`game` pre-push hook is `entry: uv run scripts/check.py` with `stages: [pre-push]`.
- Tool versions for linting templates come from `versions.env` (`PY_RUFF`, `PY_PYRIGHT`); never hard-code them.
- Local environment: `pwsh` and `shellcheck` are not installed on the developer machine. PowerShell changes are verified only by the `windows` CI job; say so instead of claiming they pass.

## Review Focus

- Running from a subfolder (`cd src && uv run ../scripts/check.py`): must behave like running from the root. Pinned by the subfolder run in Task 2's e2e and the `cwd` assertions in Task 1.
- A tool that exits non-zero with output on stderr: output must reach the user unchanged and the exit code must propagate. Pinned by Task 1's stop-at-failure case (exit code 3).
- Caller's shell already has `VIRTUAL_ENV` set (activated venv): child tools must not see it. Pinned by Task 1's case that runs the template with `VIRTUAL_ENV=/somewhere`.
- Windows `npm.cmd`: must resolve through `shutil.which`. Only the Windows `web` e2e (Task 3) exercises it; flag in the PR that it was verified by CI only.
- Generated template content drifting between Bash- and PowerShell-made projects: pinned by byte-equality against `templates/scripts/` in Tasks 2 and 3.

---

### Task 1: Script templates, template contract test, template lint

**Files:**
- Create: `templates/scripts/base/check.py`, `templates/scripts/base/fix.py`
- Create: `templates/scripts/web/check.py`, `templates/scripts/web/fix.py`
- Create: `templates/scripts/game/check.py`, `templates/scripts/game/fix.py`
- Create: `tests/script_templates_contract.sh`
- Create: `tests/lint_script_templates.sh`, `tests/pyright-script-templates.json`
- Modify: `.github/workflows/ci.yml` (Linux job)

**Interfaces:**
- Produces: `templates/scripts/{base,web,game}/{check,fix}.py`, consumed by Tasks 2 and 3 as template names `scripts/<profile>/check.py` and `scripts/<profile>/fix.py`.
- Produces: in each template, `ROOT: Path`, `run(*command: str, cwd: Path = ROOT) -> None`, `main() -> None`.

Steps per template (`uv run` prefix on every Python tool; `B` = `cwd=ROOT / "backend"`, `F` = `cwd=ROOT / "frontend"`, no marker = `ROOT`):

| Template | Steps, in order |
|---|---|
| `base/check.py` | `ruff format --check .`, `ruff check .`, `pyright`, `pytest` |
| `base/fix.py` | `ruff check . --fix`, `ruff format .`, `ruff check .`, `pyright`, `pytest` |
| `web/check.py` | B: base check steps; F: `npm run test`, `npm run typecheck`, `npm run lint`, `npm run build` |
| `web/fix.py` | B: base fix steps; F: same four npm steps |
| `game/check.py` | B: base check steps; F: `npm run test --if-present`, `npm run test:e2e --if-present`, `npm run lint`, `npm run build` |
| `game/fix.py` | B: base fix steps; F: same four npm steps |

- [ ] **Step 1: Write `tests/script_templates_contract.sh`**

Structure (Bash, `set -euo pipefail`, `ROOT` resolved like the other tests, ends with `printf 'script template contract tests passed\n'`):

1. `PYTHON="$(command -v python3)"` and `BASH_BIN="$(command -v bash)"` before any PATH changes.
2. `make_fake_bin <dir> <log> [tools...]`: writes one executable per tool (default `uv npm`) with shebang `#!$BASH_BIN`. Each appends one line to `<log>`: `<tool> <args> | cwd=<basename of $PWD> | venv=${VIRTUAL_ENV-unset}`. If `FAKE_FAIL_ON` is non-empty and `"<tool> <args>"` equals it, exit 3; else exit 0.
3. `make_project <dir> <profile> <task>`: creates `<dir>/scripts/`, `<dir>/backend/`, `<dir>/frontend/`, copies `templates/scripts/<profile>/<task>.py` to `<dir>/scripts/<task>.py`.
4. `run_template <fake_bin> <dir> <task>`: runs `env -i PATH="<fake_bin>" VIRTUAL_ENV=/caller/venv FAKE_FAIL_ON="${FAKE_FAIL_ON-}" "$PYTHON" "<dir>/scripts/<task>.py"` from `<dir>/backend` (a subfolder), captures stdout and stderr to separate files, and returns its exit code without tripping `set -e`.

Cases:

- `test_templates_complete`: for each of `base web game`, both `check.py` and `fix.py` exist.
- `test_shared_helper_identical`: extract lines between the two markers (inclusive) from all six files with `sed -n '/^# --- shared helper ---$/,/^# --- end shared helper ---$/p'`; all six extracts are equal and non-empty.
- `test_steps_<profile>_<task>` (six cases): run with no failure; the log equals exactly the expected lines for the table above, e.g. for `web/check.py` the first line is `uv run ruff format --check . | cwd=backend | venv=unset` and the fifth is `npm run test | cwd=frontend | venv=unset`; `base` lines have `cwd=<project dir basename>`. Compare the whole log with a heredoc, so order and absence of `--if-present`/`test:e2e` in `web` are both pinned. The `venv=unset` field proves `VIRTUAL_ENV=/caller/venv` was stripped.
- `test_stops_at_first_failure`: `base/check.py` with `FAKE_FAIL_ON="uv run ruff check ."`; exit code is 3; log has exactly 2 lines; `pyright` is not in the log.
- `test_missing_tool`: `web/check.py` with a fake bin containing only `uv`; exit code is non-zero; stderr contains `error: 'npm' was not found on PATH`; stderr does not contain `Traceback`; log has exactly the 4 backend lines.
- `test_prints_commands`: stdout of a successful `base/check.py` run contains `> uv run ruff format --check .` and `> uv run pytest`.

- [ ] **Step 2: Run it and confirm it fails**

Run: `bash tests/script_templates_contract.sh`
Expected: FAIL at `test_templates_complete` (templates missing).

- [ ] **Step 3: Write the six templates**

Each file: PEP 723 block, docstring `"""Run the project checks. Usage: uv run scripts/check.py"""` (fix: `"""Apply automatic fixes, then run the checks. Usage: uv run scripts/fix.py"""`), imports `os`, `shutil`, `subprocess`, `sys`, `from pathlib import Path`, `ROOT = Path(__file__).resolve().parent.parent`, the shared helper, `main()` with the table's steps as `run(...)` calls, and the `if __name__ == "__main__": main()` guard. Backend/frontend templates may define `BACKEND = ROOT / "backend"` and `FRONTEND = ROOT / "frontend"` below the helper.

The shared helper is exact copy, identical in all six:

```python
# --- shared helper ---
def run(*command: str, cwd: Path = ROOT) -> None:
    executable = shutil.which(command[0])
    if executable is None:
        sys.exit(f"error: '{command[0]}' was not found on PATH")
    env = {key: value for key, value in os.environ.items() if key != "VIRTUAL_ENV"}
    print(f"> {' '.join(command)}", flush=True)
    result = subprocess.run([executable, *command[1:]], cwd=cwd, env=env, check=False)
    if result.returncode != 0:
        sys.exit(result.returncode)


# --- end shared helper ---
```

Adjust blank lines only as `ruff format` requires, then keep the result identical everywhere.

- [ ] **Step 4: Run the contract test and confirm it passes**

Run: `bash tests/script_templates_contract.sh`
Expected: `script template contract tests passed`

- [ ] **Step 5: Write the template lint**

`tests/pyright-script-templates.json`: `{"include": ["../templates/scripts"], "typeCheckingMode": "strict", "pythonVersion": "3.10"}`.

`tests/lint_script_templates.sh`: reads `PY_RUFF` and `PY_PYRIGHT` from `versions.env` with the same `KEY=value` parsing `scaffold_e2e.sh`'s `pinned` uses, then runs from `$ROOT`:

```bash
uvx "ruff@$ruff_version" format --check --line-length 100 --target-version py310 templates/scripts
uvx "ruff@$ruff_version" check --line-length 100 --target-version py310 \
  --select E,F,I,B,UP,SIM,C4,PT,RUF templates/scripts
uvx --from "pyright==$pyright_version" pyright -p tests/pyright-script-templates.json
```

Ends with `printf 'script template lint passed\n'`.

- [ ] **Step 6: Run the lint and fix templates until it passes**

Run: `bash tests/lint_script_templates.sh`
Expected: ruff reports no changes and no errors; pyright `0 errors`; final line `script template lint passed`. Re-run Step 4 after any template edit.

- [ ] **Step 7: Add both tests to the Linux CI job**

In `.github/workflows/ci.yml`, after `Contract tests`, add steps `Script template contract` (`bash tests/script_templates_contract.sh`) and `Script template lint` (`bash tests/lint_script_templates.sh`). The existing `shellcheck ... tests/*.sh` glob already covers the two new `.sh` files.

- [ ] **Step 8: Commit**

```bash
git add templates/scripts tests/script_templates_contract.sh tests/lint_script_templates.sh tests/pyright-script-templates.json .github/workflows/ci.yml
git commit -m "feat: add cross-platform check/fix script templates"
```

---

### Task 2: Bash scaffolder writes the Python scripts

**Files:**
- Modify: `new-project.sh` — header comment (lines 4-12), `CHECK_COMMAND`/`FIX_COMMAND` (22-23), `expand_text` (120-121), base pyright include (308), `write_base_scripts` (434-454), `write_web_scripts` (544-619), web README commands (1239-1240), web pre-commit entry (1249), "Done" lines (1257, 1342), base README commands (1336-1337)
- Modify: `tests/scaffold_e2e.sh`
- Modify: `tests/cross_platform_contract.sh` (Bash-scaffolder assertions only)

**Interfaces:**
- Consumes: `templates/scripts/<profile>/{check,fix}.py` from Task 1; existing `write_template_file <template_name> <path>`.
- Produces: `write_project_scripts` (no arguments; reads `$PROFILE`), replacing `write_base_scripts` and `write_web_scripts` at their call sites.

- [ ] **Step 1: Update `tests/scaffold_e2e.sh` to the new contract**

- `run_project_checks <project_dir>`: from the project root run `uv run scripts/check.py`, `uv run scripts/fix.py`, `uv run scripts/check.py`; then from `<project_dir>/tests` (base) or `<project_dir>/backend` (web/game) run `uv run ../scripts/check.py`.
- New `assert_project_scripts <profile> <project_dir>`: `cmp` each of `scripts/check.py` and `scripts/fix.py` against `$ROOT/templates/scripts/<profile>/`; fail if any of `scripts/check.sh`, `scripts/fix.sh`, `scripts/check.ps1`, `scripts/fix.ps1` exists. Call it from `run_scaffold_case`.
- `assert_web_frontend_config`: delete the `check_script_path`/`fix_script_path` content assertions (now pinned by Task 1); change the hook assertion to `entry: uv run scripts/check.py`.
- In `run_scaffold_case`, for `base`: `assert_file_contains "$project_dir/pyproject.toml" 'include = ["src", "tests", "scripts"]'`.

In `tests/cross_platform_contract.sh`, wherever the Bash-generated base or web project is checked, replace `.sh` script expectations the same way (template equality, no `.sh`/`.ps1` scripts) and expect `entry: uv run scripts/check.py` for web and game.

- [ ] **Step 2: Run the contract test and confirm it fails**

Run: `bash tests/cross_platform_contract.sh`
Expected: FAIL on the first `scripts/check.py` or hook-entry assertion.

- [ ] **Step 3: Change `new-project.sh`**

- `write_project_scripts`: `local profile="$PROFILE"`; map `desktop` to `base` (harmless today, needed by the later port); `write_template_file "scripts/$profile/check.py" "scripts/check.py"` and the same for `fix.py`. Delete `write_base_scripts` and `write_web_scripts` and call the new function at both call sites. No `chmod`.
- Base pyright include: `include = [\"src\", \"tests\", \"scripts\"]` (line 308 only; leave the web backend at 638 unchanged).
- Web/game hook: `entry: uv run scripts/check.py`.
- README command blocks: `uv run scripts/check.py` and `uv run scripts/fix.py`. "Done" lines: `Done. Next: uv run scripts/check.py`.
- Delete `CHECK_COMMAND`, `FIX_COMMAND`, and their two `expand_text` lines.
- Header comment: add the six `scripts/<profile>/<task>.py` template paths.

- [ ] **Step 4: Run contract tests and confirm they pass**

Run: `bash tests/cross_platform_contract.sh`
Expected: `cross-platform contract tests passed` (the PowerShell part prints `Skipping PowerShell contract: pwsh not found` locally).

- [ ] **Step 5: Run the real e2e**

Run: `REPOSEED_E2E_GAME=1 bash tests/scaffold_e2e.sh`
Expected: `base scaffold e2e passed`, `web scaffold e2e passed`, `game scaffold e2e passed`, `all scaffold e2e tests passed`. Output shows `> uv run ...` lines and no `VIRTUAL_ENV` mismatch warning from uv.

- [ ] **Step 6: Commit**

```bash
git add new-project.sh tests/scaffold_e2e.sh tests/cross_platform_contract.sh
git commit -m "feat: generate cross-platform scripts from the Bash scaffolder"
```

---

### Task 3: PowerShell scaffolder writes the Python scripts

**Files:**
- Modify: `new-project.ps1` — `Expand-Template` (136-137), web/game `check.ps1`/`fix.ps1` blocks (about 805-980), web README commands (1000-1001), web hook (1012), "Done" lines (1183, 1570), base pyright include (1267), base `check.ps1`/`fix.ps1` (1436-1480), base/desktop README commands (1484-1492)
- Modify: `tests/powershell_web_contract.ps1`, `tests/scaffold_e2e.ps1`
- Modify: `tests/cross_platform_contract.sh` (`run_powershell_contract_if_available`)

**Interfaces:**
- Consumes: `templates/scripts/<profile>/{check,fix}.py` from Task 1; existing `Write-TemplateFile -TemplateName <name> -Path <path>`.

- [ ] **Step 1: Update the PowerShell tests**

- `tests/powershell_web_contract.ps1`: replace `$CheckScript`/`$FixScript` with `scripts/check.py`/`scripts/fix.py`; replace the `$WebCheckOrder` assertions with byte equality against `templates/scripts/web/` (compare `[System.IO.File]::ReadAllBytes`); assert `scripts/check.ps1` and `scripts/fix.ps1` do not exist; hook assertion becomes `entry: uv run scripts/check.py`.
- `tests/scaffold_e2e.ps1`: same file assertions; replace the three `& scripts/*.ps1` calls with `uv run scripts/check.py`, `uv run scripts/fix.py`, `uv run scripts/check.py`, each followed by `if ($LASTEXITCODE -ne 0) { throw "<command> failed with exit code $LASTEXITCODE" }`.
- `tests/cross_platform_contract.sh` `run_powershell_contract_if_available`: expect `scripts/check.py`/`fix.py` equal to `templates/scripts/base/`, no `.ps1` scripts, and `include = ["src", "tests", "scripts"]` in `pyproject.toml`; update the comment above the hook assertions.

- [ ] **Step 2: Confirm they would fail**

`pwsh` is not available locally. Confirm by reading that every changed assertion targets a file or string the current `new-project.ps1` does not produce (`scripts/check.py`, `uv run scripts/check.py`). Record this in the commit message body.

- [ ] **Step 3: Change `new-project.ps1`**

- Replace all `check.ps1`/`fix.ps1` `Write-TextFile` blocks with `Write-TemplateFile -TemplateName "scripts/<profile>/check.py" -Path (Join-Path "scripts" "check.py")` and the same for `fix.py`, where `<profile>` is `$Profile` for web/game and `base` for base and desktop. Remove the `$Npm` resolution lines with them.
- Base pyright include (1267 only): `include = ["src", "tests", "scripts"]`.
- Web/game hook: `entry: uv run scripts/check.py`.
- README command blocks and both "Done" lines: `uv run scripts/check.py` / `uv run scripts/fix.py`.
- Remove the two `__CHECK_COMMAND__`/`__FIX_COMMAND__` `.Replace` calls, keeping the chain valid (the `__SETUP_COMMAND__` line becomes the last, without the trailing `.`).

- [ ] **Step 4: Verify locally what can be verified**

Run: `grep -nE 'check\.ps1|fix\.ps1|__CHECK_COMMAND__|__FIX_COMMAND__|powershell -ExecutionPolicy' new-project.ps1 tests/*.ps1`
Expected: no output.
Run: `bash tests/cross_platform_contract.sh`
Expected: passes (PowerShell section skipped locally).

- [ ] **Step 5: Commit**

```bash
git add new-project.ps1 tests/powershell_web_contract.ps1 tests/scaffold_e2e.ps1 tests/cross_platform_contract.sh
git commit -m "feat: generate cross-platform scripts from the PowerShell scaffolder"
```

---

### Task 4: Docs and full verification

**Files:**
- Modify: `README.md` — lines 64-65 (Requirements), 91, 108, 134, 145-148, 156, 285-290, and any other `scripts/*.sh`/`scripts\*.ps1` mention
- Modify: `CHANGELOG.md` — `[Unreleased]`

- [ ] **Step 1: Update `README.md`**

- Requirements: Bash and PowerShell 7+ are needed to run the installer and scaffolder; generated projects need only `uv` (and Node.js/npm for `web`/`game`). Drop the "and generated `scripts/*.sh`/`scripts/*.ps1`" wording.
- Every generated-project command becomes `uv run scripts/check.py` / `uv run scripts/fix.py`; trees show `check.py`/`fix.py`; the `base` entrypoint sentence drops the per-platform split.

- [ ] **Step 2: Update `CHANGELOG.md`**

Under `[Unreleased]` → `### Changed`: "Generated projects now get `scripts/check.py` and `scripts/fix.py`, run with `uv run scripts/check.py`, instead of `check.sh`/`fix.sh` or `check.ps1`/`fix.ps1`. Both scaffolders write identical scripts, so a project works on Linux and Windows. The `web`/`game` pre-push hook runs `uv run scripts/check.py`. Existing projects are not changed." Leave historical entries (line 74) untouched.

- [ ] **Step 3: Full local verification**

Run, in order:
- `grep -rnE 'scripts/(check|fix)\.(sh|ps1)|scripts\\(check|fix)\.ps1' README.md new-project.sh new-project.ps1 tests/` — expected: no output.
- `bash tests/script_templates_contract.sh` — expected: `script template contract tests passed`.
- `bash tests/lint_script_templates.sh` — expected: `script template lint passed`.
- `bash tests/cross_platform_contract.sh` — expected: `cross-platform contract tests passed`.
- `REPOSEED_E2E_GAME=1 bash tests/scaffold_e2e.sh` — expected: `all scaffold e2e tests passed`.
- `shellcheck --severity=warning new-project.sh install.sh tests/*.sh` if `shellcheck` is installed; otherwise state that CI covers it.

- [ ] **Step 4: Commit**

```bash
git add README.md CHANGELOG.md
git commit -m "docs: document cross-platform project scripts"
```

- [ ] **Step 5: Hand off Windows verification**

Report that PowerShell scaffolder changes and the Windows `npm.cmd` path are verified only by the `windows` job in repository CI, which runs on a pull request from `dev`.
