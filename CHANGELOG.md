# Changelog

All notable changes to RepoSeed are documented here.
See the README for the current project description and usage.

## [Unreleased]

### Added

- `versions.env`: a single manifest of exact, tested versions for every
  package the scaffolders install, plus minimum `uv` and Node.js versions.
  Both `new-project.sh` and `new-project.ps1` read it; the installers ship it.
- Preflight checks: the scaffolders now stop early with a clear message when
  `uv` or Node.js is older than the minimum in `versions.env`.
- Generated frontends get `frontend/.npmrc` (`save-exact`, `engine-strict`)
  and an `engines.node` field.
- Repository CI (`.github/workflows/ci.yml`) runs shellcheck, the contract
  tests, and the scaffold e2e tests on Linux and Windows, on every push and
  weekly, to catch upstream drift.
- `docs/versioning.md` describes the version policy and the bump procedure.

### Changed

- Python dependencies are added with exact `==` pins instead of "whatever is
  newest today".
- Frontend `package.json` files use exact versions instead of `^` ranges, and
  the `game` profile no longer uses `"latest"` for any package.
- Tests assert against `versions.env` instead of hard-coded version strings.

### Removed

- Stale planning artifacts (`.superpowers/`, `docs/superpowers/`) and the
  README section about a hand-written `np` PowerShell alias, which the
  installer's `reposeed` command replaces.

### Removed

- Scaffolders no longer generate `AGENTS.md` in new projects, and the
  `templates/agents/` templates have been removed.

### Changed

- `web` profile on Windows (`new-project.ps1`) now matches the bash scaffolder:
  pinned frontend dependencies, Tailwind CSS, Vitest coverage gates, and a
  required frontend typecheck. Generated web CI runs frontend test, typecheck,
  lint, and build (no Playwright).

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
