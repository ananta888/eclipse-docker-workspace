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
    [switch]$ImportIntoEclipse
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

    $projectDirs = Get-ChildItem -Path $reposPath -Recurse -File -Filter ".project" -ErrorAction SilentlyContinue |
        ForEach-Object { $_.Directory.FullName } |
        Sort-Object -Unique

    if (-not $projectDirs -or $projectDirs.Count -eq 0) {
        Write-Warning "No .project files found under $reposPath. Nothing to import."
        return
    }

    Write-Host "Importing $($projectDirs.Count) Eclipse projects into workspace $WorkspacePath"
    $importArgs = @(
        "-nosplash"
        "-consoleLog"
        "-application"
        "org.eclipse.ui.ide.workbench"
        "-data"
        $WorkspacePath
    )
    foreach ($projectDir in $projectDirs) {
        $importArgs += @("-import", $projectDir)
    }

    # Use Start-Process so Eclipse stderr log lines do not get promoted to terminating PowerShell errors.
    $proc = Start-Process -FilePath $eclipseExe -ArgumentList $importArgs -NoNewWindow -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        throw "Eclipse project import failed with exit code $($proc.ExitCode)"
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
    $workspace = Join-Path $root "portable\workspace"
    New-Item -ItemType Directory -Force -Path $workspace | Out-Null
    Import-ProjectsIntoEclipse -RepoRootPath $root -WorkspacePath $workspace
}

Write-Host "Done. Repositories are managed via: $manifestPath"
