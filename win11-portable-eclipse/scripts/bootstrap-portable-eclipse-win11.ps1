[CmdletBinding()]
param(
    [string]$EclipseVersion = '2025-12',
    [string]$EclipseBuild = 'R',
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
    return (Resolve-Path (Join-Path $ScriptPath '..\..')).Path
}

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

    if ($featureId.EndsWith('.feature')) {
        $shortId = $featureId.Substring(0, $featureId.Length - '.feature'.Length)
        $patterns.Add("$shortId_*") | Out-Null
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
        return
    }

    $lines = Get-Content -Path $EclipseIniPath
    $vmargsIndex = [Array]::IndexOf($lines, '-vmargs')
    if ($vmargsIndex -lt 0) {
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
        return
    }

    $head = @($lines[0..$vmargsIndex])
    $updated = $head + $vmargLines + @($missing.ToArray())
    Set-Content -Path $EclipseIniPath -Value $updated -Encoding UTF8
}

function Invoke-EclipseWorkbenchImport {
    param(
        [string]$EclipseExe,
        [string[]]$Arguments,
        [int]$TimeoutSeconds = 45
    )

    $stdoutPath = Join-Path $env:TEMP "eclipse-import-$PID-out.log"
    $stderrPath = Join-Path $env:TEMP "eclipse-import-$PID-err.log"

    if (Test-Path $stdoutPath) {
        Remove-Item -Force $stdoutPath
    }
    if (Test-Path $stderrPath) {
        Remove-Item -Force $stderrPath
    }

    $proc = Start-Process -FilePath $EclipseExe -ArgumentList $Arguments -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    $timedOut = $false

    try {
        Wait-Process -Id $proc.Id -Timeout $TimeoutSeconds -ErrorAction Stop
    }
    catch {
        $timedOut = $true
    }
    finally {
        if (-not $proc.HasExited) {
            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
            Wait-Process -Id $proc.Id -Timeout 5 -ErrorAction SilentlyContinue
        }
    }

    $stdout = if (Test-Path $stdoutPath) { Get-Content -Path $stdoutPath -ErrorAction SilentlyContinue } else { @() }
    $stderr = if (Test-Path $stderrPath) { Get-Content -Path $stderrPath -ErrorAction SilentlyContinue } else { @() }

    return @{
        TimedOut = $timedOut
        ExitCode = if ($proc.HasExited) { $proc.ExitCode } else { -1 }
        StdOut = @($stdout)
        StdErr = @($stderr)
        OutputText = ((@($stdout) + @($stderr)) | Out-String).Trim()
    }
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$resolvedRepoRoot = Get-RepoRoot -ScriptPath $scriptDir
$packageRoot = Join-Path $resolvedRepoRoot 'win11-portable-eclipse'
$portableRoot = Join-Path $resolvedRepoRoot 'portable'
$eclipseHome = Join-Path $portableRoot 'eclipse-win'
$workspaceDir = Join-Path $portableRoot 'workspace-win'
$reposDir = Join-Path $portableRoot 'repos'
$configDir = Join-Path $portableRoot 'config'
$prefsFile = Join-Path $packageRoot 'config\prefs\eclipse.epf'
$pluginsFile = Join-Path $packageRoot 'config\p2\plugins.txt'
$launchSrcDir = Join-Path $packageRoot 'config\launch'
$launchDstDir = Join-Path $workspaceDir '.launches'
$workbenchPluginDir = Join-Path $workspaceDir '.metadata\.plugins\org.eclipse.ui.workbench'
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

New-Item -ItemType Directory -Force -Path $portableRoot, $workspaceDir, $reposDir, $configDir, $cacheDir | Out-Null

$eclipseExe = Join-Path $eclipseHome 'eclipse.exe'
$extractedDir = Join-Path $portableRoot 'eclipse'
$extractedExe = Join-Path $extractedDir 'eclipse.exe'
$hasExistingInstall = Test-Path $eclipseExe
$recoveryDir = "${eclipseHome}.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

function Move-InvalidInstallAside {
    param(
        [string]$SourceDir,
        [string]$BackupDir
    )

    if (-not (Test-Path $SourceDir)) {
        return
    }

    Write-Warning "Existing Eclipse target is incomplete. Moving it aside: $SourceDir -> $BackupDir"
    Move-Item -Force -Path $SourceDir -Destination $BackupDir
}

if ($hasExistingInstall) {
    Write-Host "Existing Eclipse installation found ($eclipseExe). Skipping download/extract."
}
elseif (Test-Path $extractedExe) {
    Write-Host "Found already extracted Eclipse directory ($extractedDir). Finalizing installation without download."
    if (Test-Path $eclipseHome) {
        Move-InvalidInstallAside -SourceDir $eclipseHome -BackupDir $recoveryDir
    }
    Move-Item -Force -Path $extractedDir -Destination $eclipseHome
    $hasExistingInstall = Test-Path $eclipseExe
}

if (-not $hasExistingInstall) {
    if (-not (Test-Path $cachedZip)) {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $cachedZip
    }

    if (Test-Path $eclipseHome) {
        Move-InvalidInstallAside -SourceDir $eclipseHome -BackupDir $recoveryDir
    }

    if (Test-Path $extractedDir) {
        Remove-Item -Recurse -Force $extractedDir
    }

    Expand-Archive -Path $cachedZip -DestinationPath $portableRoot -Force
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

$packageConfigTarget = Join-Path $configDir 'win11-portable-eclipse'
if (Test-Path $packageConfigTarget) {
    Remove-Item -Recurse -Force $packageConfigTarget
}
Copy-Item -Recurse -Force $packageRoot $packageConfigTarget

if (Test-Path $launchSrcDir) {
    New-Item -ItemType Directory -Force -Path $launchDstDir | Out-Null
    Copy-Item -Recurse -Force (Join-Path $launchSrcDir '*') $launchDstDir
}

if (Test-Path $workbenchPluginDir) {
    $workingsetsFile = Join-Path $workbenchPluginDir 'workingsets.xml'
    if (Test-Path $workingsetsFile) {
        Remove-Item -Force $workingsetsFile
    }
}

if (-not $SkipPluginInstall) {
    $pluginReposByIU = @{}
    $pluginOrder = New-Object System.Collections.Generic.List[string]

    foreach ($line in Get-Content $pluginsFile) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
        if ($trimmed.StartsWith('#')) { continue }

        $parts = $trimmed.Split('|', 2)
        if ($parts.Count -ne 2) { continue }

        $repo = $parts[0].Trim().Replace('${ECLIPSE_VERSION}', $EclipseVersion).Replace('$ECLIPSE_VERSION', $EclipseVersion)
        $iu = $parts[1].Trim()
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
        if ((-not (Test-IsSarosIU -IU $iu)) -and $alreadyInstalled) {
            continue
        }

        $installed = $false
        $attemptFailures = New-Object System.Collections.Generic.List[string]

        foreach ($repo in $pluginReposByIU[$iu]) {
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

            if ($LASTEXITCODE -eq 0) {
                $installed = $true
                break
            }

            $failureBlock = "Repository: $repo`nExitCode: $LASTEXITCODE"
            $details = ($directorOutput | Out-String).Trim()
            if ($details) {
                $failureBlock += "`n$details"
            }
            $p2LogSnippet = Get-LatestP2LogSnippet -EclipseHome $eclipseHome
            if ($p2LogSnippet) {
                $failureBlock += "`n`n$p2LogSnippet"
            }
            $attemptFailures.Add($failureBlock) | Out-Null
        }

        if (-not $installed) {
            $failureDetails = ($attemptFailures -join "`n`n---`n`n")
            if ((Test-IsSarosIU -IU $iu) -and $alreadyInstalled) {
                Write-Warning "Saros repair install failed, but Saros is already installed. Continuing.`n$failureDetails"
                continue
            }
            throw "Plugin installation failed for IU: $iu`nAttempted repositories:`n$failureDetails"
        }
    }
}

if ($ImportPreferences -and (Test-Path $prefsFile)) {
    $importArgs = @(
        '-nosplash',
        '-consoleLog',
        '-application', 'org.eclipse.ui.ide.workbench',
        '-data', $workspaceDir,
        '-import', $prefsFile
    )
    $importResult = Invoke-EclipseWorkbenchImport -EclipseExe $eclipseExe -Arguments $importArgs
    if ($importResult.TimedOut -or $importResult.ExitCode -ne 0) {
        $details = $importResult.OutputText
        $workspaceLogSnippet = Get-LatestWorkspaceLogSnippet -WorkspaceDir $workspaceDir
        $failureMessage = 'Preference import failed (continuing bootstrap).'
        if ($importResult.TimedOut) {
            $failureMessage += ' Eclipse was force-closed after the import timeout.'
        }
        if ($details) {
            $failureMessage += "`n$details"
        }
        if ($workspaceLogSnippet) {
            $failureMessage += "`n`n$workspaceLogSnippet"
        }
        Write-Warning $failureMessage
    }
}
