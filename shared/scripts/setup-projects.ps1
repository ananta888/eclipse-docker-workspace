[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$MasterRepoUrl,
    [string]$MasterBranch,
    [string]$MasterTargetDir,

    [string]$SubRepoUrl1,
    [string]$SubBranch1,
    [string]$SubTargetDir1,

    [string]$SubRepoUrl2,
    [string]$SubBranch2,
    [string]$SubTargetDir2,

    [string]$RepoRoot,
    [switch]$SkipSync,
    [switch]$GenerateEclipseProjects,
    [switch]$ImportIntoEclipse,
    [string]$WorkspacePath,
    [switch]$DisableSaros,
    [switch]$EnableSaros
)

$ErrorActionPreference = 'Stop'

function Resolve-RepoRoot {
    param([string]$ScriptPath)
    if ($RepoRoot) {
        return (Resolve-Path $RepoRoot).Path
    }
    return (Resolve-Path (Join-Path $ScriptPath "..\..")).Path
}

function Get-DefaultTargetDir {
    param([string]$RepoUrl)
    $leaf = Split-Path -Leaf $RepoUrl
    if ($leaf.EndsWith(".git")) {
        return $leaf.Substring(0, $leaf.Length - 4)
    }
    return $leaf
}

function Add-ManifestEntry {
    param(
        [System.Collections.Generic.List[string]]$List,
        [string]$RepoUrl,
        [string]$Branch,
        [string]$TargetDir
    )

    if ([string]::IsNullOrWhiteSpace($RepoUrl)) {
        return
    }

    $repo = $RepoUrl.Trim()
    $br = if ([string]::IsNullOrWhiteSpace($Branch)) { "" } else { $Branch.Trim() }
    $target = if ([string]::IsNullOrWhiteSpace($TargetDir)) { Get-DefaultTargetDir -RepoUrl $repo } else { $TargetDir.Trim() }
    $List.Add("$repo|$br|$target") | Out-Null
}

function Set-SarosEnabled {
    param(
        [string]$RepoRootPath,
        [bool]$Enabled
    )

    $pluginsDir = Join-Path $RepoRootPath "portable\eclipse-win\plugins"
    if (-not (Test-Path $pluginsDir)) {
        throw "Eclipse plugins directory not found: $pluginsDir"
    }

    if ($Enabled) {
        $disabledFiles = Get-ChildItem -Path $pluginsDir -File -Filter "saros*.jar.disabled" -ErrorAction SilentlyContinue
        foreach ($file in $disabledFiles) {
            $target = $file.FullName.Substring(0, $file.FullName.Length - ".disabled".Length)
            Move-Item -Force -Path $file.FullName -Destination $target
            Write-Host "Enabled Saros bundle: $(Split-Path -Leaf $target)"
        }
        return
    }

    $enabledFiles = Get-ChildItem -Path $pluginsDir -File -Filter "saros*.jar" -ErrorAction SilentlyContinue |
        Where-Object { -not $_.Name.EndsWith(".disabled") }
    foreach ($file in $enabledFiles) {
        $target = "$($file.FullName).disabled"
        Move-Item -Force -Path $file.FullName -Destination $target
        Write-Host "Disabled Saros bundle: $(Split-Path -Leaf $file.FullName)"
    }
}

function Invoke-GradleEclipse {
    param([string]$RepoPath)

    $searchDirs = New-Object System.Collections.Generic.List[string]
    $searchDirs.Add($RepoPath) | Out-Null
    foreach ($dir in Get-ChildItem -Path $RepoPath -Directory -ErrorAction SilentlyContinue) {
        $searchDirs.Add($dir.FullName) | Out-Null
    }

    $gradlew = $null
    $gradlewSh = $null
    $workingDir = $null

    foreach ($dir in $searchDirs) {
        $candidateBat = Join-Path $dir "gradlew.bat"
        $candidateSh = Join-Path $dir "gradlew"
        if (Test-Path $candidateBat) {
            $gradlew = $candidateBat
            $workingDir = $dir
            break
        }
        if (Test-Path $candidateSh) {
            $gradlewSh = $candidateSh
            $workingDir = $dir
            break
        }
    }

    if ($gradlew) {
        Write-Host "Generating Eclipse metadata via gradlew.bat in $workingDir"
        Push-Location $workingDir
        try {
            & $gradlew "-q" "eclipse"
        }
        finally {
            Pop-Location
        }
        if ($LASTEXITCODE -ne 0) {
            throw "gradlew.bat eclipse failed in $workingDir"
        }
        return
    }

    if ($gradlewSh) {
        Write-Host "Generating Eclipse metadata via gradlew in $workingDir"
        Push-Location $workingDir
        try {
            & bash $gradlewSh "-q" "eclipse"
        }
        finally {
            Pop-Location
        }
        if ($LASTEXITCODE -ne 0) {
            throw "gradlew eclipse failed in $workingDir"
        }
        return
    }

    Write-Warning "No Gradle wrapper found in $RepoPath. Skipping Eclipse metadata generation."
}

function Import-ProjectsIntoEclipse {
    param(
        [string]$RepoRootPath,
        [string]$WorkspacePath
    )

    $eclipseExe = Join-Path $RepoRootPath "portable\eclipse-win\eclipse.exe"
    if (-not (Test-Path $eclipseExe)) {
        throw "Eclipse executable not found: $eclipseExe. Run bootstrap-portable-eclipse-win11.ps1 first."
    }

    $reposPath = Join-Path $RepoRootPath "portable\repos"
    if (-not (Test-Path $reposPath)) {
        throw "Repos path not found: $reposPath"
    }
    $workspaceLock = Join-Path $WorkspacePath ".metadata\.lock"
    if (Test-Path $workspaceLock) {
        throw "Workspace appears to be in use: $WorkspacePath. Please close Eclipse and retry."
    }

    $projectDirs = Get-ChildItem -Path $reposPath -Recurse -File -Filter ".project" -ErrorAction SilentlyContinue |
        ForEach-Object { $_.Directory.FullName } |
        Sort-Object -Unique

    if (-not $projectDirs -or $projectDirs.Count -eq 0) {
        Write-Warning "No .project files found under $reposPath. Nothing to import."
        return
    }

    $featuresDir = Join-Path $RepoRootPath "portable\eclipse-win\features"
    $pluginsDir = Join-Path $RepoRootPath "portable\eclipse-win\plugins"
    $hasCdtFeature = $false
    $hasCdtHeadlessPlugin = $false

    if (Test-Path $featuresDir) {
        $hasCdtFeature = [bool](Get-ChildItem -Path $featuresDir -Filter "org.eclipse.cdt_*" -ErrorAction SilentlyContinue)
    }
    if (Test-Path $pluginsDir) {
        $hasCdtHeadlessPlugin = [bool](Get-ChildItem -Path $pluginsDir -Filter "org.eclipse.cdt.managedbuilder.core_*" -ErrorAction SilentlyContinue)
    }

    $useHeadlessImport = ($hasCdtFeature -or $hasCdtHeadlessPlugin)
    if (-not $useHeadlessImport) {
        Write-Warning "CDT headless importer not found. Falling back to standard Eclipse -import mode."
    }

    $eclipsecExe = Join-Path $RepoRootPath "portable\eclipse-win\eclipsec.exe"
    $launcherExe = if (Test-Path $eclipsecExe) { $eclipsecExe } else { $eclipseExe }

    $projectsStorePath = Join-Path $WorkspacePath ".metadata\.plugins\org.eclipse.core.resources\.projects"
    $countImportedProjects = {
        if (-not (Test-Path $projectsStorePath)) { return 0 }
        return @(
            Get-ChildItem -Path $projectsStorePath -Directory -ErrorAction SilentlyContinue |
            Where-Object { -not $_.Name.StartsWith(".") }
        ).Count
    }

    $beforeCount = & $countImportedProjects
    if ($useHeadlessImport) {
        Write-Host "Importing $($projectDirs.Count) projects into workspace $WorkspacePath via headless importer (before: $beforeCount)"

        $timeoutSeconds = 40
        $headlessApp = "org.eclipse.cdt.managedbuilder.core.headlessbuild"

        for ($i = 0; $i -lt $projectDirs.Count; $i++) {
            $projectDir = $projectDirs[$i]
            Write-Host ("  -> {0}/{1}: {2}" -f ($i + 1), $projectDirs.Count, $projectDir)

            $importArgs = @(
                "-nosplash"
                "-consoleLog"
                "-application"
                $headlessApp
                "-data"
                $WorkspacePath
                "-import"
                $projectDir
                "-vmargs"
                "--add-opens=java.base/java.util=ALL-UNNAMED"
                "--add-opens=java.base/java.lang=ALL-UNNAMED"
                "--add-opens=java.base/java.lang.reflect=ALL-UNNAMED"
                "--add-opens=java.base/java.text=ALL-UNNAMED"
                "--add-opens=java.desktop/java.awt.font=ALL-UNNAMED"
            )

            $proc = Start-Process -FilePath $launcherExe -ArgumentList $importArgs -NoNewWindow -PassThru
            $timedOut = $false
            try {
                Wait-Process -Id $proc.Id -Timeout $timeoutSeconds -ErrorAction Stop
            }
            catch {
                $timedOut = $true
                if (-not $proc.HasExited) {
                    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                }
            }

            if (-not $timedOut -and $proc.ExitCode -ne 0) {
                throw "Headless import failed for $projectDir with exit code $($proc.ExitCode)"
            }
        }
    }
    else {
        Write-Host "Importing $($projectDirs.Count) projects into workspace $WorkspacePath via standard -import mode (before: $beforeCount)"
        $batchSize = 20
        for ($i = 0; $i -lt $projectDirs.Count; $i += $batchSize) {
            $upper = [Math]::Min($i + $batchSize - 1, $projectDirs.Count - 1)
            $batch = @($projectDirs[$i..$upper])
            Write-Host "  -> batch $($i + 1)-$($upper + 1)"

            $importArgs = @(
                "-nosplash"
                "-consoleLog"
                "-data"
                $WorkspacePath
            )
            foreach ($projectDir in $batch) {
                $importArgs += @("-import", $projectDir)
            }
            $importArgs += @(
                "-vmargs"
                "--add-opens=java.base/java.util=ALL-UNNAMED"
                "--add-opens=java.base/java.lang=ALL-UNNAMED"
                "--add-opens=java.base/java.lang.reflect=ALL-UNNAMED"
                "--add-opens=java.base/java.text=ALL-UNNAMED"
                "--add-opens=java.desktop/java.awt.font=ALL-UNNAMED"
            )

            $proc = Start-Process -FilePath $launcherExe -ArgumentList $importArgs -NoNewWindow -Wait -PassThru
            if ($proc.ExitCode -ne 0) {
                throw "Eclipse project import failed in batch starting at index $i with exit code $($proc.ExitCode)"
            }
        }
    }

    $afterCount = & $countImportedProjects
    Write-Host "Imported projects visible in workspace metadata: $afterCount"
    if ($afterCount -le 0) {
        throw "Import completed without registered projects in workspace metadata. Check $WorkspacePath\.metadata\.log"
    }
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Resolve-RepoRoot -ScriptPath $scriptDir
$manifestPath = Join-Path $root "repos-manifest.txt"
$cloneScript = Join-Path $root "shared\scripts\clone-repos.ps1"

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Format: <git-url>|<branch>|<target-subdir-under-portable/repos>") | Out-Null
$lines.Add("# Generated by shared/scripts/setup-projects.ps1") | Out-Null
$lines.Add("") | Out-Null

Add-ManifestEntry -List $lines -RepoUrl $MasterRepoUrl -Branch $MasterBranch -TargetDir $MasterTargetDir
Add-ManifestEntry -List $lines -RepoUrl $SubRepoUrl1 -Branch $SubBranch1 -TargetDir $SubTargetDir1
Add-ManifestEntry -List $lines -RepoUrl $SubRepoUrl2 -Branch $SubBranch2 -TargetDir $SubTargetDir2

Set-Content -Path $manifestPath -Value $lines -Encoding UTF8
Write-Host "Manifest written: $manifestPath"

if ($DisableSaros -and $EnableSaros) {
    throw "Use either -DisableSaros or -EnableSaros, not both."
}

if ($DisableSaros) {
    Set-SarosEnabled -RepoRootPath $root -Enabled:$false
}

if ($EnableSaros) {
    Set-SarosEnabled -RepoRootPath $root -Enabled:$true
}

if (-not $SkipSync) {
    if (-not (Test-Path $cloneScript)) {
        throw "Clone script not found: $cloneScript"
    }
    & powershell -NoProfile -ExecutionPolicy Bypass -File $cloneScript -RepoRoot $root -ManifestPath $manifestPath
    if ($LASTEXITCODE -ne 0) {
        throw "clone-repos.ps1 failed with exit code $LASTEXITCODE"
    }
}

if ($GenerateEclipseProjects) {
    $reposRoot = Join-Path $root "portable\repos"

    $masterDir = if ([string]::IsNullOrWhiteSpace($MasterTargetDir)) {
        Get-DefaultTargetDir -RepoUrl $MasterRepoUrl
    } else {
        $MasterTargetDir.Trim()
    }
    $masterPath = Join-Path $reposRoot $masterDir
    if (-not (Test-Path $masterPath)) {
        throw "Master repo path not found: $masterPath"
    }
    Invoke-GradleEclipse -RepoPath $masterPath

    foreach ($sub in @(
        @{ Url = $SubRepoUrl1; Target = $SubTargetDir1 },
        @{ Url = $SubRepoUrl2; Target = $SubTargetDir2 }
    )) {
        if ([string]::IsNullOrWhiteSpace($sub.Url)) { continue }
        $subDir = if ([string]::IsNullOrWhiteSpace($sub.Target)) {
            Get-DefaultTargetDir -RepoUrl $sub.Url
        } else {
            $sub.Target.Trim()
        }
        $subPath = Join-Path $reposRoot $subDir
        if (Test-Path $subPath) {
            Invoke-GradleEclipse -RepoPath $subPath
        }
    }
}

if ($ImportIntoEclipse) {
    $workspace = if ([string]::IsNullOrWhiteSpace($WorkspacePath)) {
        Join-Path $root "portable\workspace-win"
    } else {
        $WorkspacePath
    }
    New-Item -ItemType Directory -Force -Path $workspace | Out-Null
    Import-ProjectsIntoEclipse -RepoRootPath $root -WorkspacePath $workspace
}

Write-Host "Done. Repositories are managed via: $manifestPath"
