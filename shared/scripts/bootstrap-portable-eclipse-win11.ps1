[CmdletBinding()]
param(
    [string]$EclipseVersion,
    [string]$EclipseBuild,
    [string]$RepoRoot,
    [switch]$SkipPluginInstall,
    [switch]$ImportPreferences
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
$workspaceDir = Join-Path $portableRoot 'workspace-win'
$reposDir = Join-Path $portableRoot 'repos'
$configDir = Join-Path $portableRoot 'config'
$sharedDir = Join-Path $resolvedRepoRoot 'shared'
$prefsFile = Join-Path $sharedDir 'prefs\eclipse.epf'
$pluginsFile = Join-Path $sharedDir 'p2\plugins.txt'
$launchSrcDir = Join-Path $sharedDir 'launch'
$launchDstDir = Join-Path $workspaceDir '.launches'
$p2Profile = 'epp.package.java'
$requiredSarosVmOpens = @(
    '--add-opens=java.base/java.util=ALL-UNNAMED',
    '--add-opens=java.base/java.lang=ALL-UNNAMED',
    '--add-opens=java.base/java.lang.reflect=ALL-UNNAMED',
    '--add-opens=java.base/java.text=ALL-UNNAMED',
    '--add-opens=java.desktop/java.awt.font=ALL-UNNAMED'
)

$package = "eclipse-java-$EclipseVersion-$EclipseBuild-win32-x86_64.zip"
$downloadUrl = "https://www.eclipse.org/downloads/download.php?file=/technology/epp/downloads/release/$EclipseVersion/$EclipseBuild/$package&r=1"
$cacheDir = Join-Path $portableRoot 'cache'
$cachedZip = Join-Path $cacheDir $package
$scriptVersion = "bootstrap-portable-eclipse-win11.ps1 fallback-v6 2026-03-08"

function Get-LatestP2LogSnippet {
    param(
        [string]$EclipseHome,
        [int]$TailLines = 120
    )

    $configDir = Join-Path $EclipseHome 'configuration'
    if (-not (Test-Path $configDir)) {
        return $null
    }

    $logCandidates = Get-ChildItem -Path $configDir -Filter '*.log' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending
    if (-not $logCandidates) {
        return $null
    }

    $latest = $logCandidates[0]
    $tail = Get-Content -Path $latest.FullName -Tail $TailLines -ErrorAction SilentlyContinue
    if (-not $tail) {
        return "Latest p2 log: $($latest.FullName) (empty)"
    }

    return "Latest p2 log: $($latest.FullName)`n--- LOG TAIL ---`n$($tail -join [Environment]::NewLine)"
}

function Get-LatestWorkspaceLogSnippet {
    param(
        [string]$WorkspaceDir,
        [int]$TailLines = 120
    )

    $workspaceLog = Join-Path $WorkspaceDir '.metadata\.log'
    if (-not (Test-Path $workspaceLog)) {
        return $null
    }

    $tail = Get-Content -Path $workspaceLog -Tail $TailLines -ErrorAction SilentlyContinue
    if (-not $tail) {
        return "Workspace log: $workspaceLog (empty)"
    }

    return "Workspace log: $workspaceLog`n--- LOG TAIL ---`n$($tail -join [Environment]::NewLine)"
}

function Test-FeatureIUInstalled {
    param(
        [string]$EclipseHome,
        [string]$IU
    )

    if (-not $IU.EndsWith('.feature.group')) {
        return $false
    }

    $featureId = $IU.Substring(0, $IU.Length - '.feature.group'.Length)
    $featuresDir = Join-Path $EclipseHome 'features'
    if (-not (Test-Path $featuresDir)) {
        return $false
    }

    $patterns = New-Object System.Collections.Generic.List[string]
    $patterns.Add("$featureId_*") | Out-Null

    # Some feature IUs use ".feature.group" while the on-disk feature folder uses a shorter id.
    if ($featureId -eq 'org.eclipse.cdt.feature') {
        $patterns.Add("org.eclipse.cdt_*") | Out-Null
    }

    $matches = @()
    foreach ($pattern in $patterns) {
        $matches += Get-ChildItem -Path $featuresDir -Filter $pattern -ErrorAction SilentlyContinue
    }
    return [bool]$matches
}

function Test-IsSarosIU {
    param([string]$IU)
    return $IU -eq 'saros.feature.feature.group'
}

function Ensure-EclipseIniVmArgs {
    param(
        [string]$EclipseIniPath,
        [string[]]$RequiredVmArgs
    )

    if (-not (Test-Path $EclipseIniPath)) {
        Write-Warning "eclipse.ini not found: $EclipseIniPath"
        return
    }

    $lines = Get-Content -Path $EclipseIniPath
    if (-not $lines) {
        Write-Warning "eclipse.ini is empty: $EclipseIniPath"
        return
    }

    $vmargsIndex = [Array]::IndexOf($lines, '-vmargs')
    if ($vmargsIndex -lt 0) {
        Write-Warning "No -vmargs section found in eclipse.ini: $EclipseIniPath"
        return
    }

    $vmargLines = @()
    if ($vmargsIndex + 1 -le $lines.Count - 1) {
        $vmargLines = @($lines[($vmargsIndex + 1)..($lines.Count - 1)])
    }

    $missing = New-Object System.Collections.Generic.List[string]
    foreach ($arg in $RequiredVmArgs) {
        if (-not ($vmargLines -contains $arg)) {
            $missing.Add($arg) | Out-Null
        }
    }

    if ($missing.Count -eq 0) {
        Write-Host "Saros Java module opens already present in eclipse.ini."
        return
    }

    $head = @($lines[0..$vmargsIndex])
    $updated = $head + $vmargLines + @($missing.ToArray())
    Set-Content -Path $EclipseIniPath -Value $updated -Encoding UTF8
    Write-Host "Added Saros Java module opens to eclipse.ini:"
    foreach ($arg in $missing) {
        Write-Host "  $arg"
    }
}

Write-Host "Repo root: $resolvedRepoRoot"
Write-Host "Script version: $scriptVersion"
Write-Host "Eclipse release: $EclipseVersion/$EclipseBuild"
Write-Host "Download URL: $downloadUrl"

New-Item -ItemType Directory -Force -Path $portableRoot, $workspaceDir, $reposDir, $configDir, $cacheDir | Out-Null

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

$eclipseIniPath = Join-Path $eclipseHome 'eclipse.ini'
Ensure-EclipseIniVmArgs -EclipseIniPath $eclipseIniPath -RequiredVmArgs $requiredSarosVmOpens

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
    $pluginReposByIU = @{}
    $pluginOrder = New-Object System.Collections.Generic.List[string]

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

        if (-not $pluginReposByIU.ContainsKey($iu)) {
            $pluginReposByIU[$iu] = New-Object System.Collections.Generic.List[string]
            $pluginOrder.Add($iu) | Out-Null
        }
        if (-not $pluginReposByIU[$iu].Contains($repo)) {
            $pluginReposByIU[$iu].Add($repo) | Out-Null
        }
    }

    foreach ($iu in $pluginOrder) {
        $alreadyInstalled = Test-FeatureIUInstalled -EclipseHome $eclipseHome -IU $iu

        # Always try installation to avoid false positives in local feature detection.
        # p2 director is idempotent and will no-op when the IU is already installed.

        $installed = $false
        $attemptFailures = New-Object System.Collections.Generic.List[string]

        foreach ($repo in $pluginReposByIU[$iu]) {
            Write-Host "  -> $iu (repo: $repo)"
            $directorArgs = @(
                '-nosplash',
                '-consoleLog',
                '-application', 'org.eclipse.equinox.p2.director',
                '-repository', $repo,
                '-installIU', $iu,
                '-profile', $p2Profile,
                '-destination', $eclipseHome,
                '-bundlepool', $eclipseHome,
                '-roaming'
            )
            $directorOutput = & $eclipseExe @directorArgs 2>&1

            $exitCode = $LASTEXITCODE
            if ($exitCode -eq 0) {
                $installed = $true
                break
            }

            $details = ($directorOutput | Out-String).Trim()
            $p2LogSnippet = Get-LatestP2LogSnippet -EclipseHome $eclipseHome
            $failureBlock = "Repository: $repo`nExitCode: $exitCode"
            if ($details) {
                $failureBlock += "`n$details"
            }
            if ($p2LogSnippet) {
                $failureBlock += "`n`n$p2LogSnippet"
            }
            $attemptFailures.Add($failureBlock) | Out-Null
            Write-Warning "Plugin install attempt failed for IU '$iu' from repo '$repo'. Trying next configured repo (if any)."
        }

        if (-not $installed) {
            $failureDetails = ($attemptFailures -join "`n`n---`n`n")
            if ((Test-IsSarosIU -IU $iu) -and $alreadyInstalled) {
                Write-Warning "Saros repair install failed, but Saros is already installed. Continuing bootstrap.`nAttempted repositories:`n$failureDetails"
                continue
            }
            throw "Plugin installation failed for IU: $iu`nAttempted repositories:`n$failureDetails"
        }
    }
}

if ($ImportPreferences -and (Test-Path $prefsFile)) {
    Write-Host "Importing team preferences..."
    $importArgs = @(
        '-nosplash',
        '-consoleLog',
        '-application', 'org.eclipse.ui.ide.workbench',
        '-data', $workspaceDir,
        '-import', $prefsFile
    )
    $importOutput = & $eclipseExe @importArgs 2>&1

    if ($LASTEXITCODE -ne 0) {
        $details = ($importOutput | Out-String).Trim()
        $workspaceLogSnippet = Get-LatestWorkspaceLogSnippet -WorkspaceDir $workspaceDir
        $failureMessage = "Preference import failed (continuing bootstrap)."
        if ($details) {
            $failureMessage += "`n$details"
        }
        if ($workspaceLogSnippet) {
            $failureMessage += "`n`n$workspaceLogSnippet"
        }
        Write-Warning $failureMessage
    }
}
elseif (Test-Path $prefsFile) {
    Write-Host "Skipping preference import (headless default). Use -ImportPreferences to run it explicitly."
}

Write-Host "Done."
Write-Host "Start Eclipse with: portable\\start-eclipse-win11.bat"
Write-Host "Configured workspace: $workspaceDir"
Write-Host "Configured repo root: $reposDir"
Write-Host "Windows workspace is separated from Docker workspace by default."
