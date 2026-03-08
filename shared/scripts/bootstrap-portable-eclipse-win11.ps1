[CmdletBinding()]
param(
    [string]$EclipseVersion,
    [string]$EclipseBuild,
    [string]$RepoRoot,
    [switch]$SkipPluginInstall
)

$ErrorActionPreference = 'Stop'

function Get-RepoRoot {
    param([string]$ScriptPath)
    if ($RepoRoot) {
        return (Resolve-Path $RepoRoot).Path
    }

    $candidate = Resolve-Path (Join-Path $ScriptPath "..\..")
    return $candidate.Path
}

function Get-EclipseReleaseFromDockerfile {
    param([string]$DockerfilePath)

    $version = $null
    $build = $null

    if (Test-Path $DockerfilePath) {
        foreach ($line in Get-Content $DockerfilePath) {
            if (-not $version -and $line -match '^ENV\s+ECLIPSE_VERSION=(.+)$') {
                $version = $Matches[1].Trim()
            }
            if (-not $build -and $line -match '^ENV\s+ECLIPSE_BUILD=(.+)$') {
                $build = $Matches[1].Trim()
            }
        }
    }

    if (-not $version) { $version = '2025-12' }
    if (-not $build) { $build = 'R' }

    return @{ Version = $version; Build = $build }
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$resolvedRepoRoot = Get-RepoRoot -ScriptPath $scriptDir

$dockerfilePath = Join-Path $resolvedRepoRoot 'docker\eclipse\Dockerfile'
$releaseInfo = Get-EclipseReleaseFromDockerfile -DockerfilePath $dockerfilePath

if (-not $EclipseVersion) { $EclipseVersion = $releaseInfo.Version }
if (-not $EclipseBuild) { $EclipseBuild = $releaseInfo.Build }

$portableRoot = Join-Path $resolvedRepoRoot 'portable'
$eclipseHome = Join-Path $portableRoot 'eclipse-win'
$workspaceDir = Join-Path $portableRoot 'workspace'
$configDir = Join-Path $portableRoot 'config'
$sharedDir = Join-Path $resolvedRepoRoot 'shared'
$prefsFile = Join-Path $sharedDir 'prefs\eclipse.epf'
$pluginsFile = Join-Path $sharedDir 'p2\plugins.txt'
$launchSrcDir = Join-Path $sharedDir 'launch'
$launchDstDir = Join-Path $workspaceDir '.launches'

$package = "eclipse-java-$EclipseVersion-$EclipseBuild-win32-x86_64.zip"
$downloadUrl = "https://www.eclipse.org/downloads/download.php?file=/technology/epp/downloads/release/$EclipseVersion/$EclipseBuild/$package&r=1"
$tempZip = Join-Path $env:TEMP $package

Write-Host "Repo root: $resolvedRepoRoot"
Write-Host "Eclipse release: $EclipseVersion/$EclipseBuild"
Write-Host "Download URL: $downloadUrl"

New-Item -ItemType Directory -Force -Path $portableRoot, $workspaceDir, $configDir | Out-Null

if (Test-Path $eclipseHome) {
    Remove-Item -Recurse -Force $eclipseHome
}

Write-Host "Downloading Eclipse package..."
Invoke-WebRequest -Uri $downloadUrl -OutFile $tempZip

Write-Host "Extracting Eclipse..."
Expand-Archive -Path $tempZip -DestinationPath $portableRoot -Force

$extractedDir = Join-Path $portableRoot 'eclipse'
if (-not (Test-Path $extractedDir)) {
    throw "Expected extracted directory not found: $extractedDir"
}

Move-Item -Force -Path $extractedDir -Destination $eclipseHome
Remove-Item -Force $tempZip

$eclipseExe = Join-Path $eclipseHome 'eclipse.exe'
if (-not (Test-Path $eclipseExe)) {
    throw "Eclipse executable not found: $eclipseExe"
}

Write-Host "Copying shared configuration snapshot..."
$sharedConfigTarget = Join-Path $configDir 'shared'
if (Test-Path $sharedConfigTarget) {
    Remove-Item -Recurse -Force $sharedConfigTarget
}
Copy-Item -Recurse -Force $sharedDir $sharedConfigTarget

if (Test-Path $launchSrcDir) {
    New-Item -ItemType Directory -Force -Path $launchDstDir | Out-Null
    Copy-Item -Recurse -Force (Join-Path $launchSrcDir '*') $launchDstDir
}

if (-not $SkipPluginInstall) {
    if (-not (Test-Path $pluginsFile)) {
        throw "Plugin file not found: $pluginsFile"
    }

    Write-Host "Installing plugins from shared/p2/plugins.txt..."
    foreach ($line in Get-Content $pluginsFile) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
        if ($trimmed.StartsWith('#')) { continue }

        $parts = $trimmed.Split('|', 2)
        if ($parts.Count -ne 2) { continue }

        $repo = $parts[0].Trim()
        $iu = $parts[1].Trim()
        if (-not $repo -or -not $iu) { continue }

        Write-Host "  -> $iu"
        & $eclipseExe `
            -nosplash `
            -application org.eclipse.equinox.p2.director `
            -repository $repo `
            -installIU $iu `
            -profile SDKProfile `
            -destination $eclipseHome `
            -bundlepool $eclipseHome `
            -roaming

        if ($LASTEXITCODE -ne 0) {
            throw "Plugin installation failed for IU: $iu"
        }
    }
}

if (Test-Path $prefsFile) {
    Write-Host "Importing team preferences..."
    & $eclipseExe `
        -nosplash `
        -application org.eclipse.ui.ide.workbench `
        -data $workspaceDir `
        -import $prefsFile

    if ($LASTEXITCODE -ne 0) {
        throw "Preference import failed."
    }
}

Write-Host "Done."
Write-Host "Start Eclipse with: portable\\start-eclipse-win11.bat"
Write-Host "Configured workspace: $workspaceDir"
Write-Host "Docker compose also maps this workspace path (via WORKSPACE_DIR default)."
