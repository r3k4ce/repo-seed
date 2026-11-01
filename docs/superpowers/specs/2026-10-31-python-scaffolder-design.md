# Single Python Scaffolder

## Problem, Goal, and User-Visible Outcome

RepoSeed has two complete scaffolders that do the same job:
`new-project.sh` (Bash, 1,282 lines) and `new-project.ps1` (PowerShell,
1,356 lines), plus two installers (`install.sh`, `install.ps1`). Every feature
and fix is written twice, most generated files are inline text in both
scripts, and the PowerShell side can only be exercised in Windows CI. The
`desktop` profile exists only in PowerShell as a result.

The goal is a RepoSeed that works the same on Linux and Windows with as little
friction as possible and that is cheap to maintain: a change is made once, in
one place, and can be fully tested on Linux before Windows CI.

User-visible outcome:

- RepoSeed is a Python package. It is installed on either OS with
  `uv tool install --editable <checkout>` (or
  `uv tool install git+https://github.com/r3k4ce/repo-seed`), which puts a
  `reposeed` command on PATH. `uv` is the only requirement, as it already is
  for every generated project.
- `reposeed` takes the same options on both OSes and generates identical
  projects on both OSes.
- All four profiles (`base`, `desktop`, `web`, `game`) work on both OSes.

The only user is the repository owner, so commands and generated output may
change; every change is recorded in `CHANGELOG.md`.

## Scope and Non-goals

### In scope

- A `reposeed` package under `src/reposeed/` with a console entry point.
- Moving every generated file into `src/reposeed/templates/`, and
  `versions.env` into `src/reposeed/`.
- Porting `base`, `web`, and `game` from `new-project.sh` and `desktop` from
  `new-project.ps1`, proven equal to the old output before any change.
- Four deliberate output changes after equality is proven (listed below).
- A pytest suite (unit, snapshot, temporary comparison, real e2e), lint, and a
  two-OS CI workflow.
- Deleting `new-project.sh`, `new-project.ps1`, `install.sh`, `install.ps1`,
  and the Bash/PowerShell test scripts.
- README and CHANGELOG updates; reinstalling the owner's `reposeed`.

### Non-goals

- No new profiles and no change to what a profile's generated project
  contains beyond the four listed changes.
- No dependency upgrades; `versions.env` values stay as they are.
- No runtime dependencies for RepoSeed itself.
- No macOS support work.
- No publishing to PyPI.
- No rollback of a half-created project on failure.

## Current Behavior and Repository Constraints

Both scaffolders take the same options: name (default: current folder name),
Python version (default `3.12`), Pyright type mode (`off|basic|standard|strict`,
default `standard`), profile, and the switches no-git, no-install-hooks,
no-github-actions. Bash accepts `base|web|game`; PowerShell also accepts
`desktop`.

Shared behavior to preserve:

- Project name: lowercased, runs of non-`[a-z0-9]` replaced by `-`, leading and
  trailing `-` removed, empty result becomes `python-project`. Package name:
  project name with `-` replaced by `_`. Ruff target: `py<major><minor>` from
  the Python version, default `py312`.
- Refuses to run directly in the home folder:
  `Refusing to scaffold directly in HOME: <path>. Create and enter a project directory first.`
- Refuses a non-fresh folder: `base`/`desktop` stop if `pyproject.toml`
  exists; `web`/`game` stop if any of `backend`, `frontend`, `package.json`,
  `pyproject.toml` exists. Message: `<path> already exists. Run this only in a fresh project directory.`
- Preflight: `uv` must be on PATH and at least `UV_MIN`; for `web`/`game`,
  `node` and `npm` must be on PATH and Node at least `NODE_MIN`. Messages match
  the current ones (`uv was not found on PATH...`, `uv <v> is too old...`,
  `Node.js <v> is too old...`).
- Dev tools added with `uv add --dev`: `ruff`, `pytest`, `pytest-cov`,
  `pyright`, `pre-commit` at their `PY_*` pins; runtime: `python-dotenv`;
  `web`/`game` backends add `fastapi` and `uvicorn`; `desktop` adds `PySide6`.
- Several generated files are created by `uv init` and then appended to
  (`pyproject.toml`, `.gitignore`).
- Hooks: `base`/`desktop` install pre-commit and pre-push hooks via
  `uv run pre-commit install` (twice); `web`/`game` install a pre-push hook via
  `uv --project backend run pre-commit install --hook-type pre-push`. Skipped
  with a warning when there is no `.git` folder.
- File writers normalize to LF and end each file with exactly one newline.

Constraints:

- `pwsh` is not installed on the development machine. The PowerShell
  scaffolder cannot be run locally.
- GitHub Actions expressions (`${{ ... }}`) and shell text appear in
  templates, so placeholders cannot use `$name` syntax.
- Windows runners check out with `core.autocrlf=true`; the repository already
  pins `templates/** text eol=lf`, and the rule must follow the templates to
  their new location.

## Chosen Design

Rebuild in Python, prove equal output, then improve:

1. Port each profile and prove the new output equals the old scaffolder's,
   file by file.
2. Land the deliberate output changes, one commit each.
3. Delete the old scaffolders, installers, shell tests, and comparison tests;
   keep snapshot tests as the long-term guard.

Rejected: a clean rewrite with only real-tool e2e (it would not catch a lost
`.gitignore` line or CI step); a line-by-line translation of `new-project.sh`
(it keeps 1,300 lines of inline text, the current maintenance problem).

## Components, Interfaces, and Data Flow

```text
repo-seed/
|-- pyproject.toml          # project "reposeed"; reposeed = "reposeed.cli:main"
|-- src/reposeed/
|   |-- __init__.py         # __version__
|   |-- cli.py              # argparse -> Options; main() -> exit code
|   |-- create.py           # create(options, runner, cwd, home): runs a profile
|   |-- profiles.py         # Profile descriptions for base/desktop/web/game
|   |-- render.py           # placeholder filling, LF writing, appends
|   |-- tools.py            # Runner, tool lookup, version checks
|   |-- versions.py         # load_versions(path) -> dict[str, str]
|   |-- versions.env
|   `-- templates/
|       |-- common/  base/  desktop/  web/  game/  scripts/
`-- tests/
```

### Options (`cli.py`)

A frozen dataclass `Options` with fields `name: str`, `python: str`,
`type_mode: str`, `profile: str`, `no_git: bool`, `no_install_hooks: bool`,
`no_github_actions: bool`. `main(argv: list[str] | None = None) -> int` parses
arguments, calls `create`, and returns the exit code. `--version` prints
`reposeed <__version__>`.

### Profiles (`profiles.py`)

A profile is data: a frozen dataclass `Profile` with

- `name: str`
- `layout: Literal["single", "split"]` — `single` is a uv project at the root
  (`base`, `desktop`); `split` is `backend/` + `frontend/` (`web`, `game`).
- `runtime_pins: tuple[str, ...]` and `dev_pins: tuple[str, ...]` — `versions.env`
  keys.
- `files: tuple[FileSpec, ...]` — `FileSpec(template: str, dest: str,
  mode: Literal["write", "append"], when: Literal["always", "github_actions"])`.
  `dest` may contain placeholders (for example `src/__PACKAGE_NAME__/ui/`).
- `npm_install: bool`, `playwright: bool`.
- `hooks: Literal["per_tool", "pre_push"]`.
- `fresh_paths: tuple[str, ...]` — paths that must not exist.

`PROFILES: dict[str, Profile]`. `create.py` contains no profile-specific
branches; differences live in profile data and templates. Shared files are
listed once in a shared tuple that profiles include.

### Rendering (`render.py`)

- Placeholders are `__UPPER_SNAKE__` tokens. Context keys: `PROJECT_NAME`,
  `PACKAGE_NAME`, `BACKEND_PACKAGE_NAME`, `PYTHON_VERSION`, `RUFF_TARGET`,
  `TYPE_MODE`, plus every `versions.env` key as `PIN_<KEY>`.
- `render(text: str, context: Mapping[str, str]) -> str` replaces every known
  token, then raises `TemplateError` naming the template and token if any
  `__[A-Z][A-Z0-9_]*__` token remains. Python dunder names (`__file__`,
  `__name__`, `__main__`, `__init__`) are lowercase and never match.
- `write(path: Path, text: str) -> None` creates parents, normalizes CRLF/CR to
  LF, strips trailing newlines, writes exactly one, encoding UTF-8 without BOM.
- `append(path: Path, text: str) -> None` follows the current `add_text_file`
  semantics exactly; its first test pins them against the Bash function.

### Tools (`tools.py`)

- `Runner` protocol: `run(command: Sequence[str], cwd: Path) -> None` and
  `which(name: str) -> str | None` and `output(command: Sequence[str]) -> str`.
- `SubprocessRunner` resolves with `shutil.which` (so `npm.cmd` works on
  Windows), runs without a shell, and raises `CommandError(command, code)` on
  non-zero exit.
- `version_at_least(actual: str, minimum: str) -> bool` compares dotted
  integers.

### Data flow (`create.py`)

`create(options: Options, runner: Runner, cwd: Path, home: Path) -> None`:

1. Validate: refuse `cwd == home`; refuse existing `fresh_paths`.
2. Preflight tools.
3. `git init` unless `no_git`; warn and skip when git is missing.
4. `uv init` (root for `single`, `backend` for `split`), `uv add --dev`,
   `uv add` with pins from `versions.env`.
5. Render and write or append each `FileSpec` whose `when` applies.
6. `npm install --no-audit --legacy-peer-deps` in `frontend/` when
   `npm_install`; `npm exec playwright install chromium` when `playwright`.
7. Install hooks unless `no_install_hooks`; warn and skip without `.git`.
8. Print `Done. Next: uv run scripts/check.py`.

The command order and arguments for steps 3–7 match the old Bash scaffolder for
`base`, `web`, `game`, and the PowerShell scaffolder for `desktop`.

## Functional Behavior

### Usage

```text
reposeed [--name NAME] [--python VERSION] [--type-mode off|basic|standard|strict]
         [--profile base|desktop|web|game] [--no-git] [--no-install-hooks]
         [--no-github-actions] [--version] [-h]
```

Defaults: name = current folder name, `--python 3.12`, `--type-mode standard`,
`--profile base`. PowerShell-style `-Profile` options are not accepted.

### Deliberate output changes after equality is proven

1. Generated READMEs use shell-neutral commands. Every
   `pushd <dir> >/dev/null; <cmd>; popd >/dev/null` and
   `Push-Location <dir>; <cmd>; Pop-Location` becomes `uv --directory <dir> ...`
   for uv commands and `npm --prefix <dir> ...` for npm commands, for example
   `uv --directory backend run uvicorn <pkg>.main:app --reload` and
   `npm --prefix frontend run dev`.
2. `desktop` is available on every OS.
3. `--version` prints `reposeed <version>`.
4. The generated `desktop` CI workflow installs `libegl1` before syncing
   dependencies (`sudo apt-get update && sudo apt-get install -y libegl1`).

## Error Handling and Boundary Conditions

- Validation and preflight failures print `error: <message>` to stderr and exit
  1, with no traceback. Messages keep the current wording.
- `CommandError` prints `error: '<command>' failed with exit code <code>`, then
  `The project folder is incomplete; delete it and run reposeed again.`, and
  exits with the command's code.
- `TemplateError` prints the template path and unfilled token and exits 1; it
  is a RepoSeed bug, caught by snapshot tests before release.
- A missing `versions.env` key raises a clear error naming the key.
- Unknown options and invalid choices use argparse's standard message and
  exit 2.

## Compatibility, Migration, and Platform Constraints

- The `reposeed` command name stays. The owner reinstalls with
  `uv tool install --editable ~/Development/repo-seed`, replacing the
  `~/.local/bin/reposeed` wrapper and `~/.local/share/reposeed` data written by
  `install.sh`; the README tells the owner to delete those two paths first.
- An editable install follows the checked-out branch.
- RepoSeed requires Python 3.10+ (chosen by uv) and no packages.
- `.gitattributes` becomes `src/reposeed/templates/** text eol=lf`.
- Package data: templates and `versions.env` ship inside the package and are
  read with `importlib.resources`.

## Acceptance Criteria

### Scenario: Equal output for ported profiles

Given fake `uv`/`npm` on PATH and the same options, when the old Bash
scaffolder and the new `reposeed` each generate `base`, `web`, and `game`,
then every generated file is byte-identical and the same commands run in the
same order.

### Scenario: Desktop equals the PowerShell output

Given the expected desktop tree derived from `new-project.ps1` (the `base` tree
plus `src/<pkg>/{ui,models,services}/__init__.py`, `ui/main_window.py`,
`__main__.py`, `tests/test_desktop_smoke.py`, `PySide6==<PY_PYSIDE6>`, and the
desktop README lines), then `reposeed --profile desktop` produces it; and the
Windows CI job confirms it against the real PowerShell scaffolder before that
scaffolder is deleted.

### Scenario: Snapshot guard

Given `tests/snapshots/<profile>/`, when any template or scaffolder change
alters generated output, then the snapshot test fails with a diff, and
`pytest --update-snapshots` rewrites the snapshots.

### Scenario: Real projects pass their checks

Given real tools, when each profile is generated, then
`uv run scripts/check.py` passes from the project root and from a subfolder,
on Linux and Windows.

### Scenario: Installed command

Given `uv tool install --editable .`, then `reposeed --version` prints the
package version and `reposeed --profile web` in an empty folder creates a
working project, on Linux and Windows.

### Scenario: Unfilled placeholder

Given a template containing `__NOT_A_KEY__`, when it is rendered, then
`TemplateError` names the template and the token.

### Scenario: Old entry points removed

After the switch-over, `new-project.sh`, `new-project.ps1`, `install.sh`,
`install.ps1`, `tests/*.sh`, and `tests/*.ps1` do not exist, and the README
documents only `uv tool install`.

## Testing Strategy

- **Runner injection.** Fast tests pass a `FakeRunner` that records commands
  and simulates `uv init` output (`pyproject.toml`, `src/<pkg>/__init__.py`,
  `.gitignore`, `.python-version`, `README.md` as uv writes them), so they run
  identically on both OSes.
- **Unit tests:** naming rules, `render` (including unfilled tokens and
  dunders), `write`/`append`, `load_versions`, `version_at_least`, option
  parsing, every error message.
- **Snapshot tests:** one per profile, comparing the full generated tree and
  the recorded command list (paths written with `/` on every OS) to
  `tests/snapshots/<profile>/`.
- **Comparison tests (temporary, Linux):** run old `new-project.sh` and new
  `reposeed` (with `SubprocessRunner`) against the same PATH-based fake
  `uv`/`npm` from `tests/cross_platform_contract.sh`; deleted with the old
  scaffolders.
- **Real e2e** (`pytest -m e2e`, default off locally, on in CI): every profile,
  `check.py` from root and a subfolder; desktop with `QT_QPA_PLATFORM=offscreen`.
- **Lint:** ruff (`E,F,I,B,UP,SIM,C4,PT,RUF`, line length 100) and strict
  pyright over `src/reposeed` and the script templates; RepoSeed's own dev
  tools are pinned in its `pyproject.toml` dependency group using the
  `versions.env` values.
- **CI:** one workflow, matrix `ubuntu-latest` and `windows-latest`: lint,
  unit + snapshot, e2e for every profile; the Linux job installs `libegl1`
  before the desktop e2e; the weekly drift schedule stays.
- **Local verification:** everything except the Windows job runs on the
  development machine. Windows is verified when the owner pushes and tests.

## Order of Work

All work on `dev`; the repository is usable after each phase.

1. Package skeleton (`cli`, `render`, `versions`, `tools`, `create`), `base`
   profile, comparison test for `base`.
2. `web` and `game`, each with a comparison test.
3. `desktop` against the expected tree.
4. Switch-over: delete old entry points and shell tests, add snapshot tests and
   the two-OS CI, land the four deliberate changes, update README and
   CHANGELOG, reinstall the owner's `reposeed`.

## Mechanical Assumptions and Deferred Work

- `FakeRunner`'s simulated `uv init` output is copied from a real `uv init`
  run with the uv installed on the development machine (0.13.3), and recorded
  in the plan.
- The equality phase uses the Bash scaffolder as written on `dev` at commit
  `926990e`.
- Deferred: the minor issues recorded from the cross-platform-scripts review
  (Ctrl-C traceback in `check.py`, missing-folder traceback, stderr test).
