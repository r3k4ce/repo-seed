[CmdletBinding()]
param(
    [string]$Name = (Split-Path -Leaf (Get-Location)),
    [string]$Python = "3.12",

    [ValidateSet("off", "basic", "standard", "strict")]
    [string]$TypeMode = "standard",

    [ValidateSet("base", "desktop", "web", "game")]
    [string]$Profile = "base",

    [switch]$NoGit,
    [switch]$NoInstallHooks,
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

function Read-Template {
    param([Parameter(Mandatory)] [string]$Name)

    $path = Join-Path (Join-Path $PSScriptRoot "templates") $Name
    return Get-Content -Raw -LiteralPath $path
}

function Expand-Template {
    param([Parameter(Mandatory)] [string]$Text)

    return $Text.Replace("__PROJECT_NAME__", $ProjectName).
        Replace("__PACKAGE_NAME__", $PackageName).
        Replace("__PYTHON_VERSION__", $Python).
        Replace("__GENERATOR_NAME__", "new-project.ps1").
        Replace("__PRIMARY_SHELL__", "PowerShell").
        Replace("__COMMAND_FENCE__", "powershell").
        Replace("__SETUP_COMMAND__", "uv sync --dev").
        Replace("__CHECK_COMMAND__", ".\scripts\check.ps1").
        Replace("__FIX_COMMAND__", ".\scripts\fix.ps1")
}

function Write-TemplateFile {
    param(
        [Parameter(Mandatory)] [string]$TemplateName,
        [Parameter(Mandatory)] [string]$Path
    )

    Write-TextFile -Path $Path -Content (Expand-Template (Read-Template $TemplateName))
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

# Pinned versions live in versions.env next to this script. Both scaffolders
# read the same file, so a version is only ever changed in one place.
function Read-Versions {
    $path = Join-Path $PSScriptRoot "versions.env"

    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Stop-WithMessage "Missing versions.env next to new-project.ps1."
    }

    $versions = @{}
    foreach ($rawLine in [System.IO.File]::ReadAllLines($path)) {
        $line = ($rawLine -split "#", 2)[0] -replace "\s", ""
        if ($line.Length -eq 0) {
            continue
        }
        if ($line -notmatch "^([A-Z][A-Z0-9_]*)=([A-Za-z0-9.+-]+)$") {
            Stop-WithMessage "Invalid line in versions.env: $line"
        }
        $versions[$Matches[1]] = $Matches[2]
    }

    return $versions
}

function Get-Pinned {
    param([Parameter(Mandatory)] [string]$Key)

    if (-not $Versions.ContainsKey($Key)) {
        Stop-WithMessage "versions.env is missing $Key."
    }

    return $Versions[$Key]
}

function Get-VersionNumber {
    param([AllowEmptyString()] [string]$Text)

    if ($Text -match "(\d+)\.(\d+)(?:\.(\d+))?") {
        $patch = if ($Matches[3]) { [int]$Matches[3] } else { 0 }
        return [version]::new([int]$Matches[1], [int]$Matches[2], $patch)
    }

    return $null
}

function Get-NpmCommand {
    if (Get-Command npm.cmd -ErrorAction SilentlyContinue) {
        return "npm.cmd"
    }

    if (Get-Command npm -ErrorAction SilentlyContinue) {
        return "npm"
    }

    Stop-WithMessage "npm was not found on PATH. Install Node.js first, then rerun this script."
}

function Test-UvVersion {
    if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
        Stop-WithMessage "uv was not found on PATH. Install uv first, then rerun this script."
    }

    $minimum = [version](Get-Pinned "UV_MIN")
    $actual = Get-VersionNumber ((& uv --version 2>$null) -join " ")

    if ($null -eq $actual) {
        Stop-WithMessage "Could not read the uv version from 'uv --version'."
    }

    if ($actual -lt $minimum) {
        Stop-WithMessage "uv $actual is too old. RepoSeed needs uv $minimum or newer. Run 'uv self update' and retry."
    }
}

function Test-NodeVersion {
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        Stop-WithMessage "node was not found on PATH. Install Node.js first, then rerun this script."
    }

    $minimum = [version](Get-Pinned "NODE_MIN")
    $actual = Get-VersionNumber ((& node --version 2>$null) -join " ")

    if ($null -eq $actual) {
        Stop-WithMessage "Could not read the Node.js version from 'node --version'."
    }

    if ($actual -lt $minimum) {
        Stop-WithMessage "Node.js $actual is too old. RepoSeed needs Node.js $minimum or newer for the $Profile profile."
    }
}

$Versions = Read-Versions
Test-UvVersion

# Exact pins shared by every profile. The web/game profiles add FastAPI on top.
$DevToolPins = @(
    "ruff==$(Get-Pinned 'PY_RUFF')",
    "pytest==$(Get-Pinned 'PY_PYTEST')",
    "pytest-cov==$(Get-Pinned 'PY_PYTEST_COV')",
    "pyright==$(Get-Pinned 'PY_PYRIGHT')",
    "pre-commit==$(Get-Pinned 'PY_PRE_COMMIT')"
)
$RuntimePins = @(
    "python-dotenv==$(Get-Pinned 'PY_PYTHON_DOTENV')"
)

if ($Profile -in @("web", "game")) {
    foreach ($existingPath in @("backend", "frontend", "package.json", "pyproject.toml")) {
        if (Test-Path -LiteralPath $existingPath) {
            Stop-WithMessage "$existingPath already exists. Run this only in a fresh project directory."
        }
    }
}
elseif (Test-Path "pyproject.toml") {
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

if ($Profile -in @("web", "game")) {
    $BackendProjectName = "$ProjectName-backend"
    $BackendPackageName = "${PackageName}_backend"
    Test-NodeVersion
    $NpmCommand = Get-NpmCommand
    $WebTemplatePrefix = if ($Profile -eq "game") { "game" } else { "web" }
    $FrontendDescription = if ($Profile -eq "game") { "Phaser game frontend" } else { "React TypeScript frontend" }
    $MemorySummary = if ($Profile -eq "game") { "Created initial game scaffold." } else { "Created initial web app scaffold." }
    $MemoryChanged = if ($Profile -eq "game") { "Initial FastAPI backend, Phaser frontend, checks, CI, hooks, and memory file." } else { "Initial FastAPI backend, React TypeScript frontend, checks, CI, hooks, and memory file." }
    $BackendTestTemplate = if ($Profile -eq "game") { "game/test_game_api.py" } else { "web/test_health.py" }
    $BackendTestPath = if ($Profile -eq "game") { "test_game_api.py" } else { "test_health.py" }

    Write-Host "Creating $Profile project: $ProjectName (FastAPI backend, $FrontendDescription)"

    if (-not $NoGit) {
        if (Get-Command git -ErrorAction SilentlyContinue) {
            Invoke-Checked git init
        }
        else {
            Write-Warning "git was not found on PATH. Skipping git init."
        }
    }

    Invoke-Checked uv init --package --name $BackendProjectName --python $Python --vcs none backend

    Push-Location "backend"
    try {
        Invoke-Checked uv add @RuntimePins "fastapi==$(Get-Pinned 'PY_FASTAPI')" "uvicorn==$(Get-Pinned 'PY_UVICORN')"
        Invoke-Checked uv add --dev @DevToolPins
    }
    finally {
        Pop-Location
    }

    Write-TextFile -Path (Join-Path (Join-Path "backend/src" $BackendPackageName) "__init__.py") -Content @"
def project_name() -> str:
    return "$ProjectName"
"@

    Write-TemplateFile -TemplateName "$WebTemplatePrefix/backend_main.py" -Path (Join-Path (Join-Path "backend/src" $BackendPackageName) "main.py")
    Write-TemplateFile -TemplateName $BackendTestTemplate -Path (Join-Path "backend/tests" $BackendTestPath)

    Add-TextFile -Path (Join-Path "backend" "pyproject.toml") -Content @"

[tool.ruff]
line-length = 100
target-version = "$RuffTarget"

[tool.ruff.lint]
select = ["E", "F", "I", "B", "UP", "SIM", "C4", "PT", "RUF"]
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
venvPath = "."
venv = ".venv"

[tool.pytest.ini_options]
minversion = "8.0"
addopts = "-ra --strict-markers --strict-config --cov --cov-report=term-missing:skip-covered --cov-report=xml"
testpaths = ["tests"]

[tool.coverage.run]
branch = true
source = ["src"]
omit = [".venv/*", "tests/*"]

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

    New-Item -ItemType Directory -Path "frontend/src" -Force | Out-Null

    if ($Profile -eq "game") {
        Write-TextFile -Path (Join-Path "frontend" "package.json") -Content @"
{
  "name": "$ProjectName-frontend",
  "private": true,
  "version": "0.1.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "tsc -b && vite build",
    "lint": "eslint .",
    "typecheck": "tsc --noEmit",
    "test:e2e": "playwright test",
    "preview": "vite preview"
  },
  "engines": {
    "node": ">=$(Get-Pinned 'NODE_MIN')"
  },
  "dependencies": {
    "phaser": "$(Get-Pinned 'NPM_PHASER')"
  },
  "devDependencies": {
    "@eslint/js": "$(Get-Pinned 'NPM_ESLINT_JS')",
    "@playwright/test": "$(Get-Pinned 'NPM_PLAYWRIGHT_TEST')",
    "eslint": "$(Get-Pinned 'NPM_ESLINT')",
    "globals": "$(Get-Pinned 'NPM_GLOBALS')",
    "typescript": "$(Get-Pinned 'NPM_TYPESCRIPT')",
    "typescript-eslint": "$(Get-Pinned 'NPM_TYPESCRIPT_ESLINT')",
    "vite": "$(Get-Pinned 'NPM_VITE')"
  }
}
"@
    }
    else {
        Write-TextFile -Path (Join-Path "frontend" "package.json") -Content @"
{
  "name": "$ProjectName-frontend",
  "private": true,
  "version": "0.1.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "tsc -b && vite build",
    "lint": "eslint .",
    "typecheck": "tsc --noEmit",
    "test": "vitest run --coverage",
    "test:watch": "vitest",
    "preview": "vite preview"
  },
  "engines": {
    "node": ">=$(Get-Pinned 'NODE_MIN')"
  },
  "dependencies": {
    "react": "$(Get-Pinned 'NPM_REACT')",
    "react-dom": "$(Get-Pinned 'NPM_REACT_DOM')"
  },
  "devDependencies": {
    "@eslint/js": "$(Get-Pinned 'NPM_ESLINT_JS')",
    "@tailwindcss/vite": "$(Get-Pinned 'NPM_TAILWINDCSS_VITE')",
    "@testing-library/jest-dom": "$(Get-Pinned 'NPM_TESTING_LIBRARY_JEST_DOM')",
    "@testing-library/react": "$(Get-Pinned 'NPM_TESTING_LIBRARY_REACT')",
    "@types/react": "$(Get-Pinned 'NPM_TYPES_REACT')",
    "@types/react-dom": "$(Get-Pinned 'NPM_TYPES_REACT_DOM')",
    "@vitejs/plugin-react": "$(Get-Pinned 'NPM_VITEJS_PLUGIN_REACT')",
    "@vitest/coverage-v8": "$(Get-Pinned 'NPM_VITEST_COVERAGE_V8')",
    "eslint": "$(Get-Pinned 'NPM_ESLINT')",
    "eslint-plugin-react-hooks": "$(Get-Pinned 'NPM_ESLINT_PLUGIN_REACT_HOOKS')",
    "eslint-plugin-react-refresh": "$(Get-Pinned 'NPM_ESLINT_PLUGIN_REACT_REFRESH')",
    "globals": "$(Get-Pinned 'NPM_GLOBALS')",
    "jsdom": "$(Get-Pinned 'NPM_JSDOM')",
    "tailwindcss": "$(Get-Pinned 'NPM_TAILWINDCSS')",
    "typescript": "$(Get-Pinned 'NPM_TYPESCRIPT')",
    "typescript-eslint": "$(Get-Pinned 'NPM_TYPESCRIPT_ESLINT')",
    "vite": "$(Get-Pinned 'NPM_VITE')",
    "vitest": "$(Get-Pinned 'NPM_VITEST')"
  }
}
"@
    }

    # save-exact keeps future "npm install <pkg>" calls pinned too; engine-strict
    # turns the engines field above into a hard check instead of a warning.
    Write-TextFile -Path (Join-Path "frontend" ".npmrc") -Content @'
save-exact=true
engine-strict=true
'@

    $FrontendEntry = if ($Profile -eq "game") { "/src/main.ts" } else { "/src/main.tsx" }

    Write-TextFile -Path (Join-Path "frontend" "index.html") -Content @"
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>$ProjectName</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="$FrontendEntry"></script>
  </body>
</html>
"@

    Write-TextFile -Path (Join-Path "frontend" "tsconfig.json") -Content @'
{
  "files": [],
  "references": [
    { "path": "./tsconfig.app.json" },
    { "path": "./tsconfig.node.json" }
  ]
}
'@

    if ($Profile -eq "game") {
        Write-TextFile -Path (Join-Path "frontend" "tsconfig.app.json") -Content @'
{
  "compilerOptions": {
    "tsBuildInfoFile": "./node_modules/.tmp/tsconfig.app.tsbuildinfo",
    "target": "ES2022",
    "useDefineForClassFields": true,
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "allowImportingTsExtensions": true,
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "noEmit": true,
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true,
    "skipLibCheck": true
  },
  "include": ["src"]
}
'@
    }
    else {
        Write-TextFile -Path (Join-Path "frontend" "tsconfig.app.json") -Content @'
{
  "compilerOptions": {
    "tsBuildInfoFile": "./node_modules/.tmp/tsconfig.app.tsbuildinfo",
    "target": "ES2022",
    "useDefineForClassFields": true,
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "allowImportingTsExtensions": true,
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "noEmit": true,
    "jsx": "react-jsx",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true,
    "skipLibCheck": true
  },
  "include": ["src"]
}
'@
    }

    Write-TextFile -Path (Join-Path "frontend" "tsconfig.node.json") -Content @'
{
  "compilerOptions": {
    "tsBuildInfoFile": "./node_modules/.tmp/tsconfig.node.tsbuildinfo",
    "target": "ES2023",
    "lib": ["ES2023"],
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "allowImportingTsExtensions": true,
    "noEmit": true,
    "strict": true,
    "skipLibCheck": true
  },
  "include": ["vite.config.ts", "eslint.config.js"]
}
'@

    if ($Profile -eq "game") {
        Write-TextFile -Path (Join-Path "frontend" "vite.config.ts") -Content @'
import { defineConfig } from "vite";

export default defineConfig({
  build: {
    chunkSizeWarningLimit: 2000,
  },
  server: {
    proxy: {
      "/api": "http://127.0.0.1:8000",
    },
  },
});
'@
    }
    else {
        Write-TextFile -Path (Join-Path "frontend" "vite.config.ts") -Content @'
import { defineConfig } from "vitest/config";
import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react(), tailwindcss()],
  build: {
    chunkSizeWarningLimit: 2000,
  },
  server: {
    proxy: {
      "/api": "http://127.0.0.1:8000",
    },
  },
  test: {
    environment: "jsdom",
    setupFiles: "./src/test/setup.ts",
    coverage: {
      provider: "v8",
      reporter: ["text", "json", "html"],
      thresholds: {
        statements: 80,
        branches: 80,
        functions: 80,
        lines: 80,
      },
      exclude: [
        "src/main.tsx",
        "src/vite-env.d.ts",
        "src/test/**",
        "**/*.test.{ts,tsx}",
      ],
    },
  },
});
'@
    }

    if ($Profile -eq "game") {
        Write-TextFile -Path (Join-Path "frontend" "eslint.config.js") -Content @'
import js from "@eslint/js";
import globals from "globals";
import tseslint from "typescript-eslint";

export default tseslint.config(
  { ignores: ["dist"] },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    files: ["**/*.ts"],
    languageOptions: {
      ecmaVersion: 2022,
      globals: globals.browser,
    },
  },
);
'@
    }
    else {
        Write-TextFile -Path (Join-Path "frontend" "eslint.config.js") -Content @'
import js from "@eslint/js";
import globals from "globals";
import reactHooks from "eslint-plugin-react-hooks";
import reactRefresh from "eslint-plugin-react-refresh";
import tseslint from "typescript-eslint";

export default tseslint.config(
  { ignores: ["dist"] },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    files: ["**/*.{ts,tsx}"],
    languageOptions: {
      ecmaVersion: 2022,
      globals: globals.browser,
    },
    plugins: {
      "react-hooks": reactHooks,
      "react-refresh": reactRefresh,
    },
    rules: {
      ...reactHooks.configs.recommended.rules,
      "react-refresh/only-export-components": ["warn", { allowConstantExport: true }],
    },
  },
);
'@
    }

    if ($Profile -eq "game") {
        Write-TemplateFile -TemplateName "game/frontend_main.ts" -Path (Join-Path "frontend/src" "main.ts")
    }
    else {
        Write-TemplateFile -TemplateName "web/frontend_main.tsx" -Path (Join-Path "frontend/src" "main.tsx")
        Write-TemplateFile -TemplateName "web/App.tsx" -Path (Join-Path "frontend/src" "App.tsx")
        Write-TemplateFile -TemplateName "web/App.test.tsx" -Path (Join-Path "frontend/src" "App.test.tsx")
        Write-TemplateFile -TemplateName "web/test_setup.ts" -Path (Join-Path "frontend/src/test" "setup.ts")
    }

    Write-TextFile -Path (Join-Path "frontend/src" "vite-env.d.ts") -Content @'
/// <reference types="vite/client" />
'@

    Write-TemplateFile -TemplateName "$WebTemplatePrefix/style.css" -Path (Join-Path "frontend/src" "style.css")

    if ($Profile -eq "game") {
        New-Item -ItemType Directory -Path "frontend/src/game" -Force | Out-Null
        Write-TemplateFile -TemplateName "game/scene.ts" -Path (Join-Path "frontend/src/game" "GameScene.ts")
        Write-TemplateFile -TemplateName "game/playwright.config.ts" -Path (Join-Path "frontend" "playwright.config.ts")
        Write-TemplateFile -TemplateName "game/game-smoke.spec.ts" -Path (Join-Path "frontend/tests" "game-smoke.spec.ts")
    }

    Push-Location "frontend"
    try {
        Invoke-Checked $NpmCommand install

        if ($Profile -eq "game") {
            Invoke-Checked $NpmCommand exec playwright install chromium
        }
    }
    finally {
        Pop-Location
    }

    Write-TextFile -Path ".editorconfig" -Content @"
root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true
indent_style = space
indent_size = 2

[*.py]
indent_size = 4
"@

    Write-TextFile -Path ".gitattributes" -Content @"
* text=auto

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
*.html text eol=lf
*.css text eol=lf
*.js text eol=lf
*.jsx text eol=lf
*.ts text eol=lf
*.tsx text eol=lf

*.bat text eol=crlf
*.cmd text eol=crlf

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
!.env.example

# Frontend
node_modules/
dist/

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
*.egg-info/

# Editors / OS
.vscode/
.idea/
.DS_Store
Thumbs.db
"@

    Write-TextFile -Path ".env.example" -Content @"
# Add required environment variable names here. Never commit real secrets.
"@

    New-Item -ItemType Directory -Path "scripts" -Force | Out-Null

    if ($Profile -eq "game") {
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

$Npm = if (Get-Command npm.cmd -ErrorAction SilentlyContinue) { "npm.cmd" } else { "npm" }

Push-Location backend
try {
    Invoke-Checked uv run ruff format --check .
    Invoke-Checked uv run ruff check .
    Invoke-Checked uv run pyright
    Invoke-Checked uv run pytest
}
finally {
    Pop-Location
}

Push-Location frontend
try {
    Invoke-Checked $Npm run test --if-present
    Invoke-Checked $Npm run test:e2e --if-present
    Invoke-Checked $Npm run lint
    Invoke-Checked $Npm run build
}
finally {
    Pop-Location
}
'@
    }
    else {
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

$Npm = if (Get-Command npm.cmd -ErrorAction SilentlyContinue) { "npm.cmd" } else { "npm" }

Push-Location backend
try {
    Invoke-Checked uv run ruff format --check .
    Invoke-Checked uv run ruff check .
    Invoke-Checked uv run pyright
    Invoke-Checked uv run pytest
}
finally {
    Pop-Location
}

Push-Location frontend
try {
    Invoke-Checked $Npm run test
    Invoke-Checked $Npm run typecheck
    Invoke-Checked $Npm run lint
    Invoke-Checked $Npm run build
}
finally {
    Pop-Location
}
'@
    }

    if ($Profile -eq "game") {
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

$Npm = if (Get-Command npm.cmd -ErrorAction SilentlyContinue) { "npm.cmd" } else { "npm" }

Push-Location backend
try {
    Invoke-Checked uv run ruff check . --fix
    Invoke-Checked uv run ruff format .
    Invoke-Checked uv run ruff check .
    Invoke-Checked uv run pyright
    Invoke-Checked uv run pytest
}
finally {
    Pop-Location
}

Push-Location frontend
try {
    Invoke-Checked $Npm run test --if-present
    Invoke-Checked $Npm run test:e2e --if-present
    Invoke-Checked $Npm run lint
    Invoke-Checked $Npm run build
}
finally {
    Pop-Location
}
'@
    }
    else {
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

$Npm = if (Get-Command npm.cmd -ErrorAction SilentlyContinue) { "npm.cmd" } else { "npm" }

Push-Location backend
try {
    Invoke-Checked uv run ruff check . --fix
    Invoke-Checked uv run ruff format .
    Invoke-Checked uv run ruff check .
    Invoke-Checked uv run pyright
    Invoke-Checked uv run pytest
}
finally {
    Pop-Location
}

Push-Location frontend
try {
    Invoke-Checked $Npm run test
    Invoke-Checked $Npm run typecheck
    Invoke-Checked $Npm run lint
    Invoke-Checked $Npm run build
}
finally {
    Pop-Location
}
'@
    }

    $FrontendSetupExtra = if ($Profile -eq "game") { "    Push-Location frontend; npm exec playwright install chromium; Pop-Location`n" } else { "" }

    Write-TextFile -Path "README.md" -Content @"
# $ProjectName

## Setup

    Push-Location backend; uv sync --dev; Pop-Location
    Push-Location frontend; npm install; Pop-Location
$FrontendSetupExtra
Copy .env.example to .env only when real secrets are needed. Never commit .env.

Dependencies are pinned to exact versions. To upgrade one, change its version
in backend/pyproject.toml (then run uv lock) or frontend/package.json (then run
npm install), and run the checks.

## Commands

Backend source lives in backend/src/$BackendPackageName/. Frontend source lives in frontend/src/.

    .\scripts\check.ps1
    .\scripts\fix.ps1
    Push-Location backend; uv run uvicorn $BackendPackageName.main:app --reload; Pop-Location
    Push-Location frontend; npm run dev; Pop-Location

## Docs

Project memory lives in docs/project-memory.yaml.
"@

    $Now = Get-Date
    $TimeUtc = $Now.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $TimeLocal = $Now.ToString("yyyy-MM-ddTHH:mm:sszzz")

    Write-TextFile -Path (Join-Path "docs" "project-memory.yaml") -Content @"
entries:
  - time_utc: "$TimeUtc"
    time_local: "$TimeLocal"
    summary: "$MemorySummary"
    changed:
      - "$MemoryChanged"
    verification:
      - 'Not run yet; run .\scripts\check.ps1 before first commit.'
"@

    Write-TextFile -Path ".pre-commit-config.yaml" -Content @'
repos:
  - repo: local
    hooks:
      - id: project-check
        name: project check
        entry: powershell -ExecutionPolicy Bypass -File scripts/check.ps1
        language: system
        pass_filenames: false
        stages: [pre-push]
'@

    if (-not $NoGitHubActions) {
        $ciPath = Join-Path (Join-Path ".github" "workflows") "ci.yml"

        if ($Profile -eq "game") {
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

      - name: Install backend dependencies
        working-directory: backend
        run: uv sync --locked --dev

      - name: Ruff format check
        working-directory: backend
        run: uv run --locked ruff format --check .

      - name: Ruff lint
        working-directory: backend
        run: uv run --locked ruff check .

      - name: Pyright
        working-directory: backend
        run: uv run --locked pyright

      - name: Pytest
        working-directory: backend
        run: uv run --locked pytest

      - name: Set up Node
        uses: actions/setup-node@v6
        with:
          node-version: 24
          cache: npm
          cache-dependency-path: frontend/package-lock.json

      - name: Install frontend dependencies
        working-directory: frontend
        run: npm ci

      - name: Install Playwright Chromium
        working-directory: frontend
        run: |
          if node -e "process.exit(require('./package.json').scripts['test:e2e'] ? 0 : 1)"; then
            npx playwright install --with-deps chromium
          fi

      - name: Frontend test
        working-directory: frontend
        run: npm run test --if-present

      - name: Frontend browser test
        working-directory: frontend
        run: npm run test:e2e --if-present

      - name: Frontend lint
        working-directory: frontend
        run: npm run lint

      - name: Frontend build
        working-directory: frontend
        run: npm run build
'@
        }
        else {
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

      - name: Install backend dependencies
        working-directory: backend
        run: uv sync --locked --dev

      - name: Ruff format check
        working-directory: backend
        run: uv run --locked ruff format --check .

      - name: Ruff lint
        working-directory: backend
        run: uv run --locked ruff check .

      - name: Pyright
        working-directory: backend
        run: uv run --locked pyright

      - name: Pytest
        working-directory: backend
        run: uv run --locked pytest

      - name: Set up Node
        uses: actions/setup-node@v6
        with:
          node-version: 24
          cache: npm
          cache-dependency-path: frontend/package-lock.json

      - name: Install frontend dependencies
        working-directory: frontend
        run: npm ci

      - name: Frontend test
        working-directory: frontend
        run: npm run test

      - name: Frontend typecheck
        working-directory: frontend
        run: npm run typecheck

      - name: Frontend lint
        working-directory: frontend
        run: npm run lint

      - name: Frontend build
        working-directory: frontend
        run: npm run build
'@
        }
    }

    if (-not $NoInstallHooks) {
        if (Test-Path ".git") {
            Write-Host "Installing pre-push hook..."
            Invoke-Checked uv --project backend run pre-commit install --hook-type pre-push
        }
        else {
            Write-Warning "No .git directory found. Skipping hook installation."
        }
    }

    Write-Host ""
    Write-Host "Done. Next: .\scripts\check.ps1"
    exit 0
}

Write-Host "Creating Python project: $ProjectName ($PackageName, Python $Python, pyright $TypeMode, profile $Profile)"

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

Write-Host "Adding dev tooling..."
Invoke-Checked uv add --dev @DevToolPins

Write-Host "Adding runtime dependencies..."
Invoke-Checked uv add @RuntimePins

if ($Profile -eq "desktop") {
    Invoke-Checked uv add "PySide6==$(Get-Pinned 'PY_PYSIDE6')"
}

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

if ($Profile -eq "desktop") {
    New-Item -ItemType Directory -Path (Join-Path (Join-Path "src" $PackageName) "ui") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path (Join-Path "src" $PackageName) "models") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path (Join-Path "src" $PackageName) "services") -Force | Out-Null

    Write-TextFile -Path (Join-Path (Join-Path (Join-Path "src" $PackageName) "ui") "__init__.py") -Content ""
    Write-TextFile -Path (Join-Path (Join-Path (Join-Path "src" $PackageName) "models") "__init__.py") -Content ""
    Write-TextFile -Path (Join-Path (Join-Path (Join-Path "src" $PackageName) "services") "__init__.py") -Content ""

    Write-TemplateFile -TemplateName "desktop/main_window.py" -Path (Join-Path (Join-Path (Join-Path "src" $PackageName) "ui") "main_window.py")
    Write-TemplateFile -TemplateName "desktop/__main__.py" -Path (Join-Path (Join-Path "src" $PackageName) "__main__.py")
    Write-TemplateFile -TemplateName "desktop/test_desktop_smoke.py" -Path (Join-Path "tests" "test_desktop_smoke.py")
}

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
venvPath = "."
venv = ".venv"

[tool.pytest.ini_options]
minversion = "8.0"
addopts = "-ra --strict-markers --strict-config --cov --cov-report=term-missing:skip-covered --cov-report=xml"
testpaths = ["tests"]

[tool.coverage.run]
branch = true
source = ["src"]
omit = [
    ".venv/*",
    "tests/*",
    "src/*/__main__.py"
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
!.env.example

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

Write-TextFile -Path ".env.example" -Content @"
# Add required environment variable names here. Never commit real secrets.
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

if ($Profile -eq "desktop") {
    $ReadmeCommands = @"
    uv run python -m $PackageName
    .\scripts\check.ps1
    .\scripts\fix.ps1
"@
    $SourceDescription = "Source code lives in src/$PackageName/. UI code lives in src/$PackageName/ui/. Tests live in tests/."
}
else {
    $ReadmeCommands = @"
    .\scripts\check.ps1
    .\scripts\fix.ps1
"@
    $SourceDescription = "Source code lives in src/$PackageName/. Tests live in tests/."
}

Write-TextFile -Path "README.md" -Content @"
# $ProjectName

## Setup

    uv sync --dev

Copy .env.example to .env only when real secrets are needed. Never commit .env.

Dependencies are pinned to exact versions. To upgrade one, change its version
in pyproject.toml, run uv lock, then run the checks.

## Commands

$SourceDescription

$ReadmeCommands

## Docs

Project memory lives in docs/project-memory.yaml.
"@

$Now = Get-Date
$TimeUtc = $Now.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$TimeLocal = $Now.ToString("yyyy-MM-ddTHH:mm:sszzz")

Write-TextFile -Path (Join-Path "docs" "project-memory.yaml") -Content @"
entries:
  - time_utc: "$TimeUtc"
    time_local: "$TimeLocal"
    summary: "Created initial $Profile scaffold."
    changed:
      - "Initial $Profile project, tests, checks, CI, hooks, and memory file."
    verification:
      - 'Not run yet; run .\scripts\check.ps1 before first commit.'
"@

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
Write-Host "Done. Next: .\scripts\check.ps1"
