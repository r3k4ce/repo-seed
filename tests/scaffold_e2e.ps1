$ErrorActionPreference = "Stop"

function Assert-Contains {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Expected
    )

    $content = Get-Content -Raw -LiteralPath $Path
    if (-not $content.Contains($Expected)) {
        throw "Expected $Path to contain: $Expected"
    }
}

function Assert-NotContains {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Unexpected
    )

    $content = Get-Content -Raw -LiteralPath $Path
    if ($content.Contains($Unexpected)) {
        throw "Expected $Path not to contain: $Unexpected"
    }
}

# Reads one KEY from versions.env so assertions follow the manifest instead of
# hard-coding version numbers that would drift.
$VersionsPath = Join-Path $PSScriptRoot "..\versions.env"
function Get-Pinned {
    param([Parameter(Mandatory)] [string]$Key)

    foreach ($line in [System.IO.File]::ReadAllLines($VersionsPath)) {
        if ($line -match "^$Key=([A-Za-z0-9.+-]+)\s*$") {
            return $Matches[1]
        }
    }

    throw "versions.env is missing $Key"
}

function Assert-ExactPinsOnly {
    param([Parameter(Mandatory)] [string]$Path)

    Assert-NotContains -Path $Path -Unexpected '"latest"'
    $content = Get-Content -Raw -LiteralPath $Path
    if ($content -match '": *"[\^~*]') {
        throw "Expected only exact version pins in $Path"
    }
}

# Generated helper scripts must be exact copies of templates/scripts/<profile>/,
# with no per-platform shell scripts alongside them.
function Assert-ProjectScripts {
    param(
        [Parameter(Mandatory)] [string]$ProfileName,
        [Parameter(Mandatory)] [string]$ProjectDir
    )

    foreach ($task in @("check", "fix")) {
        $template = Join-Path $PSScriptRoot "../templates/scripts/$ProfileName/$task.py"
        $generated = Join-Path $ProjectDir "scripts/$task.py"
        if (-not (Test-Path -LiteralPath $generated)) {
            throw "Expected generated script: $generated"
        }
        $expectedBytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $template))
        $actualBytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $generated))
        if ([System.Convert]::ToBase64String($expectedBytes) -ne [System.Convert]::ToBase64String($actualBytes)) {
            throw "Expected $generated to equal templates/scripts/$ProfileName/$task.py"
        }
    }
    foreach ($leftover in @("check.sh", "fix.sh", "check.ps1", "fix.ps1")) {
        if (Test-Path -LiteralPath (Join-Path $ProjectDir "scripts/$leftover")) {
            throw "Expected no scripts/$leftover in generated project: $ProjectDir"
        }
    }
}

if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    Write-Host "PowerShell web scaffold e2e skipped: uv is not available"
    exit 0
}

$Npm = if (Get-Command npm.cmd -ErrorAction SilentlyContinue) { "npm.cmd" } else { "npm" }
if (-not (Get-Command $Npm -ErrorAction SilentlyContinue)) {
    Write-Host "PowerShell web scaffold e2e skipped: npm is not available"
    exit 0
}

$TmpRoot = $null
$Pushed = $false

try {
    $TmpRoot = [System.IO.Path]::GetFullPath(
        [System.IO.Path]::Combine(
            [System.IO.Path]::GetTempPath(),
            [System.IO.Path]::GetRandomFileName()
        )
    )
    New-Item -ItemType Directory -Path $TmpRoot -Force | Out-Null

    $ProjectDir = Join-Path $TmpRoot "powershell-web-e2e"
    New-Item -ItemType Directory -Path $ProjectDir -Force | Out-Null

    Push-Location $ProjectDir
    $Pushed = $true
    try {
        & "$PSScriptRoot\..\new-project.ps1" -Name powershell-web-e2e -Profile web -NoGit -NoInstallHooks
    }
    finally {
        if ($Pushed) {
            Pop-Location
            $Pushed = $false
        }
    }

    $PackageJson = Join-Path $ProjectDir "frontend/package.json"
    $ViteConfig = Join-Path $ProjectDir "frontend/vite.config.ts"
    $CiYaml = Join-Path $ProjectDir ".github/workflows/ci.yml"
    $AgentsFile = Join-Path $ProjectDir "AGENTS.md"

    if (Test-Path -LiteralPath $AgentsFile) {
        throw "Expected no AGENTS.md in generated project: $AgentsFile"
    }

    Assert-ExactPinsOnly -Path $PackageJson
    Assert-Contains -Path $PackageJson -Expected ('"react": "' + (Get-Pinned "NPM_REACT") + '"')
    Assert-Contains -Path $PackageJson -Expected ('"tailwindcss": "' + (Get-Pinned "NPM_TAILWINDCSS") + '"')
    Assert-Contains -Path $PackageJson -Expected ('"@tailwindcss/vite": "' + (Get-Pinned "NPM_TAILWINDCSS_VITE") + '"')
    Assert-Contains -Path $PackageJson -Expected ('"vite": "' + (Get-Pinned "NPM_VITE") + '"')
    Assert-Contains -Path $PackageJson -Expected ('"vitest": "' + (Get-Pinned "NPM_VITEST") + '"')
    Assert-Contains -Path $PackageJson -Expected ('"@vitest/coverage-v8": "' + (Get-Pinned "NPM_VITEST_COVERAGE_V8") + '"')
    Assert-Contains -Path $PackageJson -Expected ('"@testing-library/dom": "' + (Get-Pinned "NPM_TESTING_LIBRARY_DOM") + '"')
    Assert-Contains -Path $PackageJson -Expected ('"node": ">=' + (Get-Pinned "NODE_MIN") + '"')
    Assert-Contains -Path $PackageJson -Expected '"test": "vitest run --coverage"'
    Assert-Contains -Path $PackageJson -Expected '"test:watch": "vitest"'
    Assert-Contains -Path (Join-Path $ProjectDir "frontend/.npmrc") -Expected 'save-exact=true'
    Assert-NotContains -Path $PackageJson -Unexpected "@playwright/test"
    Assert-NotContains -Path $PackageJson -Unexpected "test:e2e"

    Assert-Contains -Path $ViteConfig -Expected 'import tailwindcss from "@tailwindcss/vite";'
    Assert-Contains -Path $ViteConfig -Expected 'plugins: [react(), tailwindcss()]'
    Assert-Contains -Path $ViteConfig -Expected 'provider: "v8"'
    Assert-Contains -Path $ViteConfig -Expected 'statements: 80'
    Assert-Contains -Path $ViteConfig -Expected 'branches: 80'
    Assert-Contains -Path $ViteConfig -Expected 'functions: 80'
    Assert-Contains -Path $ViteConfig -Expected 'lines: 80'


    Assert-Contains -Path $CiYaml -Expected '- name: Frontend test'
    Assert-Contains -Path $CiYaml -Expected 'run: npm run test'
    Assert-Contains -Path $CiYaml -Expected '- name: Frontend typecheck'
    Assert-Contains -Path $CiYaml -Expected 'run: npm run typecheck'
    Assert-Contains -Path $CiYaml -Expected '- name: Frontend lint'
    Assert-Contains -Path $CiYaml -Expected 'run: npm run lint'
    Assert-Contains -Path $CiYaml -Expected '- name: Frontend build'
    Assert-Contains -Path $CiYaml -Expected 'run: npm run build'
    Assert-NotContains -Path $CiYaml -Unexpected "Install Playwright Chromium"
    Assert-NotContains -Path $CiYaml -Unexpected "test:e2e"

    Assert-ProjectScripts -ProfileName web -ProjectDir $ProjectDir
    Assert-Contains -Path (Join-Path $ProjectDir ".pre-commit-config.yaml") -Expected 'entry: uv run scripts/check.py'

    Push-Location $ProjectDir
    $Pushed = $true
    try {
        foreach ($script in @("scripts/check.py", "scripts/fix.py", "scripts/check.py")) {
            & uv run $script
            if ($LASTEXITCODE -ne 0) {
                throw "uv run $script failed with exit code $LASTEXITCODE"
            }
        }
    }
    finally {
        if ($Pushed) {
            Pop-Location
            $Pushed = $false
        }
    }

    Write-Host "PowerShell web scaffold e2e passed"
}
finally {
    if ($Pushed) {
        Pop-Location
    }
    if ($TmpRoot -and (Test-Path -LiteralPath $TmpRoot)) {
        if ($IsWindows) {
            & cmd.exe /c rmdir /s /q $TmpRoot 2>&1 | Out-Null
        }
        else {
            Remove-Item -LiteralPath $TmpRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
