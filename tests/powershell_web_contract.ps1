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

function Assert-InOrder {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string[]]$Expected
    )

    $content = Get-Content -Raw -LiteralPath $Path
    $offset = 0
    foreach ($needle in $Expected) {
        $found = $content.IndexOf($needle, $offset)
        if ($found -lt 0) {
            throw "Expected $Path to contain: $needle"
        }
        $offset = $found + $needle.Length
    }
}

$TmpRoot = $null
$OriginalPath = $env:Path

try {
    $TmpRoot = [System.IO.Path]::GetFullPath(
        [System.IO.Path]::Combine(
            [System.IO.Path]::GetTempPath(),
            [System.IO.Path]::GetRandomFileName()
        )
    )
    $BinDir = Join-Path $TmpRoot "bin"
    New-Item -ItemType Directory -Path $BinDir -Force | Out-Null

    $env:Path = $BinDir + [System.IO.Path]::PathSeparator + $env:Path

    Set-Content -LiteralPath (Join-Path $BinDir "npm.cmd") -Value @"
@echo off
exit /b 0
"@

    Set-Content -LiteralPath (Join-Path $BinDir "uv.cmd") -Value @"
@echo off
if /I not "%~1"=="init" exit /b 0
set "package=python_project"
set "project=."
:parse
shift
if "%~1"=="" goto create
if /I "%~1"=="--name" (
  set "package=%~2"
  shift
) else if /I "%~1"=="--python" (
  shift
) else if /I "%~1"=="--vcs" (
  shift
) else if /I not "%~1"=="--package" (
  set "project=%~1"
)
goto parse
:create
set "package=%package:-=_%"
mkdir "%project%\src\%package%" 2>nul
> "%project%\pyproject.toml" echo [project]
exit /b 0
"@

    $ProjectDir = Join-Path $TmpRoot "ps-web-contract"
    New-Item -ItemType Directory -Path $ProjectDir -Force | Out-Null

    Push-Location $ProjectDir
    try {
        & "$PSScriptRoot\..\new-project.ps1" -Name ps-web-contract -Profile web -NoGit -NoInstallHooks
    }
    finally {
        Pop-Location
    }

    $PackageJson = Join-Path $ProjectDir "frontend/package.json"
    $ViteConfig = Join-Path $ProjectDir "frontend/vite.config.ts"
    $CheckScript = Join-Path $ProjectDir "scripts/check.ps1"
    $FixScript = Join-Path $ProjectDir "scripts/fix.ps1"
    $PreCommit = Join-Path $ProjectDir ".pre-commit-config.yaml"
    $CiYaml = Join-Path $ProjectDir ".github/workflows/ci.yml"

    Assert-Contains -Path $PackageJson -Expected '"react": "^19.0.0"'
    Assert-Contains -Path $PackageJson -Expected '"tailwindcss": "^4.3.2"'
    Assert-Contains -Path $PackageJson -Expected '"@tailwindcss/vite": "^4.3.2"'
    Assert-Contains -Path $PackageJson -Expected '"@vitest/coverage-v8": "^4.1.9"'
    Assert-Contains -Path $PackageJson -Expected '"test": "vitest run --coverage"'
    Assert-Contains -Path $PackageJson -Expected '"test:watch": "vitest"'
    Assert-NotContains -Path $PackageJson -Unexpected '"latest"'
    Assert-NotContains -Path $PackageJson -Unexpected "@playwright/test"
    Assert-NotContains -Path $PackageJson -Unexpected "test:e2e"

    Assert-Contains -Path $ViteConfig -Expected 'import tailwindcss from "@tailwindcss/vite";'
    Assert-Contains -Path $ViteConfig -Expected 'plugins: [react(), tailwindcss()]'
    Assert-Contains -Path $ViteConfig -Expected 'provider: "v8"'
    Assert-Contains -Path $ViteConfig -Expected 'statements: 80'
    Assert-Contains -Path $ViteConfig -Expected 'branches: 80'
    Assert-Contains -Path $ViteConfig -Expected 'functions: 80'
    Assert-Contains -Path $ViteConfig -Expected 'lines: 80'
    Assert-Contains -Path $ViteConfig -Expected '"src/main.tsx"'
    Assert-Contains -Path $ViteConfig -Expected '"src/vite-env.d.ts"'
    Assert-Contains -Path $ViteConfig -Expected '"src/test/**"'
    Assert-Contains -Path $ViteConfig -Expected '"**/*.test.{ts,tsx}"'

    $WebCheckOrder = @(
        'Invoke-Checked $Npm run test',
        'Invoke-Checked $Npm run typecheck',
        'Invoke-Checked $Npm run lint',
        'Invoke-Checked $Npm run build'
    )
    Assert-InOrder -Path $CheckScript -Expected $WebCheckOrder
    Assert-InOrder -Path $FixScript -Expected $WebCheckOrder
    Assert-NotContains -Path $CheckScript -Unexpected "--if-present"
    Assert-NotContains -Path $CheckScript -Unexpected "test:e2e"
    Assert-NotContains -Path $FixScript -Unexpected "--if-present"
    Assert-NotContains -Path $FixScript -Unexpected "test:e2e"

    Assert-Contains -Path $PreCommit -Expected 'powershell -ExecutionPolicy Bypass -File scripts/check.ps1'

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

    Write-Host "PowerShell web contract passed"
}
finally {
    if ($OriginalPath) {
        $env:Path = $OriginalPath
    }
    if ($TmpRoot -and (Test-Path -LiteralPath $TmpRoot)) {
        & cmd.exe /c rmdir /s /q $TmpRoot 2>&1 | Out-Null
    }
}
