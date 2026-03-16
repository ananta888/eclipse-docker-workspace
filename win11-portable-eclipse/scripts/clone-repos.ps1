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
    return (Resolve-Path (Join-Path $ScriptPath '..\..')).Path
}

function Normalize-RepoName {
    param([string]$RepoUrl)
    $leaf = Split-Path -Leaf $RepoUrl
    if ($leaf.EndsWith('.git')) {
        return $leaf.Substring(0, $leaf.Length - 4)
    }
    return $leaf
}

function Test-LocalBranchExists {
    param(
        [string]$RepoPath,
        [string]$BranchName
    )
    & git -C $RepoPath show-ref --verify --quiet "refs/heads/$BranchName"
    return ($LASTEXITCODE -eq 0)
}

function Test-RemoteBranchExists {
    param(
        [string]$RepoPath,
        [string]$BranchName
    )
    & git -C $RepoPath show-ref --verify --quiet "refs/remotes/origin/$BranchName"
    return ($LASTEXITCODE -eq 0)
}

function Get-OriginDefaultBranch {
    param([string]$RepoPath)

    $headRef = (& git -C $RepoPath symbolic-ref --short refs/remotes/origin/HEAD 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($headRef)) {
        return $null
    }

    if ($headRef.StartsWith('origin/')) {
        return $headRef.Substring('origin/'.Length)
    }

    return $headRef
}

function Resolve-CheckoutBranch {
    param(
        [string]$RepoPath,
        [string]$RequestedBranch
    )

    if ([string]::IsNullOrWhiteSpace($RequestedBranch)) {
        $currentBranch = (& git -C $RepoPath branch --show-current 2>$null).Trim()
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($currentBranch)) {
            return $currentBranch
        }

        $originDefault = Get-OriginDefaultBranch -RepoPath $RepoPath
        if ($originDefault) {
            return $originDefault
        }

        if ((Test-LocalBranchExists -RepoPath $RepoPath -BranchName 'master') -or
            (Test-RemoteBranchExists -RepoPath $RepoPath -BranchName 'master')) {
            return 'master'
        }

        if ((Test-LocalBranchExists -RepoPath $RepoPath -BranchName 'main') -or
            (Test-RemoteBranchExists -RepoPath $RepoPath -BranchName 'main')) {
            return 'main'
        }

        return $null
    }

    if ((Test-LocalBranchExists -RepoPath $RepoPath -BranchName $RequestedBranch) -or
        (Test-RemoteBranchExists -RepoPath $RepoPath -BranchName $RequestedBranch)) {
        return $RequestedBranch
    }

    $originDefault = Get-OriginDefaultBranch -RepoPath $RepoPath
    if ($originDefault -and (
            (Test-LocalBranchExists -RepoPath $RepoPath -BranchName $originDefault) -or
            (Test-RemoteBranchExists -RepoPath $RepoPath -BranchName $originDefault)
        )) {
        Write-Warning "Requested branch '$RequestedBranch' not found in $RepoPath. Falling back to remote default '$originDefault'."
        return $originDefault
    }

    if ((Test-LocalBranchExists -RepoPath $RepoPath -BranchName 'master') -or
        (Test-RemoteBranchExists -RepoPath $RepoPath -BranchName 'master')) {
        Write-Warning "Requested branch '$RequestedBranch' not found in $RepoPath. Falling back to 'master'."
        return 'master'
    }

    throw "Requested branch '$RequestedBranch' not found in $RepoPath, and no fallback branch could be resolved."
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Resolve-RepoRoot -ScriptPath $scriptDir

if (-not $ManifestPath) {
    $ManifestPath = Join-Path $root 'repos-manifest.txt'
}

if (-not (Test-Path $ManifestPath)) {
    throw "Manifest not found: $ManifestPath"
}

$reposRoot = Join-Path $root 'portable\repos'
New-Item -ItemType Directory -Force -Path $reposRoot | Out-Null

foreach ($line in Get-Content $ManifestPath) {
    $trimmed = $line.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
    if ($trimmed.StartsWith('#')) { continue }

    $parts = $trimmed.Split('|')
    $repoUrl = $parts[0].Trim()
    $branch = if ($parts.Count -ge 2) { $parts[1].Trim() } else { '' }
    $target = if ($parts.Count -ge 3) { $parts[2].Trim() } else { '' }

    if (-not $repoUrl) { continue }
    if (-not $target) {
        $target = Normalize-RepoName -RepoUrl $repoUrl
    }

    $targetPath = Join-Path $reposRoot $target

    if (-not (Test-Path $targetPath)) {
        Write-Host "Cloning $repoUrl -> $targetPath"
        git -c core.longpaths=true clone --recurse-submodules $repoUrl $targetPath
        if ($LASTEXITCODE -ne 0) {
            throw "git clone failed for $repoUrl"
        }
        git -C $targetPath config core.longpaths true
        if ($LASTEXITCODE -ne 0) {
            throw "git config core.longpaths failed in $targetPath"
        }
    }
    else {
        if (-not (Test-Path (Join-Path $targetPath '.git'))) {
            throw "Target exists but is not a git repository: $targetPath"
        }
        Write-Host "Updating existing repo: $targetPath"
        git -C $targetPath config core.longpaths true
        if ($LASTEXITCODE -ne 0) {
            throw "git config core.longpaths failed in $targetPath"
        }
        git -C $targetPath fetch --all --prune
        if ($LASTEXITCODE -ne 0) {
            throw "git fetch failed in $targetPath"
        }
        git -C $targetPath submodule update --init --recursive
        if ($LASTEXITCODE -ne 0) {
            throw "git submodule update failed in $targetPath"
        }
    }

    $effectiveBranch = Resolve-CheckoutBranch -RepoPath $targetPath -RequestedBranch $branch
    if ($effectiveBranch) {
        Write-Host "Checking out branch '$effectiveBranch' in $targetPath"
        if (Test-LocalBranchExists -RepoPath $targetPath -BranchName $effectiveBranch) {
            git -C $targetPath checkout $effectiveBranch
        }
        elseif (Test-RemoteBranchExists -RepoPath $targetPath -BranchName $effectiveBranch) {
            git -C $targetPath checkout -b $effectiveBranch --track "origin/$effectiveBranch"
        }
        else {
            throw "Branch '$effectiveBranch' does not exist locally or on origin in $targetPath"
        }
        if ($LASTEXITCODE -ne 0) {
            throw "git checkout failed for branch '$effectiveBranch' in $targetPath"
        }
        git -C $targetPath pull --ff-only origin $effectiveBranch
        if ($LASTEXITCODE -ne 0) {
            throw "git pull --ff-only failed in $targetPath"
        }
        git -C $targetPath submodule update --init --recursive
        if ($LASTEXITCODE -ne 0) {
            throw "git submodule update failed in $targetPath"
        }
    }
    else {
        Write-Warning "No checkout branch resolved for $targetPath. Keeping current HEAD."
    }
}

Write-Host "Repo sync complete. Repos root: $reposRoot"
