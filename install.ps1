[CmdletBinding()]
param(
    [string]$BinDir,
    [string]$DataDir,
    [string]$Command = "reposeed"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Stop-WithMessage {
    param([Parameter(Mandatory)] [string]$Message)

    Write-Error $Message
    exit 1
}

function Get-DefaultLocalAppData {
    if ($env:LOCALAPPDATA) {
        return $env:LOCALAPPDATA
    }

    return Join-Path $HOME "AppData\Local"
}

function Test-EmptyDirectory {
    param([Parameter(Mandatory)] [string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return $false
    }

    return $null -eq (Get-ChildItem -LiteralPath $Path -Force | Select-Object -First 1)
}

function Resolve-FullPath {
    param([Parameter(Mandatory)] [string]$Path)

    return [System.IO.Path]::GetFullPath($Path)
}

function Test-PathOnPath {
    param([Parameter(Mandatory)] [string]$Path)

    $fullPath = Resolve-FullPath $Path
    $pathEntries = ($env:PATH -split [System.IO.Path]::PathSeparator) | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_)
    }

    foreach ($entry in $pathEntries) {
        if ([string]::Equals((Resolve-FullPath $entry), $fullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function Ensure-DataDirCanBeReplaced {
    param([Parameter(Mandatory)] [string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        Stop-WithMessage "Data path exists and is not a directory: $Path"
    }

    if (Test-Path -LiteralPath (Join-Path $Path ".reposeed-install")) {
        return
    }

    if (Test-EmptyDirectory $Path) {
        return
    }

    Stop-WithMessage "Refusing to replace non-empty unmanaged data directory: $Path"
}

function Copy-Payload {
    param([Parameter(Mandatory)] [string]$PayloadPath)

    New-Item -ItemType Directory -Path $PayloadPath -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $RepoRoot "new-project.sh") -Destination (Join-Path $PayloadPath "new-project.sh") -Force
    Copy-Item -LiteralPath (Join-Path $RepoRoot "new-project.ps1") -Destination (Join-Path $PayloadPath "new-project.ps1") -Force
    Copy-Item -LiteralPath (Join-Path $RepoRoot "templates") -Destination (Join-Path $PayloadPath "templates") -Recurse -Force
    Set-Content -LiteralPath (Join-Path $PayloadPath ".reposeed-install") -Value @(
        "managed-by=RepoSeed"
        "installed-command=$Command"
    ) -Encoding utf8
}

function Replace-DataDir {
    param([Parameter(Mandatory)] [string]$PayloadPath)

    $parent = Split-Path -Parent $DataDir
    if ($parent) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    if (Test-Path -LiteralPath $DataDir) {
        Remove-Item -LiteralPath $DataDir -Recurse -Force
    }

    Move-Item -LiteralPath $PayloadPath -Destination $DataDir
}

function Write-Wrapper {
    New-Item -ItemType Directory -Path $BinDir -Force | Out-Null

    $wrapper = Join-Path $BinDir "$Command.ps1"
    $installedScript = Join-Path $DataDir "new-project.ps1"
    $escapedScript = $installedScript.Replace("'", "''")

Set-Content -LiteralPath $wrapper -Encoding utf8 -Value @"
`$ErrorActionPreference = "Stop"
& '$escapedScript' @args
if (-not `$?) { exit 1 }
exit 0
"@

    return $wrapper
}

function Warn-IfBinDirNotOnPath {
    if (-not (Test-PathOnPath $BinDir)) {
        Write-Warning "$BinDir is not on PATH. Add it to your user PATH before running $Command by name."
    }
}

if ([string]::IsNullOrWhiteSpace($Command)) {
    Stop-WithMessage "-Command must not be empty."
}

if ($Command -match '[\\/]') {
    Stop-WithMessage "-Command must be a command name, not a path."
}

$localAppData = Get-DefaultLocalAppData

if ([string]::IsNullOrWhiteSpace($BinDir)) {
    $BinDir = Join-Path $localAppData "Microsoft\WindowsApps"
}

if ([string]::IsNullOrWhiteSpace($DataDir)) {
    $DataDir = Join-Path $localAppData "RepoSeed"
}

$BinDir = Resolve-FullPath $BinDir
$DataDir = Resolve-FullPath $DataDir
$RepoRoot = $PSScriptRoot

if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot "new-project.sh"))) {
    Stop-WithMessage "Missing new-project.sh next to installer."
}

if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot "new-project.ps1"))) {
    Stop-WithMessage "Missing new-project.ps1 next to installer."
}

if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot "templates") -PathType Container)) {
    Stop-WithMessage "Missing templates directory next to installer."
}

Ensure-DataDirCanBeReplaced $DataDir

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString("N"))
$payload = Join-Path $tempRoot "reposeed"

try {
    Copy-Payload $payload
    Replace-DataDir $payload
    $wrapper = Write-Wrapper
    Warn-IfBinDirNotOnPath

    Write-Host "Installed $Command to $wrapper"
    Write-Host "Managed files are in $DataDir"
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
