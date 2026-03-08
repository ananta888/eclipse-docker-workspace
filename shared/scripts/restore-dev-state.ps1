[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$ArchivePath
)

$ErrorActionPreference = 'Stop'

function Resolve-RepoRoot {
    param([string]$ScriptPath)
    if ($RepoRoot) {
        return (Resolve-Path $RepoRoot).Path
    }
    return (Resolve-Path (Join-Path $ScriptPath "..\..")).Path
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Resolve-RepoRoot -ScriptPath $scriptDir

if (-not $ArchivePath) {
    $backupDir = Join-Path $root "backup"
    $latest = Get-ChildItem -Path $backupDir -Filter "dev-state-*.zip" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $latest) {
        throw "No backup archive found in $backupDir"
    }
    $ArchivePath = $latest.FullName
}

if (-not (Test-Path $ArchivePath)) {
    throw "Archive not found: $ArchivePath"
}

$extractDir = Join-Path ([System.IO.Path]::GetTempPath()) ("dev-state-restore-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $extractDir | Out-Null

Expand-Archive -Path $ArchivePath -DestinationPath $extractDir -Force
Copy-Item -Path (Join-Path $extractDir "*") -Destination $root -Recurse -Force
Remove-Item -Recurse -Force $extractDir

Write-Host "Dev-state restored from: $ArchivePath"
Write-Host "Restart Eclipse to apply restored workspace metadata."
