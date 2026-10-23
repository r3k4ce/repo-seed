# Cross-Platform Project Scripts

## Problem, Goal, and User-Visible Outcome

Each scaffolder writes helper scripts for its own platform only. Projects made
by `new-project.sh` get `scripts/check.sh` and `scripts/fix.sh`; projects made
by `new-project.ps1` get `scripts/check.ps1` and `scripts/fix.ps1`. A project
created on one OS therefore has no working helper scripts on the other.

The `web` and `game` profiles also wire the helper script into their single
pre-push hook, so the hook itself is platform-bound:

- Bash-generated: `entry: bash scripts/check.sh`
- PowerShell-generated: `entry: powershell -ExecutionPolicy Bypass -File scripts/check.ps1`

The PowerShell entry fails on Linux, where there is no `powershell` command.

The goal is that a project created by either scaffolder can run its checks,
fixes, and hooks on both Linux and Windows. Every generated project gets
`scripts/check.py` and `scripts/fix.py`, run with:

```text
uv run scripts/check.py
uv run scripts/fix.py
```

Both scaffolders write byte-identical scripts for a given profile.

## Scope and Non-goals

### In scope

- Six self-contained templates: `templates/scripts/{base,web,game}/check.py`
  and `fix.py`. The `desktop` profile uses the `base` pair.
- Both scaffolders copy the profile's pair instead of writing `.sh`/`.ps1`
  scripts inline.
- The `web`/`game` pre-push hook becomes `entry: uv run scripts/check.py`.
- The `base`/`desktop` pyproject adds `"scripts"` to pyright's `include`.
- Generated README command blocks and the final "Done. Next:" message show the
  `uv run scripts/...` commands.
- Remove the `__CHECK_COMMAND__`/`__FIX_COMMAND__` placeholder expansion and
  the `CHECK_COMMAND`/`FIX_COMMAND` variables, which no template uses.
- A new template contract test, a CI step that lints and type-checks the
  templates, and updates to the existing contract and e2e tests.
- RepoSeed README and CHANGELOG updates.

### Non-goals

- No `.sh` or `.ps1` wrapper scripts in generated projects.
- No change to which steps each profile runs, their order, or the stop-at-first-
  failure behavior.
- No change to generated CI workflows; they call the tools directly.
- No change to the `base`/`desktop` per-tool pre-commit/pre-push hooks; they
  already call `uv run <tool>` directly.
- No migration of existing projects; RepoSeed only creates new ones.
- No removal of the other unused placeholders (`__PYTHON_VERSION__`,
  `__GENERATOR_NAME__`, `__PRIMARY_SHELL__`, `__COMMAND_FENCE__`,
  `__SETUP_COMMAND__`); that is separate cleanup.
- No Bash `desktop` profile; that port follows this change and reuses the
  `base` pair.

## Current Behavior and Repository Constraints

Steps per profile, identical between the two scaffolders today:

| Profile | `check` | `fix` |
|---|---|---|
| `base`/`desktop` (root) | `ruff format --check .`, `ruff check .`, `pyright`, `pytest` | `ruff check . --fix`, `ruff format .`, `ruff check .`, `pyright`, `pytest` |
| `web` | backend: as `base`; frontend: `npm run test`, `typecheck`, `lint`, `build` | backend: as `base` fix; frontend: same as check |
| `game` | backend: as `base`; frontend: `npm run test --if-present`, `test:e2e --if-present`, `lint`, `build` | backend: as `base` fix; frontend: same as check |

All Python tools run as `uv run <tool>`.

Constraints:

- `web`/`game` projects have no root `pyproject.toml`; the uv project lives
  in `backend/`.
- When uv runs a script that carries inline script metadata, it sets
  `VIRTUAL_ENV` to a cached script environment. A nested `uv run` in the
  project then warns that `VIRTUAL_ENV` does not match the project's `.venv`.
  This was observed with uv 0.13.3.
- On Windows, npm is `npm.cmd`; the PowerShell scripts already resolve it.
- Template writers (`write_template_file`, `Write-TemplateFile`) replace only
  named `__TOKEN__` placeholders, so `__file__`, `__name__`, and `__main__` in
  Python templates pass through unchanged.
- Both installers copy `templates/` recursively, so nested template folders
  need no installer change.
- In `base`/`desktop` projects, ruff runs from the root and lints `scripts/`;
  pyright includes only `src` and `tests`. In `web`/`game` projects, ruff and
  pyright run inside `backend/` and never see root `scripts/`.

## Chosen Design

One self-contained template per profile and task. Each file holds:

1. A PEP 723 inline metadata block declaring `requires-python = ">=3.10"` and
   `dependencies = []`, so `uv run scripts/<task>.py` works with or without a
   root project.
2. A module docstring giving the usage command.
3. `ROOT = Path(__file__).resolve().parent.parent`, so the script works from
   any working directory.
4. A shared `run()` helper between the markers `# --- shared helper ---` and
   `# --- end shared helper ---`. It is byte-identical in all six templates.
5. A `main()` listing the profile's steps as `run(...)` calls, in today's
   order, with `cwd=ROOT / "backend"` or `cwd=ROOT / "frontend"` where needed.

Rejected alternatives:

- A shared runner with steps injected by the scaffolders: it would duplicate
  the step lists in Bash and PowerShell, which is what this change removes.
- One runner that infers steps from the project layout: its behavior depends
  on which files exist, which is harder to read and can surprise users.

## Components, Interfaces, and Data Flow

### `run(*command: str, cwd: Path = ROOT) -> None`

1. Resolve `command[0]` with `shutil.which`. If not found, exit with
   `error: '<name>' was not found on PATH` and a non-zero status.
2. Copy `os.environ` without `VIRTUAL_ENV`.
3. Print `> <command joined by spaces>` and flush.
4. Run the resolved executable with the remaining arguments, in `cwd`, with
   that environment.
5. If the return code is non-zero, exit with that code.

Standard library only; type-clean under pyright strict; passes the generated
projects' ruff rule set (`E`, `F`, `I`, `B`, `UP`, `SIM`, `C4`, `PT`, `RUF`)
with line length 100.

### Scaffolders

- `new-project.sh`: `write_base_scripts` and `write_web_scripts` are replaced
  by one function that writes `templates/scripts/$PROFILE/check.py` and
  `fix.py` to `scripts/`. No `chmod`.
- `new-project.ps1`: the inline `check.ps1`/`fix.ps1` blocks for base, web,
  and game are replaced with `Write-TemplateFile` calls. `desktop` maps to the
  `base` templates.
- The "Template references used by supported profiles" comment at the top of
  `new-project.sh` lists the six new template paths.

### Generated files

| File | Change |
|---|---|
| `scripts/check.py`, `scripts/fix.py` | New, copied from the profile's templates |
| `scripts/check.sh`, `fix.sh`, `check.ps1`, `fix.ps1` | No longer generated |
| `.pre-commit-config.yaml` (`web`/`game`) | `entry: uv run scripts/check.py`, still `stages: [pre-push]` |
| `pyproject.toml` (`base`/`desktop`) | pyright `include = ["src", "tests", "scripts"]` |
| `README.md` | Commands show `uv run scripts/check.py` and `uv run scripts/fix.py` |

## Functional Behavior

- Steps run in the order listed in Current Behavior.
- The first failing step stops the script; the script exits with that step's
  exit code. Later steps do not run.
- Each step's command is printed before it runs.
- Running from a subfolder behaves the same as running from the project root.
- The pre-push hook runs the same checks as `uv run scripts/check.py`.

## Error Handling and Boundary Conditions

- Missing tool (`uv` or `npm` not on `PATH`): clear error, non-zero exit, no
  traceback.
- Tool failure: its own output is shown unchanged; the script adds nothing
  beyond the exit code.
- A Python interpreter of 3.10 or newer is needed to start the script; uv
  provides one if none is installed, as it already does for the project.
- `VIRTUAL_ENV` set by the caller (for example an activated shell) is also
  removed for child tools, so `uv run` always uses the project's `.venv`.

## Compatibility, Migration, and Platform Constraints

- Bash and PowerShell remain required to run the scaffolders. Generated
  projects need only `uv` (plus Node.js/npm for `web`/`game`).
- Existing projects keep their `.sh`/`.ps1` scripts; nothing rewrites them.
- Generated output changes for every profile, so the CHANGELOG entry under
  `[Unreleased]` states it plainly.

## Acceptance Criteria

### Scenario: Same scripts from either scaffolder

Given the same profile, when a project is generated with `new-project.sh` and
with `new-project.ps1`, then both contain `scripts/check.py` and
`scripts/fix.py`, byte-identical to `templates/scripts/<profile>/`, and
neither contains `.sh` or `.ps1` helper scripts.

### Scenario: Base project checks pass on Linux

Given a fresh `base` project on Linux, when `uv run scripts/check.py`,
`uv run scripts/fix.py`, and `uv run scripts/check.py` run in order, then
all succeed, and `uv run scripts/check.py` also succeeds from a subfolder.

### Scenario: Web and game project checks pass on Linux

Given fresh `web` and `game` projects on Linux, when the same three commands
run, then all succeed, running backend steps in `backend/` and frontend steps
in `frontend/`.

### Scenario: Web project checks pass on Windows

Given a fresh `web` project from `new-project.ps1` on Windows, when the same
three commands run, then all succeed, with npm resolved as `npm.cmd`.

### Scenario: Cross-OS pre-push hook

Given a `web` or `game` project from either scaffolder, then its pre-push hook
entry is `uv run scripts/check.py`.

### Scenario: Stop at first failure

Given fake `uv`/`npm` commands where one step exits with code 3, when the
script runs, then earlier steps ran, later steps did not, and the script exits
with code 3.

### Scenario: Missing tool

Given `npm` is not on `PATH`, when a `web` script reaches its first npm step,
then it prints `error: 'npm' was not found on PATH` and exits non-zero.

### Scenario: Templates stay consistent

Given the six templates, then each profile folder has `check.py` and
`fix.py`, the shared helper block is identical in all six, and the templates
pass ruff format, ruff lint, and pyright strict.

## Testing Strategy

- **New `tests/script_templates_contract.sh`** (Linux CI, no real tools):
  completeness; identical helper block; per-profile step lists (the `web`
  steps without `--if-present` or `test:e2e`, the `game` steps with them, the
  `fix` ruff steps); runner behavior with fake `uv`/`npm` on `PATH` that log
  arguments, working directory, and `VIRTUAL_ENV`, covering order,
  stop-at-failure with exit code, `VIRTUAL_ENV` removal, missing tool, and
  `backend/`/`frontend/` working directories.
- **CI step** in the Linux job: ruff format check, ruff lint, and pyright
  strict over `templates/scripts/`, using the `PY_RUFF` and `PY_PYRIGHT`
  versions from `versions.env`.
- **`tests/scaffold_e2e.sh`**: run the three commands for `base`, `web`, and
  `game` (game in CI); run `check.py` once from a subfolder; assert scripts
  equal the templates, no `.sh` scripts exist, the web hook entry, and the
  `base` pyright include.
- **`tests/scaffold_e2e.ps1`**: the same for the Windows `web` e2e.
- **`tests/powershell_web_contract.ps1`** and
  **`tests/cross_platform_contract.sh`**: expect `check.py`/`fix.py` and the
  new hook entry instead of `.ps1` scripts; assert PowerShell and Bash output
  match byte for byte.
- **Verification:** shellcheck, contract tests, and the Bash e2e run locally on
  Linux. Windows behavior is verified only by the repository's `windows` CI
  job on the pull request.

## Mechanical Assumptions and Deferred Work

- Both file writers normalize to LF and end the file with exactly one newline
  (`write_text_file` strips trailing newlines and adds one; `Write-TextFile`
  adds one if missing). Templates end with exactly one newline, which
  `ruff format` enforces, so output from both scaffolders is byte-identical.
- Deferred: the Bash `desktop` profile port, desktop e2e coverage, the
  possible `libegl1` step in generated desktop CI, and removal of the other
  unused placeholders.
