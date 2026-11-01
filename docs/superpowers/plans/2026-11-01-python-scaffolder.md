# Single Python Scaffolder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `new-project.sh`, `new-project.ps1`, `install.sh` and `install.ps1` with one stdlib-only Python package, `reposeed`, installed with `uv tool install`, that generates identical projects on Linux and Windows for `base`, `desktop`, `web` and `game`.

**Architecture:** `src/reposeed/` holds a CLI, a profile-agnostic `create()` that runs data-only `Profile` descriptions, a `__TOKEN__` renderer, and a `Runner` seam for `uv`/`npm`/`git`. Every generated file is a template under `src/reposeed/templates/`. Each profile is first proven byte-equal to the old scaffolder, then snapshot tests take over and the old entry points are deleted.

**Tech Stack:** Python 3.10+ standard library, argparse, importlib.resources, uv_build, pytest, ruff, pyright, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-31-python-scaffolder-design.md`

## Global Constraints

- RepoSeed has no runtime dependencies; `requires-python = ">=3.10"`; version `0.2.0`.
- Entry point: `reposeed = "reposeed.cli:main"`; build backend `uv_build>=0.13.3,<0.14.0`.
- RepoSeed dev pins equal the `versions.env` values: `pytest==9.1.1`, `ruff==0.16.9`, `pyright==1.1.414`; a test enforces equality.
- Placeholders are `__UPPER_SNAKE__`; any `__[A-Z][A-Z0-9_]*__` left after rendering raises `TemplateError`.
- Context keys: `PROJECT_NAME`, `PACKAGE_NAME`, `BACKEND_PACKAGE_NAME`, `PYTHON_VERSION`, `RUFF_TARGET`, `TYPE_MODE`, and `PIN_<KEY>` for every `versions.env` key.
- Written files: LF only, exactly one trailing newline, UTF-8 without BOM.
- Error output: `error: <message>` on stderr, exit 1, no traceback; failed command: `error: '<command>' failed with exit code <code>` then `The project folder is incomplete; delete it and run reposeed again.`, exit with that code.
- Until the switch-over (Task 9), output must equal the old scaffolders byte for byte. **Where the spec's step summary and the old scaffolder's actual command order differ, the old scaffolder is binding** (see Task 4 ruling).
- Ruff `E,F,I,B,UP,SIM,C4,PT,RUF`, line length 100; pyright strict over `src/reposeed`.
- `pwsh` is not installed locally; anything needing it is skipped locally and runs in CI. Never push without the owner's go-ahead.
- Commits carry no attribution lines.

## Review Focus

- Running `reposeed` in a folder whose name has spaces, capitals or symbols (`My App!`): project name `my-app`, package `my_app`. Pinned in Task 2 naming tests.
- A Windows path for `cwd` in recorded commands and snapshots: commands record paths relative to the project with `/`. Pinned in Task 4 FakeRunner test.
- Template file that contains a literal `__init__` or GitHub `${{ secrets.X }}`: must pass through unchanged. Pinned in Task 2 render tests.
- `uv` installed but `node` missing for `web`: clear preflight error before anything is written. Pinned in Task 3.
- The installed (non-editable) package missing templates: `uv build` wheel must contain every template. Pinned in Task 8.

---

### Task 1: Package skeleton and resource move

**Files:**
- Create: `pyproject.toml`, `src/reposeed/__init__.py`, `tests/__init__.py` (empty), `tests/test_package.py`
- Move: `git mv templates src/reposeed/templates`, `git mv versions.env src/reposeed/versions.env`
- Modify: `.gitattributes`, `new-project.sh:109,139`, `new-project.ps1:122` and its `versions.env` path, `install.sh:105-106,149-150`, `install.ps1:87-88,163-168`, `tests/script_templates_contract.sh`, `tests/lint_script_templates.sh`, `tests/pyright-script-templates.json`, `tests/scaffold_e2e.sh`, `tests/cross_platform_contract.sh`, `tests/scaffold_e2e.ps1`, `tests/powershell_web_contract.ps1`, `.gitignore` (add `.venv/`, `dist/`)

**Interfaces:**
- Produces: `reposeed.__version__ == "0.2.0"`; resources at `src/reposeed/templates/` and `src/reposeed/versions.env`.

- [ ] **Step 1: Write `tests/test_package.py`**

```python
def test_version() -> None:
    assert reposeed.__version__ == "0.2.0"

def test_dev_pins_match_versions_env() -> None:
    # parse [dependency-groups].dev from pyproject.toml with tomllib on 3.11+,
    # or a regex on 3.10; parse versions.env lines KEY=value
    assert dev["pytest"] == env["PY_PYTEST"]
    assert dev["ruff"] == env["PY_RUFF"]
    assert dev["pyright"] == env["PY_PYRIGHT"]
```

- [ ] **Step 2: Run it** — `uv run pytest tests/test_package.py` — Expected: FAIL (no project / no package).

- [ ] **Step 3: Write `pyproject.toml` and `src/reposeed/__init__.py`**

`[project]` per Global Constraints, `readme = "README.md"`, `license = "MIT"`; `[dependency-groups] dev = ["pytest==9.1.1", "ruff==0.16.9", "pyright==1.1.414"]`; `[tool.pytest.ini_options] testpaths = ["tests"]`, `markers = ["e2e: real-tool scaffolds (slow)"]`, `addopts = "-m 'not e2e'"`; `[tool.ruff]` per Global Constraints with `target-version = "py310"`; `[tool.pyright] include = ["src"]`, `typeCheckingMode = "strict"`, `pythonVersion = "3.10"`.

- [ ] **Step 4: Move resources and repoint old entry points**

`git mv` both. `.gitattributes`: `src/reposeed/templates/** text eol=lf`. In both scaffolders resolve a resource root: `src/reposeed` next to the script if it exists, otherwise the script's own folder (the installed payload layout). Installers copy `src/reposeed/templates` and `src/reposeed/versions.env` into the payload at the same names as today. Update every test path from `templates/` / `versions.env` to `src/reposeed/...`.

Ruling recorded in the plan: resources move now, not at switch-over, so the package reads them from their final place from the first commit; the fallback lookup is deleted with the old scaffolders in Task 9.

- [ ] **Step 5: Verify**

- `uv run pytest` → 2 passed.
- `bash tests/script_templates_contract.sh` → `script template contract tests passed`.
- `bash tests/cross_platform_contract.sh` → `cross-platform contract tests passed` (exercises install.sh and the moved paths).

- [ ] **Step 6: Commit** — `git commit -m "build: make RepoSeed a Python package and move templates into it"`

---

### Task 2: Naming, versions and rendering

**Files:**
- Create: `src/reposeed/naming.py`, `src/reposeed/versions.py`, `src/reposeed/render.py`
- Test: `tests/test_naming.py`, `tests/test_versions.py`, `tests/test_render.py`

**Interfaces:**
- Produces: `project_name(raw: str) -> str`, `package_name(project: str) -> str`, `ruff_target(python: str) -> str`
- Produces: `load_versions(text: str) -> dict[str, str]`, `bundled_versions() -> dict[str, str]`, `class VersionsError(ValueError)`
- Produces: `render(text: str, context: Mapping[str, str], *, source: str) -> str`, `class TemplateError(ValueError)`, `write_file(path: Path, text: str) -> None`, `append_file(path: Path, text: str) -> None`, `read_template(name: str) -> str` (via `importlib.resources.files("reposeed") / "templates" / name`)

- [ ] **Step 1: Write the tests**

- naming: `project_name("My App!") == "my-app"`, `project_name("--x__y--") == "x-y"`, `project_name("!!!") == "python-project"`, `package_name("my-app") == "my_app"`, `ruff_target("3.13") == "py313"`, `ruff_target("latest") == "py312"`.
- versions: valid `KEY=value` lines and `#` comments/blank lines parse; a line `bad line` raises `VersionsError` containing `Invalid line in versions.env: bad line`; `bundled_versions()["PY_PYTEST"] == "9.1.1"`.
- render: `render("a __PROJECT_NAME__ b", {"PROJECT_NAME": "x"}, source="t") == "a x b"`; `__init__`, `__name__`, `${{ secrets.X }}` unchanged; `__NOT_A_KEY__` raises `TemplateError` whose message contains `t` and `__NOT_A_KEY__`.
- write_file: `"a\r\nb\n\n\n"` is stored as `b"a\nb\n"`; parents are created.
- append_file, matching `add_text_file` in `new-project.sh:79-105` exactly: leading newlines of the appended text are stripped; missing file → same as `write_file`; whitespace-only existing file → replaced by the appended text; otherwise existing text minus one trailing `\n`, then `\n`, then the appended text, then one trailing newline. Cases: (`"a\n"`, `"\nb"`) → `"a\nb\n"`; (`"a\n\n"`, `"b\n"`) → `"a\n\nb\n"`; (`"  \n"`, `"b"`) → `"b\n"`.

- [ ] **Step 2: Run** — `uv run pytest tests/test_naming.py tests/test_versions.py tests/test_render.py` — Expected: FAIL (modules missing).

- [ ] **Step 3: Implement the three modules** to the signatures above. Name rules come from `new-project.sh:256-268`.

- [ ] **Step 4: Run** — same command — Expected: all pass. Then `uv run ruff check . && uv run ruff format --check . && uv run pyright` → clean.

- [ ] **Step 5: Commit** — `git commit -m "feat: add naming, versions and template rendering"`

---

### Task 3: Tools and CLI

**Files:**
- Create: `src/reposeed/tools.py`, `src/reposeed/cli.py`, `src/reposeed/__main__.py`
- Test: `tests/test_tools.py`, `tests/test_cli.py`

**Interfaces:**
- Produces in `tools.py`: `class Runner(Protocol)` with `run(self, command: Sequence[str], cwd: Path) -> None`, `which(self, name: str) -> str | None`, `output(self, command: Sequence[str]) -> str`; `class SubprocessRunner`; `class CommandError(Exception)` with `command: tuple[str, ...]`, `code: int`; `class SetupError(Exception)` (user-facing, message only); `version_at_least(actual: str, minimum: str) -> bool`; `extract_version(text: str) -> str | None` (first `\d+(\.\d+)+`); `require_uv(runner, minimum) -> None`; `require_node(runner, minimum, profile) -> None`.
- Produces in `cli.py`: `@dataclass(frozen=True) class Options` (fields per spec), `parse_args(argv: Sequence[str] | None) -> Options`, `main(argv: Sequence[str] | None = None) -> int`. `main` calls `reposeed.create.create(options, SubprocessRunner(), Path.cwd(), Path.home())` and maps `SetupError`, `VersionsError`, `TemplateError` → exit 1 and `CommandError` → its code, with the messages in Global Constraints.

- [ ] **Step 1: Write the tests**

- `version_at_least("0.13.3", "0.5.0")`, not `version_at_least("21.9.0", "22.13.0")`, `version_at_least("22.13.0", "22.13.0")`.
- `require_uv` with a stub runner: `which("uv") is None` → `SetupError("uv was not found on PATH. Install uv first, then rerun this script.")`; output `uv 0.4.0` → message `uv 0.4.0 is too old. RepoSeed needs uv 0.5.0 or newer. Run 'uv self update' and retry.`
- `require_node` with `node` missing → `node and npm were not found on PATH. Install Node.js first, then rerun this script.`; `v21.0.0` → `Node.js 21.0.0 is too old. RepoSeed needs Node.js 22.13.0 or newer for the web profile.`
- `parse_args([])` → defaults (name = `Path.cwd().name`, `3.12`, `standard`, `base`, switches false); `--profile desktop` accepted; `--profile nope` → `SystemExit` code 2; `--version` prints `reposeed 0.2.0` and exits 0.
- `main` with `create` monkeypatched to raise each error: exit codes 1/1/1/7 and stderr text exactly per Global Constraints; no `Traceback` in stderr.

- [ ] **Step 2: Run** — `uv run pytest tests/test_tools.py tests/test_cli.py` — Expected: FAIL.

- [ ] **Step 3: Implement.** `SubprocessRunner.run` resolves `command[0]` with `shutil.which` (missing → `SetupError(f"'{name}' was not found on PATH.")`), runs with `check=False`, no shell, inherited stdio; non-zero → `CommandError`. `__main__.py` calls `raise SystemExit(main())`. `create.py` does not exist yet; import it inside `main` so this task's tests can monkeypatch `reposeed.create.create` (create a stub `create.py` with `def create(...) -> None: raise NotImplementedError` and the Task 4 signature).

- [ ] **Step 4: Run** — same — all pass; lint clean.

- [ ] **Step 5: Commit** — `git commit -m "feat: add CLI and tool checks"`

---

### Task 4: Profiles, create() and the base profile, proven equal to Bash

**Files:**
- Create: `src/reposeed/profiles.py`, `src/reposeed/create.py` (replace stub)
- Create templates from `new-project.sh` (copy text verbatim; Bash `$VAR` → `__TOKEN__`): `templates/common/editorconfig`, `templates/common/gitattributes`, `templates/common/env.example`, `templates/base/pyproject.append.toml` (lines 284-348), `templates/base/gitignore.append` (399-432), `templates/base/init.py`, `templates/base/test_smoke.py`, `templates/base/pre-commit-config.yaml` (1202-1232), `templates/base/README.md` (1234-1250), `templates/base/ci.yml` (867-902). Exact line ranges: read the function bodies listed in `new-project.sh`'s outline; ranges above are as of commit `926990e`.
- Test: `tests/fakes.py`, `tests/test_create.py`, `tests/test_compare_bash.py`

**Interfaces:**
- Consumes: Task 2 render API, Task 3 `Runner`, `Options`, `SetupError`, `require_uv`, `require_node`.
- Produces in `profiles.py`: frozen dataclasses `FileSpec(template: str, dest: str, mode: Literal["write", "append"] = "write", when: Literal["always", "github_actions"] = "always")`, `UvAdd(dev: bool, pins: tuple[str, ...])`, `Profile(name, layout: Literal["single", "split"], uv_adds: tuple[UvAdd, ...], files: tuple[FileSpec, ...], npm_install: bool, playwright: bool, hooks: Literal["per_tool", "pre_push"], fresh_paths: tuple[str, ...], needs_node: bool)`; `PROFILES: dict[str, Profile]`. `pins` are `versions.env` keys; the package name for each key lives in one map `PIN_PACKAGES: dict[str, str]` (`"PY_RUFF": "ruff"`, …).
- Produces in `create.py`: `create(options: Options, runner: Runner, cwd: Path, home: Path) -> None`.
- Produces in `tests/fakes.py`: `FakeRunner(Runner)` recording `run` and `output` calls in `calls: list[str]` as `"<command> | <cwd>"` (command joined by spaces; cwd relative to the project with `/`, `.` for the root; `output` calls use `.`) and `uv init` simulation; `fake_bin(dir: Path, log: Path) -> Path` writing Bash fakes for `uv`, `npm`, `git` that append `<tool> <args> | <cwd relative>` to `log`, with the `uv init` behavior of `prepend_fake_uv` in `tests/cross_platform_contract.sh` plus: `git init` creates `.git/`; `uv init` without `--vcs none` creates `.git/` and the `.gitignore` captured below.

Ruling: command order follows the old scaffolders, not the spec's step summary. `single` profiles do not call `git init`; they run `uv init --package --name <project> --python <v>` (adding `--vcs none` only with `--no-git`) and uv creates the repository. `split` profiles run `git init` (unless `--no-git`; warn `git was not found on PATH. Skipping git init.` if missing), then `uv init --package --name <project>-backend --python <v> --vcs none backend`. `base` adds dev pins then runtime pins; `web`/`game` add runtime + FastAPI + uvicorn, then dev pins, both in `backend/`.

FakeRunner `uv init` writes (values from a real `uv init` with uv 0.13.3, authors line omitted): `pyproject.toml` with `[project]` name/version `0.1.0`/description `Add your description here`/readme/`requires-python = ">=<v>"`/`dependencies = []`, `[project.scripts] <project> = "<pkg>:main"`, `[build-system] requires = ["uv_build>=0.13.3,<0.14.0"]`, `build-backend = "uv_build"`; `.python-version` (`<v>`); empty `README.md`; `src/<pkg>/__init__.py` with uv's hello `main()`; and, without `--vcs none`, `.git/` plus `.gitignore` containing uv's `# Python-generated files` / `# Virtual environments` block.

- [ ] **Step 1: Write the tests**

- `test_create.py` (FakeRunner): base in an empty tmp folder → `calls` equals `["uv --version | .", "uv init --package --name demo-app --python 3.12 | .", "uv add --dev ruff==0.16.9 pytest==9.1.1 pytest-cov==7.1.0 pyright==1.1.414 pre-commit==4.6.2 | .", "uv add python-dotenv==1.2.3 | .", "uv run pre-commit install | .", "uv run pre-commit install --hook-type pre-push | ."]`; with `no_git=True` the init has `--vcs none` and no hook calls, and stdout warns `No .git directory found. Skipping hook installation.`; `cwd == home` → `SetupError` with the HOME message; existing `pyproject.toml` → `SetupError("pyproject.toml already exists. Run this only in a fresh project directory.")` and no calls; stdout ends with `Done. Next: uv run scripts/check.py`.
- `test_compare_bash.py` (skipped unless `sys.platform == "linux"` and `bash` exists): for options `[]` and `["--no-git", "--no-install-hooks", "--no-github-actions"]`, run `new-project.sh --name demo-app <opts>` and `python -m reposeed --name demo-app <opts>` in two empty folders with the same `fake_bin` on PATH; assert the two file trees (excluding `.git/`) are byte-identical and the two command logs are identical. Helper `tree(dir) -> dict[str, bytes]`.

- [ ] **Step 2: Run** — `uv run pytest tests/test_create.py tests/test_compare_bash.py` — Expected: FAIL.

- [ ] **Step 3: Implement** `profiles.py` (base only), `create.py`, the base templates, and `tests/fakes.py`. `create` keeps the old stdout lines (`Creating Python project: ...`, `Adding dev tooling...`, `Adding runtime dependencies...`, `Installing pre-commit and pre-push hooks...`). Base writes `scripts/check.py`/`fix.py` from `scripts/base/`.

- [ ] **Step 4: Run** — same — Expected: pass, including both comparison cases. Lint clean.

- [ ] **Step 5: Commit** — `git commit -m "feat: generate the base profile from Python"`

---

### Task 5: web profile

**Files:**
- Create templates from `new-project.sh` (verbatim, `$VAR`/`$(version_of K)` → `__TOKEN__`/`__PIN_K__`): `templates/web/` `pyproject.append.toml` (535-587), `gitignore.append` (494-530), `package.json` (626-671), `tsconfig.app.json` (719-738), `vite.config.ts` (786-819), `eslint.config.js` (821-845), `index.html` (678-689 with `/src/main.tsx`), `README.md` (1135-1155 with no Playwright line), `pre-commit-config.yaml` (1157-1165), `ci.yml` (908-981); `templates/common/` `npmrc` (673), `tsconfig.json` (691-698), `tsconfig.node.json` (740-754), `vite-env.d.ts` (853), `backend_init.py`. Re-check each range against the function bodies before copying. Where a file the base profile already templated (`.editorconfig`, `.gitattributes`, `.env.example`) has different web text (`new-project.sh:447-531`), keep two templates (`base/…`, `web/…`) instead of sharing one.
- Modify: `src/reposeed/profiles.py`, `src/reposeed/create.py` (split layout + npm steps)
- Test: `tests/test_create.py`, `tests/test_compare_bash.py`

**Interfaces:**
- Consumes: Task 4 `Profile`, `FileSpec`, `UvAdd`, `fake_bin`, `tree`.
- Produces: `PROFILES["web"]` with `layout="split"`, `fresh_paths=("backend", "frontend", "package.json", "pyproject.toml")`, `npm_install=True`, `hooks="pre_push"`, `needs_node=True`.

- [ ] **Step 1: Tests** — FakeRunner web call list: `uv --version`, `node --version`, `git init | .`, `uv init --package --name demo-app-backend --python 3.12 --vcs none backend | .`, `uv add python-dotenv==1.2.3 fastapi==0.141.1 uvicorn==0.54.0 | backend`, `uv add --dev <5 dev pins> | backend`, `npm install --no-audit --legacy-peer-deps | frontend`, `uv --project backend run pre-commit install --hook-type pre-push | .`; existing `frontend/` → the "already exists" error; comparison case for `--profile web` with both option sets.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** the web profile data and split-layout steps in `create.py` (no `if profile == "web"`; use profile fields).
- [ ] **Step 4: Run** — `uv run pytest` — Expected: all pass.
- [ ] **Step 5: Commit** — `git commit -m "feat: generate the web profile from Python"`

---

### Task 6: game profile

**Files:**
- Create templates: `templates/game/` `package.json` (596-624), `tsconfig.app.json` (700-717), `vite.config.ts` (756-766), `eslint.config.js` (768-782), `index.html` (with `/src/main.ts`), `README.md` (with the Playwright setup line), `ci.yml` (983-1051); reuse existing `game/*.ts`, `game/*.py`, `game/style.css`.
- Modify: `src/reposeed/profiles.py`
- Test: `tests/test_create.py`, `tests/test_compare_bash.py`

**Interfaces:**
- Produces: `PROFILES["game"]` (`playwright=True`, otherwise as web with game templates).

- [ ] **Step 1: Tests** — game call list equals web's plus `npm exec playwright install chromium | frontend` right after `npm install`; comparison case for `--profile game`.
- [ ] **Step 2: Run** — FAIL. **Step 3: Implement.** **Step 4: Run** `uv run pytest` — all pass.
- [ ] **Step 5: Commit** — `git commit -m "feat: generate the game profile from Python"`

---

### Task 7: desktop profile

**Files:**
- Create: `templates/desktop/README.md` (base README plus `    uv run python -m __PACKAGE_NAME__` before the check line and the source sentence `Source code lives in src/__PACKAGE_NAME__/. UI code lives in src/__PACKAGE_NAME__/ui/. Tests live in tests/.`, matching `new-project.ps1` lines for `$ReadmeCommands`/`$SourceDescription`)
- Modify: `src/reposeed/profiles.py`
- Test: `tests/test_create.py`, `tests/test_compare_powershell.py`

**Interfaces:**
- Produces: `PROFILES["desktop"]`: base plus `UvAdd(dev=False, pins=("PY_PYSIDE6",))` after the runtime add; files `src/__PACKAGE_NAME__/{ui,models,services}/__init__.py` (empty), `desktop/main_window.py` → `src/__PACKAGE_NAME__/ui/main_window.py`, `desktop/__main__.py` → `src/__PACKAGE_NAME__/__main__.py`, `desktop/test_desktop_smoke.py` → `tests/test_desktop_smoke.py`; README from `templates/desktop/README.md`.

- [ ] **Step 1: Tests**
  - FakeRunner: desktop calls equal base's with `uv add PySide6==6.11.2 | .` inserted after the runtime add; tree equals the base tree plus exactly the seven desktop paths, with README differing only in the two desktop lines.
  - `test_compare_powershell.py` (skipped unless `pwsh` is on PATH and the platform is Linux): run `new-project.ps1 -Name demo-app -Profile desktop -NoGit -NoInstallHooks -NoGitHubActions` and `reposeed --name demo-app --profile desktop --no-git --no-install-hooks --no-github-actions` against the same `fake_bin`; trees byte-identical.
- [ ] **Step 2: Run** — FAIL (PowerShell comparison reports skipped locally).
- [ ] **Step 3: Implement.** **Step 4: Run** `uv run pytest` — all pass, PowerShell comparison skipped.
- [ ] **Step 5: Commit** — `git commit -m "feat: generate the desktop profile from Python"`

---

### Task 8: Snapshots, real e2e, packaging check and two-OS CI

**Files:**
- Create: `tests/test_snapshots.py`, `tests/conftest.py` (`--update-snapshots` option), `tests/snapshots/<profile>/` (generated), `tests/test_e2e.py`, `tests/test_wheel.py`
- Replace: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: `FakeRunner`, `tree`, `create`.

- [ ] **Step 1: Tests**
  - Snapshots: for each profile with `--name demo-app` (and git on), the FakeRunner tree plus `commands.txt` (one call per line) must equal `tests/snapshots/<profile>/`; with `--update-snapshots` the folder is rewritten and the test passes. Excludes `.git/`.
  - Wheel: `uv build --wheel --out-dir <tmp>`; the wheel's names include every file under `src/reposeed/templates/` and `reposeed/versions.env`.
  - e2e (`@pytest.mark.e2e`, parametrized over the four profiles): run `python -m reposeed --name <profile>-demo --no-git --no-install-hooks --no-github-actions` with `SubprocessRunner` in a tmp folder; then `uv run scripts/check.py`, `uv run scripts/fix.py`, `uv run scripts/check.py` at the root and `uv run ../scripts/check.py` from `tests/` (single) or `backend/` (split); all exit 0. desktop sets `QT_QPA_PLATFORM=offscreen`. `game` runs only when `REPOSEED_E2E_GAME=1`.
- [ ] **Step 2: Run** `uv run pytest` — Expected: snapshot tests FAIL (no snapshots); wheel test result read and recorded (pass means uv_build already ships data files).
- [ ] **Step 3: Generate snapshots** with `uv run pytest --update-snapshots tests/test_snapshots.py`; review one profile's tree by eye against Task 4–7 expectations. If the wheel lacks templates, configure uv_build to include them.
- [ ] **Step 4: CI workflow** — jobs on `ubuntu-latest` and `windows-latest` (matrix): checkout, setup-uv `v8.2.0`, setup-node 24, `uv sync --locked`, `uv run ruff format --check .`, `uv run ruff check .`, `uv run pyright`, `uv run pytest`, then `uv run pytest -m e2e` with `REPOSEED_E2E_GAME=1`. Linux runs `sudo apt-get update && sudo apt-get install -y libegl1` before e2e. Keep `push: main`, `pull_request`, weekly `cron: "17 6 * * 1"`, `workflow_dispatch`. Until Task 9 also keep the old Bash/PowerShell test steps (they still run the old scaffolders).
- [ ] **Step 5: Run** `uv run pytest` and `uv run pytest -m e2e` (with `REPOSEED_E2E_GAME=1`) locally — Expected: all pass (desktop e2e included).
- [ ] **Step 6: Commit** — `git commit -m "test: add snapshot, wheel and e2e tests; run CI on Linux and Windows"`

---

### Task 9: Switch-over — remove old entry points

**Files:**
- Delete: `new-project.sh`, `install.sh`, `install.ps1`, `tests/*.sh`, `tests/powershell_web_contract.ps1`, `tests/scaffold_e2e.ps1`, `tests/lint_script_templates.sh`, `tests/pyright-script-templates.json`, `tests/test_compare_bash.py`, `tests/fakes.py::fake_bin` (keep `FakeRunner`)
- Keep until the owner's first CI run: `new-project.ps1` and `tests/test_compare_powershell.py` (spec: desktop must be confirmed against the real PowerShell scaffolder before it is deleted; it runs in Linux CI, where `pwsh` exists).
- Modify: `.github/workflows/ci.yml` (drop old steps), `README.md`, `CHANGELOG.md`
- Test: `tests/test_package.py`

- [ ] **Step 1: Test** — `test_old_entry_points_removed`: none of `new-project.sh`, `install.sh`, `install.ps1` exist; no `tests/*.sh`.
- [ ] **Step 2: Run** — FAIL. **Step 3: Delete**, drop CI steps, and port the two still-useful checks from the deleted shell tests into pytest: script-template shared-helper identity and step lists (`tests/test_script_templates.py`, same assertions as `tests/script_templates_contract.sh`, using a FakeRunner-free subprocess run of the template with fake `uv`/`npm` written in Python and placed on PATH; on Windows the fakes are `.cmd` shims calling `sys.executable`).
- [ ] **Step 4: Docs** — README: install section becomes `uv tool install --editable <checkout>` / `uv tool install git+https://github.com/r3k4ce/repo-seed`, `uv tool update-shell`, and "delete `~/.local/bin/reposeed` and `~/.local/share/reposeed` from the old installer first"; usage uses `--options` only; Requirements: only `uv` (+ Node for web/game, git optional). CHANGELOG `[Unreleased]`: Changed — RepoSeed is a Python package installed with `uv tool install`; the Bash/PowerShell scaffolders and installers are removed; PowerShell-style options are gone; `desktop` works on Linux.
- [ ] **Step 5: Run** `uv run pytest` and lint — all pass.
- [ ] **Step 6: Commit** — `git commit -m "refactor!: remove the Bash and PowerShell scaffolders and installers"`

---

### Task 10: Deliberate output changes

**Files:**
- Modify: `templates/web/README.md`, `templates/game/README.md`, `templates/desktop/ci.yml` (new: copy of base CI plus the libegl1 step), `src/reposeed/profiles.py` (desktop uses `desktop/ci.yml`), `tests/snapshots/**`, `CHANGELOG.md`
- Test: `tests/test_snapshots.py`, `tests/test_create.py`

- [ ] **Step 1: Tests**
  - `test_readmes_are_shell_neutral`: no generated README (any profile) contains `pushd`, `popd`, `Push-Location`, `Pop-Location`; web README contains `uv --directory backend run uvicorn demo_app_backend.main:app --reload` and `npm --prefix frontend run dev`; game README contains `npm --prefix frontend exec playwright install chromium`.
  - `test_desktop_ci_installs_libegl1`: desktop `.github/workflows/ci.yml` contains `sudo apt-get update && sudo apt-get install -y libegl1` before the `uv sync` step.
- [ ] **Step 2: Run** — FAIL. **Step 3: Edit templates** (one commit per change: READMEs, desktop CI). **Step 4:** `uv run pytest --update-snapshots`, review the snapshot diff (`git diff tests/snapshots`) — only the intended lines change; `uv run pytest` passes.
- [ ] **Step 5: Commits** — `git commit -m "feat: shell-neutral commands in generated READMEs"` and `git commit -m "fix: install libegl1 in generated desktop CI"`, each with its CHANGELOG line.

---

### Task 11: Reinstall and final verification

- [ ] **Step 1:** Show the owner the two old install paths and ask before deleting them (`~/.local/bin/reposeed`, `~/.local/share/reposeed`); on yes, delete, then `uv tool install --editable /home/adrian/Development/repo-seed`.
- [ ] **Step 2:** From a scratch folder: `reposeed --version` → `reposeed 0.2.0`; `reposeed --profile desktop --no-git` then `uv run scripts/check.py` with `QT_QPA_PLATFORM=offscreen` → passes.
- [ ] **Step 3:** Full local run: `uv run ruff format --check . && uv run ruff check . && uv run pyright && uv run pytest && REPOSEED_E2E_GAME=1 uv run pytest -m e2e` → all pass.
- [ ] **Step 4:** Report what remains gated on the owner: pushing `dev`, the Windows CI job, the PowerShell desktop comparison, and then deleting `new-project.ps1` and `tests/test_compare_powershell.py`.
