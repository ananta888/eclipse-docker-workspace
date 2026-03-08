[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$OutputDir
)

$ErrorActionPreference = 'Stop'

function Resolve-RepoRoot {
    param([string]$ScriptPath)
    if ($RepoRoot) {
        return (Resolve-Path $RepoRoot).Path
    }
    return (Resolve-Path (Join-Path $ScriptPath "..\..")).Path
}

function Copy-IfExists {
    param(
        [string]$SourcePath,
        [string]$DestinationPath
    )

    if (-not (Test-Path $SourcePath)) {
        return
    }

    $parent = Split-Path -Parent $DestinationPath
    if ($parent) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Copy-Item -Path $SourcePath -Destination $DestinationPath -Recurse -Force
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Resolve-RepoRoot -ScriptPath $scriptDir

if (-not $OutputDir) {
    $OutputDir = Join-Path $root "backup"
}

$workspaceDir = Join-Path $root "portable\workspace"
$sharedDir = Join-Path $root "shared"
$manifestPath = Join-Path $root "repos-manifest.txt"

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$stagingDir = Join-Path ([System.IO.Path]::GetTempPath()) "dev-state-$timestamp"
$archivePath = Join-Path $OutputDir "dev-state-$timestamp.zip"

New-Item -ItemType Directory -Force -Path $OutputDir, $stagingDir | Out-Null

# Workspace metadata that captures IDE state with low footprint.
Copy-IfExists -SourcePath (Join-Path $workspaceDir ".launches") -DestinationPath (Join-Path $stagingDir "workspace\.launches")
Copy-IfExists -SourcePath (Join-Path $workspaceDir ".metadata\.plugins\org.eclipse.ui.workbench\workingsets.xml") -DestinationPath (Join-Path $stagingDir "workspace\.metadata\.plugins\org.eclipse.ui.workbench\workingsets.xml")
Copy-IfExists -SourcePath (Join-Path $workspaceDir ".metadata\.plugins\org.eclipse.wst.server.core") -DestinationPath (Join-Path $stagingDir "workspace\.metadata\.plugins\org.eclipse.wst.server.core")
Copy-IfExists -SourcePath (Join-Path $workspaceDir ".metadata\.plugins\org.eclipse.wst.server.ui") -DestinationPath (Join-Path $stagingDir "workspace\.metadata\.plugins\org.eclipse.wst.server.ui")

# Team-shared state.
Copy-IfExists -SourcePath (Join-Path $sharedDir "launch") -DestinationPath (Join-Path $stagingDir "shared\launch")
Copy-IfExists -SourcePath (Join-Path $sharedDir "prefs\eclipse.epf") -DestinationPath (Join-Path $stagingDir "shared\prefs\eclipse.epf")
Copy-IfExists -SourcePath $manifestPath -DestinationPath (Join-Path $stagingDir "repos-manifest.txt")

if (Test-Path $archivePath) {
    Remove-Item -Force $archivePath
}

Compress-Archive -Path (Join-Path $stagingDir "*") -DestinationPath $archivePath -CompressionLevel Optimal -Force
Remove-Item -Recurse -Force $stagingDir

Write-Host "Dev-state backup created: $archivePath"
