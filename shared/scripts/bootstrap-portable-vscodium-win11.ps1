[CmdletBinding()]
param(
    [string]$VSCodiumVersion = 'latest',
    [string]$RepoRoot,
    [switch]$SkipExtensionInstall
)

$ErrorActionPreference = 'Stop'

function Get-RepoRoot {
    param([string]$ScriptPath)
    if ($RepoRoot) {
        return (Resolve-Path $RepoRoot).Path
    }

    return (Resolve-Path (Join-Path $ScriptPath "..\..")).Path
}

function Get-VSCodiumReleaseAsset {
    param([string]$Version)

    $apiBase = 'https://api.github.com/repos/VSCodium/vscodium/releases'
    $releaseUrl = if ($Version -eq 'latest') {
        "$apiBase/latest"
    }
    else {
        "$apiBase/tags/$Version"
    }

    Write-Host "Resolving VSCodium release metadata from: $releaseUrl"
    $release = Invoke-RestMethod -Uri $releaseUrl -Headers @{ 'User-Agent' = 'Codex-VSCodium-Bootstrap' }
    $asset = $release.assets | Where-Object { $_.name -match '^VSCodium-win32-x64-.*\.zip$' } | Select-Object -First 1
    if (-not $asset) {
        throw "No matching VSCodium Windows ZIP asset found for release '$Version'."
    }

    return @{
        Version = $release.tag_name
        AssetName = $asset.name
        DownloadUrl = $asset.browser_download_url
    }
}

function Get-VSCodiumExecutable {
    param([string]$InstallDir)

    $candidates = @(
        (Join-Path $InstallDir 'VSCodium.exe'),
        (Join-Path $InstallDir 'bin\codium.cmd')
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    return $null
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$resolvedRepoRoot = Get-RepoRoot -ScriptPath $scriptDir

$portableRoot = Join-Path $resolvedRepoRoot 'portable'
$installRoot = Join-Path $portableRoot 'vscodium-win'
$workspaceDir = Join-Path $portableRoot 'workspace-vscodium'
$reposDir = Join-Path $portableRoot 'repos'
$cacheDir = Join-Path $portableRoot 'cache'
$configDir = Join-Path $resolvedRepoRoot 'shared\vscode'
$portableDataDir = Join-Path $installRoot 'data'
$userDataDir = Join-Path $portableDataDir 'user-data'
$userSettingsDir = Join-Path $userDataDir 'User'
$extensionsDir = Join-Path $portableDataDir 'extensions'
$settingsTemplate = Join-Path $configDir 'settings.json'
$extensionsFile = Join-Path $configDir 'extensions.txt'
$javaConfigScript = Join-Path $resolvedRepoRoot 'shared\scripts\configure-portable-vscodium-java-win11.ps1'
$scriptVersion = 'bootstrap-portable-vscodium-win11.ps1 v2 2026-03-15'

Write-Host "Repo root: $resolvedRepoRoot"
Write-Host "Script version: $scriptVersion"

New-Item -ItemType Directory -Force -Path $portableRoot, $workspaceDir, $reposDir, $cacheDir, $configDir | Out-Null

$existingExecutable = Get-VSCodiumExecutable -InstallDir $installRoot
if (-not $existingExecutable) {
    $releaseAsset = Get-VSCodiumReleaseAsset -Version $VSCodiumVersion
    $cachedZip = Join-Path $cacheDir $releaseAsset.AssetName
    $extractRoot = Join-Path $cacheDir ("extract-vscodium-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))

    Write-Host "Resolved VSCodium version: $($releaseAsset.Version)"
    Write-Host "Download URL: $($releaseAsset.DownloadUrl)"

    if (-not (Test-Path $cachedZip)) {
        Write-Host "Downloading VSCodium ZIP..."
        Invoke-WebRequest -Uri $releaseAsset.DownloadUrl -OutFile $cachedZip -Headers @{ 'User-Agent' = 'Codex-VSCodium-Bootstrap' }
    }
    else {
        Write-Host "Using cached archive: $cachedZip"
    }

    if (Test-Path $installRoot) {
        throw "Target directory already exists without a valid VSCodium executable: $installRoot"
    }

    New-Item -ItemType Directory -Force -Path $extractRoot | Out-Null
    Write-Host "Extracting archive..."
    Expand-Archive -Path $cachedZip -DestinationPath $extractRoot -Force

    $extractedExecutable = Get-ChildItem -Path $extractRoot -Filter 'VSCodium.exe' -Recurse -File | Select-Object -First 1
    if (-not $extractedExecutable) {
        throw "Expected VSCodium.exe not found after extraction: $extractRoot"
    }

    $extractedRoot = Split-Path -Parent $extractedExecutable.FullName
    Move-Item -Path $extractedRoot -Destination $installRoot
}
else {
    Write-Host "Existing VSCodium installation found ($existingExecutable). Skipping download/extract."
}

$portableExecutable = Get-VSCodiumExecutable -InstallDir $installRoot
if (-not $portableExecutable) {
    throw "Portable VSCodium executable not found: $installRoot"
}

New-Item -ItemType Directory -Force -Path $userSettingsDir, $extensionsDir | Out-Null

$settingsTarget = Join-Path $userSettingsDir 'settings.json'
if ((Test-Path $settingsTemplate) -and (-not (Test-Path $settingsTarget))) {
    Copy-Item -Path $settingsTemplate -Destination $settingsTarget
    Write-Host "Seeded portable settings from shared/vscode/settings.json"
}
elseif (Test-Path $settingsTarget) {
    Write-Host "Portable settings already exist. Keeping local settings file."
}

if (Test-Path $javaConfigScript) {
    & $javaConfigScript -RepoRoot $resolvedRepoRoot -SettingsPath $settingsTarget
    if ($LASTEXITCODE -ne 0) {
        Write-Warning 'Automatic Java 21 configuration reported a non-zero exit code.'
    }
}

if (-not $SkipExtensionInstall -and (Test-Path $extensionsFile)) {
    $codiumCmd = Join-Path $installRoot 'bin\codium.cmd'
    if (Test-Path $codiumCmd) {
        $extensions = Get-Content $extensionsFile | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') }
        foreach ($extension in $extensions) {
            Write-Host "Installing extension: $extension"
            & $codiumCmd '--user-data-dir' $userDataDir '--extensions-dir' $extensionsDir '--install-extension' $extension
            if ($LASTEXITCODE -ne 0) {
                throw "Extension installation failed: $extension"
            }
        }
    }
    else {
        Write-Warning "codium.cmd not found. Skipping extension installation."
    }
}
elseif (Test-Path $extensionsFile) {
    Write-Host "Skipping extension installation by request."
}

Write-Host "Done."
Write-Host "Start VSCodium with: portable\\start-vscodium-win11.bat"
Write-Host "Configured workspace: $workspaceDir"
Write-Host "Configured repo root: $reposDir"
