# Changelog

All notable changes to RepoSeed are documented here.
See the README for the current project description and usage.

## [Unreleased]

### Added

- `versions.env` (now `src/reposeed/versions.env`): a single manifest of
  exact, tested versions for every package RepoSeed installs, plus minimum
  `uv` and Node.js versions.
- Preflight checks: RepoSeed now stops early with a clear message when
  `uv` or Node.js is older than the minimum in `versions.env`.
- Generated frontends get `frontend/.npmrc` (`save-exact`, `engine-strict`)
  and an `engines.node` field.
- Repository CI (`.github/workflows/ci.yml`) runs Ruff, Pyright, the unit,
  snapshot, wheel and script-template tests, and the scaffold e2e tests on
  Linux and Windows, on every push and weekly, to catch upstream drift.
- `docs/versioning.md` describes the version policy and the bump procedure.
- `reposeed --version` prints `reposeed <version>`.

### Changed

- **Breaking:** RepoSeed is a Python package, installed with
  `uv tool install git+https://github.com/r3k4ce/repo-seed` or
  `uv tool install --editable <checkout>`. `uv` is the only requirement.
  The Bash scaffolder `new-project.sh` and the installers `install.sh` and
  `install.ps1` are removed; delete `~/.local/bin/reposeed` and
  `~/.local/share/reposeed` from the old installer before installing. The
  PowerShell scaffolder `new-project.ps1` is no longer an entry point; it
  stays in the repository for now only as a CI comparison reference.
- **Breaking:** PowerShell-style options (`-Name`, `-Profile`, `-NoGit`, ...)
  are gone; `reposeed` takes the same `--options` on every OS.
- The `desktop` profile works on Linux (and every other OS), not only from
  PowerShell.
- The Bash and PowerShell test scripts under `tests/` are replaced by pytest;
  the script-template contract and lint now run as part of `uv run pytest`,
  `uv run ruff` and `uv run pyright`.
- Generated projects now get `scripts/check.py` and `scripts/fix.py`, run
  with `uv run scripts/check.py`, instead of `check.sh`/`fix.sh` or
  `check.ps1`/`fix.ps1`. The scripts are the same on every OS, so a
  project works on Linux and Windows. The `web`/`game` pre-push hook runs
  `uv run scripts/check.py`. Existing projects are not changed.
- Python dependencies are added with exact `==` pins instead of "whatever is
  newest today".
- Frontend `package.json` files use exact versions instead of `^` ranges, and
  the `game` profile no longer uses `"latest"` for any package.
- Tests assert against `versions.env` instead of hard-coded version strings.
- The web/game bootstrap runs `npm install --no-audit --legacy-peer-deps`.
  npm 10's peer-set loader crashes (`Cannot read properties of null (reading
  'edgesOut')`) on the generated dependency tree; the flag avoids it. Because
  legacy mode skips peer auto-install, `@testing-library/dom` (a required peer
  of `@testing-library/react`) is now pinned explicitly in `versions.env`.
- The generated `web` and `game` READMEs use shell-neutral commands
  (`uv --directory backend ...`, `npm --prefix frontend ...`) instead of
  `pushd`/`popd`, so they work in PowerShell, Bash and every other shell.
- `web` profile on Windows (`new-project.ps1`) now matches the bash scaffolder:
  pinned frontend dependencies, Tailwind CSS, Vitest coverage gates, and a
  required frontend typecheck. Generated web CI runs frontend test, typecheck,
  lint, and build (no Playwright).

### Fixed

- Generated `desktop` CI installs `libegl1` before syncing dependencies, so
  PySide6 imports no longer fail on `ubuntu-latest`.
- A project name that does not give a valid Python package (for example a
  folder called `2048`, or `--name class`) is refused before anything is
  written, instead of generating a project that fails its own checks. So is
  a name equal to a package RepoSeed installs (for example `--name pytest`).
- Running RepoSeed in a folder below another Python project no longer adds
  the new project to the parent's uv workspace and `uv.lock`: `uv init` now
  gets `--no-workspace`.

### Removed

- Stale planning artifacts (`.superpowers/`, `docs/superpowers/`) and the
  README section about a hand-written `np` PowerShell alias, which the
  installer's `reposeed` command replaces.
- Scaffolders no longer generate `AGENTS.md` in new projects, and the
  `templates/agents/` templates have been removed.
- Scaffolders no longer generate `docs/project-memory.yaml` (or a `docs/`
  folder) in new projects, and generated READMEs no longer have a Docs section.

## [v0.1.0] - 2026-06-30

### Added

- `new-project.ps1` scaffolder that turns an empty folder into a checked,
  agent-ready project (README.md:1-9, new-project.ps1:1-15).
- Four profiles, selected with `-Profile`:
  - `base` — uv-managed Python package with `src/` layout, tests, checks, CI.
  - `desktop` — `base` plus a PySide6 starter window under `src/<package>/ui/`.
  - `web` — FastAPI backend with a Vite + React + TypeScript frontend.
  - `game` — FastAPI backend with a Vite + TypeScript + Phaser frontend and a
    Playwright smoke test.
  (new-project.ps1:9, README.md:36-40)
- Generated tooling for every profile:
  - `uv` for Python packaging and dependency management.
  - Ruff for linting and formatting.
  - Pyright for static type checking (mode configurable via `-TypeMode`).
  - pytest with coverage (branch coverage, 80% fail-under).
  (new-project.ps1:931-940, README.md:46-49)
- PowerShell helper scripts: `scripts/check.ps1` and `scripts/fix.ps1` to run
  the full check/fix pipeline (new-project.ps1:1171-1214, README.md:50).
- GitHub Actions workflow at `.github/workflows/ci.yml` covering Ruff format,
  Ruff lint, Pyright, pytest, and (for `web` / `game`) frontend lint, build,
  unit tests, and Playwright e2e (new-project.ps1:820-898, 1269-1308).
- Pre-commit and pre-push hooks via `pre-commit` (new-project.ps1:1136-1167,
  README.md:52).
- `AGENTS.md` generated from a base template plus a profile-specific snippet
  (new-project.ps1:134-141, README.md:53).
- Project memory file at `docs/project-memory.yaml`, written as a YAML log
  entry with timestamp, summary, changed list, and verification step
  (new-project.ps1:1252-1265, README.md:54).
- Standard repo hygiene files: `.editorconfig`, `.gitattributes`, `.gitignore`,
  `.env.example` (new-project.ps1:1043-1134, 586-674 for web/game).
- Flags to opt out of side effects: `-NoGit`, `-NoInstallHooks`,
  `-NoGitHubActions` (new-project.ps1:12-14, README.md:142-144).

### Notes

- This is the first tracked release. No prior versions exist.
- Tags and GitHub releases are not part of this slice.
