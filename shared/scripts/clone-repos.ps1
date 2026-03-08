[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$ManifestPath
)

$ErrorActionPreference = 'Stop'

function Resolve-RepoRoot {
    param([string]$ScriptPath)
    if ($RepoRoot) {
        return (Resolve-Path $RepoRoot).Path
    }
    return (Resolve-Path (Join-Path $ScriptPath "..\..")).Path
}

function Normalize-RepoName {
    param([string]$RepoUrl)
    $leaf = Split-Path -Leaf $RepoUrl
    if ($leaf.EndsWith(".git")) {
        return $leaf.Substring(0, $leaf.Length - 4)
    }
    return $leaf
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Resolve-RepoRoot -ScriptPath $scriptDir

if (-not $ManifestPath) {
    $ManifestPath = Join-Path $root "repos-manifest.txt"
}

if (-not (Test-Path $ManifestPath)) {
    throw "Manifest not found: $ManifestPath"
}

$reposRoot = Join-Path $root "portable\repos"
New-Item -ItemType Directory -Force -Path $reposRoot | Out-Null

foreach ($line in Get-Content $ManifestPath) {
    $trimmed = $line.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
    if ($trimmed.StartsWith('#')) { continue }

    $parts = $trimmed.Split('|')
    $repoUrl = $parts[0].Trim()
    $branch = if ($parts.Count -ge 2) { $parts[1].Trim() } else { "" }
    $target = if ($parts.Count -ge 3) { $parts[2].Trim() } else { "" }

    if (-not $repoUrl) { continue }
    if (-not $target) {
        $target = Normalize-RepoName -RepoUrl $repoUrl
    }

    $targetPath = Join-Path $reposRoot $target

    if (-not (Test-Path $targetPath)) {
        Write-Host "Cloning $repoUrl -> $targetPath"
        git clone --recurse-submodules $repoUrl $targetPath
        if ($LASTEXITCODE -ne 0) {
            throw "git clone failed for $repoUrl"
        }
    }
    else {
        Write-Host "Updating existing repo: $targetPath"
        git -C $targetPath fetch --all --prune
        if ($LASTEXITCODE -ne 0) {
            throw "git fetch failed in $targetPath"
        }
        git -C $targetPath submodule update --init --recursive
        if ($LASTEXITCODE -ne 0) {
            throw "git submodule update failed in $targetPath"
        }
    }

    if ($branch) {
        Write-Host "Checking out branch '$branch' in $targetPath"
        git -C $targetPath checkout $branch
        if ($LASTEXITCODE -ne 0) {
            throw "git checkout failed for branch '$branch' in $targetPath"
        }
        git -C $targetPath pull --ff-only
        if ($LASTEXITCODE -ne 0) {
            throw "git pull --ff-only failed in $targetPath"
        }
        git -C $targetPath submodule update --init --recursive
        if ($LASTEXITCODE -ne 0) {
            throw "git submodule update failed in $targetPath"
        }
    }
}

Write-Host "Repo sync complete. Repos root: $reposRoot"
