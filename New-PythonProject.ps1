[CmdletBinding()]
param(
    [string]$Name = (Split-Path -Leaf (Get-Location)),
    [string]$Python = "3.12",

    [ValidateSet("off", "basic", "standard", "strict")]
    [string]$TypeMode = "standard",

    [switch]$NoGit,
    [switch]$InstallHooks,
    [switch]$NoInstallHooks,
    [switch]$GitHubActions,
    [switch]$NoGitHubActions
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Stop-WithMessage {
    param([Parameter(Mandatory)] [string]$Message)

    Write-Error $Message
    exit 1
}

$ProjectRoot = (Get-Location).ProviderPath

if (-not $ProjectRoot -or -not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
    Stop-WithMessage "Current location is not a valid filesystem directory."
}

$HomeRoot = (Resolve-Path -LiteralPath $HOME).ProviderPath

if ([string]::Equals($ProjectRoot, $HomeRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    Stop-WithMessage "Refusing to scaffold directly in HOME: $HomeRoot. Create and enter a project directory first."
}

[System.IO.Directory]::SetCurrentDirectory($ProjectRoot)

function Resolve-ProjectPath {
    param([Parameter(Mandatory)] [string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    return Join-Path $ProjectRoot $Path
}

function Normalize-Lf {
    param([AllowEmptyString()] [string]$Text)

    if ($null -eq $Text) {
        return ""
    }

    return (($Text -replace "`r`n", "`n") -replace "`r", "`n")
}

function Write-TextFile {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [AllowEmptyString()] [string]$Content
    )

    $fullPath = [System.IO.Path]::GetFullPath((Resolve-ProjectPath $Path))
    $parent = [System.IO.Path]::GetDirectoryName($fullPath)

    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    $normalized = Normalize-Lf $Content

    if (-not $normalized.EndsWith("`n")) {
        $normalized += "`n"
    }

    [System.IO.File]::WriteAllText($fullPath, $normalized, $utf8NoBom)
}

function Add-TextFile {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [AllowEmptyString()] [string]$Content
    )

    $fullPath = [System.IO.Path]::GetFullPath((Resolve-ProjectPath $Path))
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    $append = Normalize-Lf $Content

    while ($append.StartsWith("`n")) {
        $append = $append.Substring(1)
    }

    if (Test-Path $fullPath) {
        $existing = Normalize-Lf ([System.IO.File]::ReadAllText($fullPath))

        if ([string]::IsNullOrWhiteSpace($existing)) {
            $combined = $append
        }
        else {
            $combined = $existing.TrimEnd() + "`n" + $append
        }

        if (-not $combined.EndsWith("`n")) {
            $combined += "`n"
        }

        [System.IO.File]::WriteAllText($fullPath, $combined, $utf8NoBom)
    }
    else {
        Write-TextFile -Path $fullPath -Content $append
    }
}

function Invoke-Checked {
    param(
        [Parameter(Mandatory)] [string]$Command,
        [Parameter(ValueFromRemainingArguments)] [string[]]$Arguments
    )

    & $Command @Arguments

    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    Stop-WithMessage "uv was not found on PATH. Install uv first, then rerun this script."
}

if (Test-Path "pyproject.toml") {
    Stop-WithMessage "pyproject.toml already exists. Run this only in a fresh project directory."
}

$ProjectName = $Name.ToLowerInvariant() -replace "[^a-z0-9]+", "-"
$ProjectName = $ProjectName.Trim("-")

if ([string]::IsNullOrWhiteSpace($ProjectName)) {
    $ProjectName = "python-project"
}

$PackageName = $ProjectName -replace "-", "_"

$RuffTarget = "py312"

if ($Python -match "(\d+)\.(\d+)") {
    $RuffTarget = "py$($Matches[1])$($Matches[2])"
}

Write-Host "Creating Python project: $ProjectName"
Write-Host "Package name: $PackageName"
Write-Host "Python version: $Python"
Write-Host "Type checking mode: $TypeMode"

$initArgs = @(
    "init",
    "--package",
    "--name", $ProjectName,
    "--python", $Python
)

if ($NoGit) {
    $initArgs += @("--vcs", "none")
}

Invoke-Checked uv @initArgs

$devTools = @(
    "ruff",
    "pytest",
    "pytest-cov",
    "pyright",
    "pre-commit"
)

Write-Host "Adding dev tooling..."
Invoke-Checked uv add --dev @devTools

New-Item -ItemType Directory -Path "tests" -Force | Out-Null

Write-TextFile -Path (Join-Path (Join-Path "src" $PackageName) "__init__.py") -Content @"
def project_name() -> str:
    return "$ProjectName"
"@

Write-TextFile -Path (Join-Path "tests" "test_smoke.py") -Content @"
from $PackageName import project_name


def test_project_name() -> None:
    assert project_name() == "$ProjectName"
"@

Add-TextFile -Path "pyproject.toml" -Content @"

[tool.ruff]
line-length = 100
target-version = "$RuffTarget"

[tool.ruff.lint]
select = [
    "E",    # pycodestyle errors
    "F",    # Pyflakes
    "I",    # import sorting
    "B",    # bugbear: likely bugs
    "UP",   # pyupgrade: modern Python syntax
    "SIM",  # simplifications
    "C4",   # cleaner comprehensions
    "PT",   # pytest style
    "RUF"   # Ruff-specific rules
]
ignore = []

[tool.ruff.format]
quote-style = "double"
indent-style = "space"
line-ending = "auto"

[tool.pyright]
include = ["src", "tests"]
exclude = [
    ".venv",
    ".pytest_cache",
    ".ruff_cache",
    "build",
    "dist",
    "**/__pycache__",
    "**/*.egg-info"
]
typeCheckingMode = "$TypeMode"
pythonVersion = "$Python"
reportMissingTypeStubs = false

[tool.pytest.ini_options]
minversion = "8.0"
addopts = "-ra --strict-markers --strict-config --cov --cov-report=term-missing:skip-covered --cov-report=xml"
testpaths = ["tests"]

[tool.coverage.run]
branch = true
source = ["src"]
omit = [
    ".venv/*",
    "tests/*"
]

[tool.coverage.report]
show_missing = true
skip_covered = true
fail_under = 80
exclude_also = [
    "if TYPE_CHECKING:",
    "if __name__ == .__main__.:",
    "raise NotImplementedError"
]
"@

Write-TextFile -Path ".editorconfig" -Content @"
root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true
indent_style = space
indent_size = 4

[*.{yml,yaml,toml,json,md}]
indent_size = 2
"@

Write-TextFile -Path ".gitattributes" -Content @"
* text=auto

# Source/config files: always LF
*.py text eol=lf
*.pyi text eol=lf
*.toml text eol=lf
*.lock text eol=lf
*.yml text eol=lf
*.yaml text eol=lf
*.json text eol=lf
*.md text eol=lf
*.txt text eol=lf
*.ps1 text eol=lf
*.sh text eol=lf
*.sql text eol=lf
*.html text eol=lf
*.css text eol=lf
*.js text eol=lf
*.ts text eol=lf

# Windows command scripts
*.bat text eol=crlf
*.cmd text eol=crlf

# Binary files
*.png binary
*.jpg binary
*.jpeg binary
*.gif binary
*.webp binary
*.ico binary
*.pdf binary
*.zip binary
*.gz binary
*.sqlite binary
*.db binary
"@

Add-TextFile -Path ".gitignore" -Content @"

# Python
__pycache__/
*.py[cod]
*.pyo
*.pyd

# Environments
.venv/
.env
.env.*

# Tool caches
.pytest_cache/
.ruff_cache/
.mypy_cache/
.pyright/
.coverage
coverage.xml
htmlcov/

# Builds
build/
dist/
*.egg-info/

# Editors / OS
.vscode/
.idea/
.DS_Store
Thumbs.db
"@

Write-TextFile -Path ".pre-commit-config.yaml" -Content @'
repos:
  - repo: local
    hooks:
      - id: ruff-format-check
        name: ruff format check
        entry: uv run ruff format --check .
        language: system
        pass_filenames: false
        stages: [pre-commit]

      - id: ruff-check
        name: ruff check
        entry: uv run ruff check .
        language: system
        pass_filenames: false
        stages: [pre-commit]

      - id: pyright
        name: pyright type check
        entry: uv run pyright
        language: system
        pass_filenames: false
        stages: [pre-push]

      - id: pytest
        name: pytest
        entry: uv run pytest
        language: system
        pass_filenames: false
        stages: [pre-push]
'@

New-Item -ItemType Directory -Path "scripts" -Force | Out-Null

Write-TextFile -Path (Join-Path "scripts" "check.ps1") -Content @'
$ErrorActionPreference = "Stop"

function Invoke-Checked {
    param(
        [Parameter(Mandatory)] [string]$Command,
        [Parameter(ValueFromRemainingArguments)] [string[]]$Arguments
    )

    & $Command @Arguments

    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

Invoke-Checked uv run ruff format --check .
Invoke-Checked uv run ruff check .
Invoke-Checked uv run pyright
Invoke-Checked uv run pytest
'@

Write-TextFile -Path (Join-Path "scripts" "fix.ps1") -Content @'
$ErrorActionPreference = "Stop"

function Invoke-Checked {
    param(
        [Parameter(Mandatory)] [string]$Command,
        [Parameter(ValueFromRemainingArguments)] [string[]]$Arguments
    )

    & $Command @Arguments

    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

Invoke-Checked uv run ruff check . --fix
Invoke-Checked uv run ruff format .
Invoke-Checked uv run ruff check .
Invoke-Checked uv run pyright
Invoke-Checked uv run pytest
'@

Write-TextFile -Path "README.md" -Content @"
# $ProjectName

## Setup

Install dependencies:

    uv sync --dev

## Common commands

Source code lives in `src/$PackageName/`. Tests live in `tests/`.
This scaffold enforces an 80 percent coverage floor and is intended for test-first development.

Run everything:

    .\scripts\check.ps1

Auto-fix formatting and safe lint issues, then verify:

    .\scripts\fix.ps1

Run tests:

    uv run pytest

For new features and bug fixes, write or update a focused test first, run that test, then run the full check.

## Docs

Living project documentation lives in docs/.
Start with docs/README.md for the docs convention and docs/project-log.md for the current project memory.

Run type checking:

    uv run pyright

Run linting:

    uv run ruff check .

Run formatting:

    uv run ruff format .

## Cross-platform usage

On Windows:

    .\scripts\check.ps1
    .\scripts\fix.ps1

On macOS/Linux with PowerShell installed:

    pwsh ./scripts/check.ps1
    pwsh ./scripts/fix.ps1
"@

$Today = Get-Date -Format "yyyy-MM-dd"

Write-TextFile -Path (Join-Path "docs" "README.md") -Content @'
# Project Docs

This folder holds living documentation for the project. Keep it aligned with the codebase as the project changes.

Use these docs to capture current behavior, decisions, workflows, dependencies, verification status, and follow-ups that future maintainers or agents should know.

## Files

- `project-log.md`: Reverse chronological project memory and changelog.

When a task changes code, behavior, dependencies, workflow, project structure, or an important decision, update the relevant docs before finishing. If no docs update is needed, say why in the final handoff.
'@

Write-TextFile -Path (Join-Path "docs" "project-log.md") -Content @"
# Project Log

Newest entries first. Keep entries compact and factual.

## $Today - Initial scaffold

- Summary: Created the initial Python project scaffold.
- Changed areas: Project structure, development tooling, tests, agent instructions, and living docs.
- Verification: Scaffold generation completed. Run ``.\scripts\check.ps1`` before the first project commit.
- Follow-ups: Replace this entry's follow-ups as real project work begins.

## Entry template

### YYYY-MM-DD - Short summary

- Summary:
- Changed areas:
- Verification:
- Follow-ups:
"@

$AgentInstructions = @'
# Agent Instructions

This Python project is managed with `uv`. Keep work small, test-first, and evidence-based.

Source code lives in `src/__PACKAGE_NAME__/`. Tests live in `tests/`.

## Rules

- Inspect relevant files before editing. Preserve unrelated user changes and stop if they conflict with the task.
- For behavior changes and bug fixes, write or update a focused test first and watch it fail for the expected reason. Docs, comments, and simple config-only edits may skip the red step.
- Make the smallest practical change. Do not turn starter code into unnecessary architecture.
- Use Context7 and web search as described below when current or external facts matter.
- Verify with the focused test first, then run `.\scripts\check.ps1` when feasible. If a check cannot run, report why.
- Use `uv add` or `uv add --dev` for dependencies. Keep secrets out of the repo.
- Report changed behavior, files touched, verification commands/results, skipped checks, remaining risks, and a suggested commit message in brief Conventional Commit format.

## Ambiguity and Scope

- Resolve ambiguity before editing: inspect local files first, then use Context7 and/or web search when external facts can narrow the answer. Use Context7 first when available for SDKs, dependencies, CI actions, auth, deployment, and security-sensitive behavior.
- If meaningful ambiguity remains, ask targeted beginner-friendly questions with concrete options and tradeoffs. Wait to implement until the user answers or explicitly accepts a default.
- Before edits, restate the bounded scope. For tiny fixes, one terse line is enough; for larger work, include goal, in-scope, out-of-scope, assumptions, and verification.
- Keep tasks tight. Do not expand into adjacent features, broad refactors, new dependencies, or workflow changes unless the user explicitly includes them.

## Living Docs

- Keep `docs/README.md` and `docs/project-log.md` current with actual project changes.
- After changes to code, behavior, dependencies, workflows, structure, or important decisions, update the relevant docs before finishing.
- If no docs update is needed, say so in the final handoff and briefly explain why.

## Commands

    uv sync --dev
    uv run pytest
    uv run pyright
    uv run ruff check .
    .\scripts\check.ps1
'@

Write-TextFile -Path "AGENTS.md" -Content ($AgentInstructions.Replace("__PACKAGE_NAME__", $PackageName))

if (-not $NoGitHubActions) {
    $ciPath = Join-Path (Join-Path ".github" "workflows") "ci.yml"

    Write-TextFile -Path $ciPath -Content @'
name: ci

on:
  push:
  pull_request:

jobs:
  check:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v6

      - name: Install uv
        uses: astral-sh/setup-uv@v8.2.0
        with:
          enable-cache: true

      - name: Install Python
        run: uv python install

      - name: Sync dependencies
        run: uv sync --locked --dev

      - name: Ruff format check
        run: uv run --locked ruff format --check .

      - name: Ruff lint
        run: uv run --locked ruff check .

      - name: Pyright
        run: uv run --locked pyright

      - name: Pytest
        run: uv run --locked pytest
'@
}

if (-not $NoInstallHooks) {
    if (Test-Path ".git") {
        Write-Host "Installing pre-commit and pre-push hooks..."
        Invoke-Checked uv run pre-commit install
        Invoke-Checked uv run pre-commit install --hook-type pre-push
    }
    else {
        Write-Warning "No .git directory found. Skipping hook installation."
    }
}

Write-Host ""
Write-Host "Done."
Write-Host "Project: $ProjectName"
Write-Host ""
Write-Host "Useful commands:"
Write-Host "  .\scripts\check.ps1"
Write-Host "  .\scripts\fix.ps1"
Write-Host "  uv run pytest"
Write-Host "  uv run pyright"
Write-Host "  uv run ruff check ."
Write-Host "  uv run ruff format ."
