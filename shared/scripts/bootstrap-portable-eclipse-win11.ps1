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
$cacheDir = Join-Path $portableRoot 'cache'
$cachedZip = Join-Path $cacheDir $package

Write-Host "Repo root: $resolvedRepoRoot"
Write-Host "Eclipse release: $EclipseVersion/$EclipseBuild"
Write-Host "Download URL: $downloadUrl"

New-Item -ItemType Directory -Force -Path $portableRoot, $workspaceDir, $configDir, $cacheDir | Out-Null

$eclipseExe = Join-Path $eclipseHome 'eclipse.exe'
$extractedDir = Join-Path $portableRoot 'eclipse'
$extractedExe = Join-Path $extractedDir 'eclipse.exe'
$hasExistingInstall = Test-Path $eclipseExe
$recoveryDir = "${eclipseHome}.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$recoveryHint = "Safe recovery (no delete): Move-Item -Path '$eclipseHome' -Destination '$recoveryDir'"

# Early state checks before any download/extract action.
if ($hasExistingInstall) {
    Write-Host "Existing Eclipse installation found ($eclipseExe). Skipping download/extract."
}
elseif (Test-Path $extractedExe) {
    Write-Host "Found already extracted Eclipse directory ($extractedDir). Finalizing installation without download."
    if (Test-Path $eclipseHome) {
        throw "Target directory already exists without valid eclipse.exe: $eclipseHome`nRefusing to delete existing content automatically.`n$recoveryHint"
    }
    Move-Item -Force -Path $extractedDir -Destination $eclipseHome
    $hasExistingInstall = Test-Path $eclipseExe
}

if (-not $hasExistingInstall) {
    if (-not (Test-Path $cachedZip)) {
        Write-Host "Downloading Eclipse package..."
        Invoke-WebRequest -Uri $downloadUrl -OutFile $cachedZip
    }
    else {
        Write-Host "Using cached Eclipse package: $cachedZip"
    }

    if (Test-Path $eclipseHome) {
        throw "Target directory already exists without valid eclipse.exe: $eclipseHome`nRefusing to delete existing content automatically.`n$recoveryHint"
    }

    Write-Host "Extracting Eclipse..."
    Expand-Archive -Path $cachedZip -DestinationPath $portableRoot -Force

    if (-not (Test-Path $extractedDir)) {
        throw "Expected extracted directory not found: $extractedDir"
    }
    if (-not (Test-Path $extractedExe)) {
        throw "Expected extracted executable not found: $extractedExe"
    }

    Move-Item -Force -Path $extractedDir -Destination $eclipseHome
}

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
        $repo = $repo.Replace('${ECLIPSE_VERSION}', $EclipseVersion).Replace('$ECLIPSE_VERSION', $EclipseVersion)

        Write-Host "  -> $iu (repo: $repo)"
        $directorArgs = @(
            '-nosplash',
            '-application', 'org.eclipse.equinox.p2.director',
            '-repository', $repo,
            '-installIU', $iu,
            '-profile', 'SDKProfile',
            '-destination', $eclipseHome,
            '-bundlepool', $eclipseHome,
            '-roaming'
        )
        $directorOutput = & $eclipseExe @directorArgs 2>&1

        if ($LASTEXITCODE -ne 0) {
            $details = ($directorOutput | Out-String).Trim()
            throw "Plugin installation failed for IU: $iu`nRepository: $repo`nDetails:`n$details"
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
