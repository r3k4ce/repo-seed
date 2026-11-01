# RepoSeed

[![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20Windows-lightgrey?style=flat-square)](#requirements)
[![Python](https://img.shields.io/badge/Python-3.10%2B-lightgrey?style=flat-square)](#requirements)
[![License: MIT](https://img.shields.io/badge/License-MIT-green?style=flat-square&logo=opensourceinitiative&logoColor=white)](LICENSE)
[![Type](https://img.shields.io/badge/Type-Scaffolder-lightgrey?style=flat-square&logo=gitignoredotio&logoColor=black)](#why)

> Seed a clean, checked, agent-ready repo from an empty folder.

RepoSeed is a small Python command-line tool that turns an empty folder
into a working project starter. It creates the folder layout, config files,
tests, and scripts, then sets up git, hooks, and a GitHub Actions workflow
so the first commit is already in a healthy state.

It is for developers who keep starting the same kinds of small projects —
Python packages, PySide6 desktop apps, FastAPI backends, and small game or
toy apps — and want a clean baseline with checks included every time.

## Why

Most project starts suffer from the same three problems:

- **Repetitive setup** — redoing the same folder layout, `pyproject.toml`,
  and tooling config for every new repo.
- **Inconsistent tooling** — different Python versions, linters, formatters,
  and type-checker settings from one project to the next.
- **Missing tests and CI** — adding tests and a CI workflow "later", which
  often means never.

RepoSeed fixes all three by making the boring part a single command.

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
- **Pyright** for static type checking (mode configurable via `--type-mode`)
- **pytest** with coverage (branch coverage, 80% fail-under)
- **Cross-platform check/fix scripts** (`uv run scripts/check.py`, `uv run scripts/fix.py`) that work the same on Linux and Windows
- **GitHub Actions** workflow at `.github/workflows/ci.yml`
- **Pre-commit and pre-push hooks** via `pre-commit`
- **Exact, tested dependency versions** from [`versions.env`](src/reposeed/versions.env), so every
  run produces the same project (see [Version policy](docs/versioning.md))

## Requirements

RepoSeed officially targets Linux and Windows. macOS is not an official target yet.

- **`uv`** — the only requirement to install and run RepoSeed, and required for
  every profile. Install from https://docs.astral.sh/uv/. RepoSeed needs
  Python 3.10+, which `uv` provides; it has no other dependencies.
- **Node.js with `npm`** — required only for the `web` and `game` profiles. Install from https://nodejs.org/.
- **`git`** — optional; used to initialize a repository and install hooks. RepoSeed warns and skips `git init` if it is missing; pass `--no-git` to skip explicitly.
- **Python for the generated project** — any version `uv` can install; default is `3.12` (override with `--python`).

Generated projects need no particular shell: their `scripts/check.py` and
`scripts/fix.py` run with `uv` on both platforms.

The minimum `uv` and Node.js versions live in [`versions.env`](src/reposeed/versions.env)
(`UV_MIN`, `NODE_MIN`). RepoSeed checks them before writing anything and
stops with a clear message if a tool is too old.

## Quick start

The shortest path from an empty folder to a checked, ready-to-commit project.
The commands are the same on Linux and Windows:

```bash
# 1. Install the reposeed command from GitHub
uv tool install git+https://github.com/r3k4ce/repo-seed

# 2. Create an empty project folder and enter it
mkdir my-app
cd my-app

# 3. Run the scaffolder
reposeed

# 4. Run the generated checks
uv run scripts/check.py
```

Defaults to the `base` profile. See [Profiles](#profiles) for the available profiles and [Usage](#usage) for options.

## Demo

From an empty folder to a passing check run, in one terminal session.

```console
$ mkdir -p ~/Code/demo-app
$ cd ~/Code/demo-app
$ reposeed
Creating Python project: demo-app (demo_app, Python 3.12, pyright standard, profile base)
Initialized project `demo-app`
Done. Next: uv run scripts/check.py
```

```text
.
|-- README.md
|-- pyproject.toml
|-- .editorconfig
|-- .env.example
|-- .gitattributes
|-- .gitignore
|-- .pre-commit-config.yaml
|-- scripts/
|   |-- check.py
|   `-- fix.py
|-- src/demo_app/
|   `-- __init__.py
`-- tests/
    `-- test_smoke.py
```

```console
$ uv run scripts/check.py
> uv run ruff format --check .
5 files already formatted
> uv run ruff check .
All checks passed!
> uv run pyright
0 errors, 0 warnings, 0 informations
> uv run pytest
...
1 passed in 0.05s
```

## Usage

### Install

Install the `reposeed` command with `uv`, either from GitHub or from a local
checkout of this repository:

```bash
uv tool install git+https://github.com/r3k4ce/repo-seed
# or, from a checkout; the command then follows the checked-out branch
uv tool install --editable /path/to/repo-seed
```

`uv` puts the command in its executable directory (`~/.local/bin` by default,
on Windows too). If `reposeed` is not found afterwards, put that directory on
your `PATH` and open a new terminal:

```bash
uv tool update-shell
```

To update, run `uv tool upgrade reposeed` (a GitHub install) or `git pull` in
the checkout (an editable install). To remove it, run `uv tool uninstall reposeed`.

**Upgrading from the old installer:** earlier versions were installed with
`install.sh` or `install.ps1`, which no longer exist. Before running
`uv tool install`, delete what they installed. On Linux, delete
`~/.local/bin/reposeed` (uv does not overwrite a command it did not install)
and `~/.local/share/reposeed`. On Windows, delete
`%LOCALAPPDATA%\Microsoft\WindowsApps\reposeed.ps1` and `%LOCALAPPDATA%\RepoSeed`.

### Run

Run `reposeed` from the empty project folder:

```bash
reposeed
reposeed --name my-app
reposeed --profile desktop
reposeed --profile web
reposeed --profile game --python 3.13 --type-mode strict
reposeed --no-git --no-install-hooks --no-github-actions
```

Options (the same on every OS):

* `--name`: project name. Defaults to the current directory name.
* `--python`: Python version for `uv init`. Defaults to `3.12`.
* `--type-mode`: Pyright type checking mode. Valid values are `off`, `basic`, `standard`, and `strict`. Defaults to `standard`.
* `--profile`: scaffold profile: `base`, `desktop`, `web`, or `game`. Defaults to `base`.
* `--no-git`: skip git initialization.
* `--no-install-hooks`: skip pre-commit and pre-push hook installation.
* `--no-github-actions`: skip GitHub Actions workflow generation.
* `--version`: print the RepoSeed version.

`reposeed --help` lists them. PowerShell-style options such as `-Profile` are
not accepted.

## Profile structures

### `base`

```text
.
|-- src/<package>/
|-- tests/
|-- scripts/
|   |-- check.py
|   `-- fix.py
`-- pyproject.toml
```

Entrypoint: Python package in `src/<package>/`. Check with `uv run scripts/check.py`, the same command on every platform and profile.

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
`-- pyproject.toml
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
`-- scripts/
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
`-- scripts/
```

Entrypoints: FastAPI app in `backend/src/<package>_backend/main.py`; Phaser scene code in `frontend/src/game/`.

## Keeping it reliable

The point of RepoSeed is that it works the same way every time you start a
project. Three things make that hold:

- **One version manifest.** Every package RepoSeed installs is pinned to
  an exact version in [`versions.env`](src/reposeed/versions.env), so a bump
  happens in one place.
- **Tests that scaffold real projects.** `tests/test_e2e.py` creates every
  profile with real `uv` and `npm` installs and runs the generated checks. A
  pinned set is only accepted after it passes.
- **Weekly CI.** [`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs the
  tests on Linux and Windows on pushes to `main` and `dev`, on pull requests and
  on a weekly schedule, so upstream drift is caught before it costs you a
  project start.

To upgrade the pinned versions, edit `src/reposeed/versions.env`, regenerate the
test snapshots, run the tests, and commit.
The full procedure is in [docs/versioning.md](docs/versioning.md).

Run the tests locally from a checkout:

```bash
uv run pytest                                # unit, snapshot and wheel tests
REPOSEED_E2E_GAME=1 uv run pytest -m e2e     # real scaffolds of every profile
uv run ruff check . && uv run ruff format --check . && uv run pyright
```

`new-project.ps1` remains in the repository only temporarily, as a reference
that CI compares the `desktop` profile against. It is not an entry point; use
`reposeed`.

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
