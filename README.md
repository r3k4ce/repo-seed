# new-project

`new-project.ps1` scaffolds local project starters in the current directory.

```powershell
.\new-project.ps1 -Profile base
.\new-project.ps1 -Profile desktop
.\new-project.ps1 -Profile web
.\new-project.ps1 -Profile game
```

## PowerShell 7 profile setup

To run the script from anywhere as `np`, add a small function to your PowerShell 7 profile.
Use the absolute path to this repository on your machine.

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

## Usage

Use the script directly from this repository:

```powershell
.\new-project.ps1
.\new-project.ps1 -Name my-app
.\new-project.ps1 -Profile web
```

Or use the `np` profile function from any directory:

```powershell
np
np -Name my-app
np -Profile web
np -Profile game -Python 3.13 -TypeMode strict
np -NoGit -NoInstallHooks -NoGitHubActions
```

Options:

* `-Name`: project name. Defaults to the current directory name.
* `-Python`: Python version for `uv init`. Defaults to `3.12`.
* `-TypeMode`: Pyright type checking mode. Valid values are `off`, `basic`, `standard`, and `strict`. Defaults to `standard`.
* `-Profile`: scaffold profile. Valid values are `base`, `desktop`, `web`, and `game`. Defaults to `base`.
* `-NoGit`: skip git initialization.
* `-NoInstallHooks`: skip pre-commit and pre-push hook installation.
* `-NoGitHubActions`: skip GitHub Actions workflow generation.

Profiles:

* `base`: uv-managed Python package.
* `desktop`: base profile plus PySide6 starter folders and a runnable window.
* `web`: FastAPI backend plus Vite React TypeScript frontend.
* `game`: FastAPI backend plus Vite TypeScript frontend with Phaser.

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
