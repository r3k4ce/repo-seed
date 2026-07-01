# RepoSeed

[![Platform](https://img.shields.io/badge/Platform-Windows-0078D6?style=flat-square&logo=windows&logoColor=white)](#requirements)
[![Shell](https://img.shields.io/badge/Shell-PowerShell%207%2B-5391FE?style=flat-square&logo=powershell&logoColor=white)](#requirements)
[![License: MIT](https://img.shields.io/badge/License-MIT-green?style=flat-square&logo=opensourceinitiative&logoColor=white)](LICENSE)
[![Type](https://img.shields.io/badge/Type-Scaffolder-lightgrey?style=flat-square&logo=gitignoredotio&logoColor=black)](#why)

> Seed a clean, checked, agent-ready repo from an empty folder.

RepoSeed is a small Windows PowerShell tool that turns an empty folder into
a working project starter. It creates the folder layout, config files,
tests, scripts, and a starting `AGENTS.md`, then sets up git, hooks, and
a GitHub Actions workflow so the first commit is already in a healthy
state.

It is for Windows and PowerShell developers who keep starting the same
kinds of small projects — Python packages, FastAPI backends, PySide6
desktop apps, and small game or toy apps — and want a clean baseline
with checks included every time.

## Why

Most project starts suffer from the same four problems:

- **Repetitive setup** — redoing the same folder layout, `pyproject.toml`,
  and tooling config for every new repo.
- **Inconsistent tooling** — different Python versions, linters, formatters,
  and type-checker settings from one project to the next.
- **Missing tests and CI** — adding tests and a CI workflow "later", which
  often means never.
- **Weak agent instructions** — a thin or missing `AGENTS.md`, so AI coding
  agents have to relearn the project conventions from scratch.

RepoSeed fixes all four by making the boring part a single command.

## Status

Early but usable. I use this for my own project starts.

## Profiles

- **`base`** — uv-managed Python package with a `src/` layout, tests, checks, and CI.
- **`desktop`** — `base` profile plus a PySide6 starter window under `src/<package>/ui/`.
- **`web`** — FastAPI backend with a Vite + React + TypeScript frontend.
- **`game`** — FastAPI backend with a Vite + TypeScript + Phaser frontend and a Playwright smoke test.

See [Usage](#usage) for the full option list.

## What it creates

- **`uv`** for Python packaging and dependency management
- **Ruff** for linting and formatting
- **Pyright** for static type checking (mode configurable via `-TypeMode`)
- **pytest** with coverage (branch coverage, 80% fail-under)
- **PowerShell** `scripts/check.ps1` and `scripts/fix.ps1` to run everything
- **GitHub Actions** workflow at `.github/workflows/ci.yml`
- **Pre-commit and pre-push hooks** via `pre-commit`
- **`AGENTS.md`** with project-specific agent instructions
- **Project memory** at `docs/project-memory.yaml`

## Requirements

RepoSeed targets Windows with PowerShell 7+ and uses these tools:

- **PowerShell 7+** — required to run `new-project.ps1` and the generated `scripts/*.ps1`.
- **`uv`** — required for every profile. Install from https://docs.astral.sh/uv/.
- **`npm`** (Node.js 18+) — required only for the `web` and `game` profiles. Install from https://nodejs.org/.
- **`git`** — used to initialize a repository and install hooks. The script warns and skips `git init` if it is missing; pass `-NoGit` to skip explicitly.
- **Python** — any version `uv` can install; default is `3.12` (override with `-Python`).

## Quick start

The shortest path from an empty folder to a checked, ready-to-commit project:

```powershell
# 1. Create an empty project folder and enter it
New-Item -ItemType Directory -Path "C:\Code\my-app" -Force
Set-Location "C:\Code\my-app"

# 2. Run the scaffolder (use the absolute path to your RepoSeed clone)
& "C:\Path\To\RepoSeed\new-project.ps1"

# 3. Run the generated checks
.\scripts\check.ps1
```

Defaults to the `base` profile. See [Profiles](#profiles) for the available profiles and [Usage](#usage) for options.

## Demo

From an empty folder to a passing check run, in one terminal session.

```console
PS> New-Item -ItemType Directory -Path "C:\Code\demo-app" -Force
PS> Set-Location C:\Code\demo-app
PS> & "C:\Path\To\RepoSeed\new-project.ps1"
Creating Python project: demo-app (demo_app, Python 3.12, pyright standard, profile base)
Initialized project `demo-app`
Done. Next: .\scripts\check.ps1
```

```text
.
|-- AGENTS.md
|-- README.md
|-- pyproject.toml
|-- .editorconfig
|-- .env.example
|-- .gitattributes
|-- .gitignore
|-- .pre-commit-config.yaml
|-- docs/
|   `-- project-memory.yaml
|-- scripts/
|   |-- check.ps1
|   `-- fix.ps1
|-- src/demo_app/
|   `-- __init__.py
`-- tests/
    `-- test_smoke.py
```

```console
PS> .\scripts\check.ps1
ruff format --check .   2 files already formatted
ruff check .            All checks passed!
pyright                 0 errors, 0 warnings, 0 informations
pytest                  1 passed in 0.21s
```

## Usage

Use the script directly from this repository:

```powershell
.\new-project.ps1
.\new-project.ps1 -Name my-app
.\new-project.ps1 -Profile web
```

Options:

* `-Name`: project name. Defaults to the current directory name.
* `-Python`: Python version for `uv init`. Defaults to `3.12`.
* `-TypeMode`: Pyright type checking mode. Valid values are `off`, `basic`, `standard`, and `strict`. Defaults to `standard`.
* `-Profile`: scaffold profile. See [Profiles](#profiles) for the available values. Defaults to `base`.
* `-NoGit`: skip git initialization.
* `-NoInstallHooks`: skip pre-commit and pre-push hook installation.
* `-NoGitHubActions`: skip GitHub Actions workflow generation.

## Optional: PowerShell alias (`np`)

The `np` alias is a convenience for running the scaffolder from any folder without typing the full path. **It is not required** to use RepoSeed — if you only run the script occasionally, the absolute-path call from [Quick start](#quick-start) is enough.

To set up the alias, add a small function to your PowerShell 7 profile. Use the absolute path to this repository on your machine.

```powershell
if (-not (Test-Path -LiteralPath $PROFILE)) {
    New-Item -ItemType File -Path $PROFILE -Force | Out-Null
}

notepad $PROFILE
```

Add this function to the profile:

```powershell
function np {
    & "<absolute-path-to-this-repo>\new-project.ps1" @args
}
```

Reload the profile and verify the command:

```powershell
. $PROFILE
Get-Command np
```

After that, create and enter a fresh project directory, then run `np` from there.
The script refuses to scaffold directly in your home directory.

Or use the `np` profile function from any directory:

```powershell
np
np -Name my-app
np -Profile web
np -Profile game -Python 3.13 -TypeMode strict
np -NoGit -NoInstallHooks -NoGitHubActions
```

## Profile structures

### `base`

```text
.
|-- src/<package>/
|-- tests/
|-- scripts/
|   |-- check.ps1
|   `-- fix.ps1
|-- docs/project-memory.yaml
|-- pyproject.toml
`-- AGENTS.md
```

Entrypoint: Python package in `src/<package>/`. Check with `.\scripts\check.ps1`.

### `desktop`

```text
.
|-- src/<package>/
|   |-- __main__.py
|   |-- ui/
|   |-- models/
|   `-- services/
|-- tests/
|-- scripts/
|-- docs/project-memory.yaml
|-- pyproject.toml
`-- AGENTS.md
```

Entrypoint: `uv run python -m <package>`. UI starts in `src/<package>/ui/`.

### `web`

```text
.
|-- backend/
|   |-- src/<package>_backend/
|   |-- tests/
|   `-- pyproject.toml
|-- frontend/
|   |-- src/
|   |-- package.json
|   `-- vite.config.ts
|-- scripts/
|-- docs/project-memory.yaml
`-- AGENTS.md
```

Entrypoints: FastAPI app in `backend/src/<package>_backend/main.py`; React app in `frontend/src/`.

### `game`

```text
.
|-- backend/
|   |-- src/<package>_backend/
|   |-- tests/
|   `-- pyproject.toml
|-- frontend/
|   |-- src/
|   |   `-- game/
|   |-- tests/
|   |-- package.json
|   |-- playwright.config.ts
|   `-- vite.config.ts
|-- scripts/
|-- docs/project-memory.yaml
`-- AGENTS.md
```

Entrypoints: FastAPI app in `backend/src/<package>_backend/main.py`; Phaser scene code in `frontend/src/game/`.

## Non-goals

RepoSeed seeds a clean baseline. It does not try to be a full app generator.

RepoSeed does not generate:

- authentication or user management
- databases or data-access layers
- Dockerfiles or container configuration
- cloud infrastructure or deployment configs
- dashboards, admin UIs, or analytics
- production-grade architecture (load balancers, queues, observability, etc.)

What you build on top of the scaffold is yours.
