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
    [ValidateSet('disabled', 'marker', 'auto')]
    [string]$FolderProjectMode = 'marker',
    [string]$FolderProjectMarker = '.eclipse-project-dir',
    [switch]$DisableSaros,
    [switch]$EnableSaros
)

$ErrorActionPreference = 'Stop'

function Resolve-RepoRoot {
    param([string]$ScriptPath)
    if ($RepoRoot) {
        return (Resolve-Path $RepoRoot).Path
    }
    return (Resolve-Path (Join-Path $ScriptPath '..\..')).Path
}

function Get-DefaultTargetDir {
    param([string]$RepoUrl)
    $leaf = Split-Path -Leaf $RepoUrl
    if ($leaf.EndsWith('.git')) {
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
    $br = if ([string]::IsNullOrWhiteSpace($Branch)) { '' } else { $Branch.Trim() }
    $target = if ([string]::IsNullOrWhiteSpace($TargetDir)) { Get-DefaultTargetDir -RepoUrl $repo } else { $TargetDir.Trim() }
    $List.Add("$repo|$br|$target") | Out-Null
}

function Set-SarosEnabled {
    param(
        [string]$RepoRootPath,
        [bool]$Enabled
    )

    $pluginsDir = Join-Path $RepoRootPath 'portable\eclipse-win\plugins'
    if (-not (Test-Path $pluginsDir)) {
        throw "Eclipse plugins directory not found: $pluginsDir"
    }

    if ($Enabled) {
        $disabledFiles = Get-ChildItem -Path $pluginsDir -File -Filter 'saros*.jar.disabled' -ErrorAction SilentlyContinue
        foreach ($file in $disabledFiles) {
            $target = $file.FullName.Substring(0, $file.FullName.Length - '.disabled'.Length)
            Move-Item -Force -Path $file.FullName -Destination $target
            Write-Host "Enabled Saros bundle: $(Split-Path -Leaf $target)"
        }
        return
    }

    $enabledFiles = Get-ChildItem -Path $pluginsDir -File -Filter 'saros*.jar' -ErrorAction SilentlyContinue |
        Where-Object { -not $_.Name.EndsWith('.disabled') }
    foreach ($file in $enabledFiles) {
        $target = "$($file.FullName).disabled"
        Move-Item -Force -Path $file.FullName -Destination $target
        Write-Host "Disabled Saros bundle: $(Split-Path -Leaf $file.FullName)"
    }
}

function New-BuildshipProjectFile {
    param(
        [string]$ProjectDir,
        [string]$ProjectName,
        [string]$Comment
    )

    $projectFile = Join-Path $ProjectDir '.project'
    if (Test-Path $projectFile) {
        return
    }

@"
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
	<name>$ProjectName</name>
	<comment>$Comment</comment>
	<projects/>
	<natures>
		<nature>org.eclipse.buildship.core.gradleprojectnature</nature>
		<nature>net.sf.eclipsecs.core.CheckstyleNature</nature>
	</natures>
	<buildSpec>
		<buildCommand>
			<name>org.eclipse.buildship.core.gradleprojectbuilder</name>
			<arguments/>
		</buildCommand>
		<buildCommand>
			<name>net.sf.eclipsecs.core.CheckstyleBuilder</name>
			<arguments/>
		</buildCommand>
	</buildSpec>
	<linkedResources/>
	<filteredResources/>
</projectDescription>
"@ | Set-Content -Path $projectFile -Encoding UTF8
}

function New-BasicProjectFile {
    param(
        [string]$ProjectDir,
        [string]$ProjectName,
        [string]$Comment
    )

    $projectFile = Join-Path $ProjectDir '.project'
@"
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
	<name>$ProjectName</name>
	<comment>$Comment</comment>
	<projects/>
	<buildSpec/>
	<natures/>
	<linkedResources/>
	<filteredResources/>
</projectDescription>
"@ | Set-Content -Path $projectFile -Encoding UTF8
}

function Test-DirectoryContainsFiles {
    param([string]$ProjectDir)

    return [bool](Get-ChildItem -Path $ProjectDir -File -Recurse -Depth 1 -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -ne '.project' -and
        $_.FullName -notmatch '[\\/]\.git[\\/]' -and
        $_.FullName -notmatch '[\\/]\.gradle[\\/]'
    } | Select-Object -First 1)
}

function Test-DirectoryIsOptedInProject {
    param([string]$ProjectDir)

    switch ($FolderProjectMode) {
        'disabled' { return $false }
        'marker' { return (Test-Path (Join-Path $ProjectDir $FolderProjectMarker)) }
        'auto' { return (Test-DirectoryContainsFiles -ProjectDir $ProjectDir) }
        default { throw "Unsupported folder project mode: $FolderProjectMode" }
    }
}

function Get-PortableProjectName {
    param(
        [string]$RepoPath,
        [string]$ProjectDir
    )

    $repoName = Split-Path -Leaf $RepoPath
    $relativePath = $ProjectDir.Substring($RepoPath.Length).TrimStart('\', '/')
    if ([string]::IsNullOrWhiteSpace($relativePath)) {
        return $repoName
    }

    $sanitized = $relativePath -replace '[\\/]+', '-'
    return "$repoName-$sanitized"
}

function Ensure-GenericProjectFiles {
    param([string]$RepoPath)

    $settingsFiles = Get-ChildItem -Path $RepoPath -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -in @('settings.gradle', 'settings.gradle.kts') }

    foreach ($settingsFile in $settingsFiles) {
        $projectDir = $settingsFile.Directory.FullName
        $projectFile = Join-Path $projectDir '.project'
        if (-not (Test-Path $projectFile)) {
            New-BuildshipProjectFile -ProjectDir $projectDir -ProjectName $settingsFile.Directory.Name -Comment 'Gradle root project'
        }
    }

    $buildFiles = Get-ChildItem -Path $RepoPath -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -in @('build.gradle', 'build.gradle.kts') }

    foreach ($buildFile in $buildFiles) {
        $projectDir = $buildFile.Directory.FullName
        $projectFile = Join-Path $projectDir '.project'
        if (Test-Path $projectFile) {
            continue
        }

        $projectName = Get-PortableProjectName -RepoPath $RepoPath -ProjectDir $projectDir
        New-BuildshipProjectFile -ProjectDir $projectDir -ProjectName $projectName -Comment 'Gradle subproject'
    }

    $topLevelDirs = Get-ChildItem -Path $RepoPath -Directory -ErrorAction SilentlyContinue |
        Where-Object { -not $_.Name.StartsWith('.') }

    foreach ($projectDir in $topLevelDirs) {
        $projectFile = Join-Path $projectDir.FullName '.project'
        if (Test-Path $projectFile) {
            continue
        }
        if (Test-DirectoryIsOptedInProject -ProjectDir $projectDir.FullName) {
            New-BasicProjectFile -ProjectDir $projectDir.FullName -ProjectName $projectDir.Name -Comment 'Imported folder project'
        }
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
        $candidateBat = Join-Path $dir 'gradlew.bat'
        $candidateSh = Join-Path $dir 'gradlew'
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
        Push-Location $workingDir
        try {
            & $gradlew '-q' 'eclipse'
        }
        finally {
            Pop-Location
        }
        if ($LASTEXITCODE -ne 0) {
            throw "gradlew.bat eclipse failed in $workingDir"
        }
        Ensure-GenericProjectFiles -RepoPath $RepoPath
        return
    }

    if ($gradlewSh) {
        Push-Location $workingDir
        try {
            & bash $gradlewSh '-q' 'eclipse'
        }
        finally {
            Pop-Location
        }
        if ($LASTEXITCODE -ne 0) {
            throw "gradlew eclipse failed in $workingDir"
        }
        Ensure-GenericProjectFiles -RepoPath $RepoPath
        return
    }

    Write-Warning "No Gradle wrapper found in $RepoPath. Skipping Eclipse metadata generation."
    Ensure-GenericProjectFiles -RepoPath $RepoPath
}

function Ensure-WorkspaceImporterInstalled {
    param([string]$RepoRootPath)

    $buildScript = Join-Path $RepoRootPath 'win11-portable-eclipse\tools\workspace-importer\build-workspace-importer.ps1'
    if (-not (Test-Path $buildScript)) {
        throw "Workspace importer build script not found: $buildScript"
    }

    & powershell -NoProfile -ExecutionPolicy Bypass -File $buildScript -RepoRoot $RepoRootPath
    if ($LASTEXITCODE -ne 0) {
        throw "Workspace importer build failed with exit code $LASTEXITCODE"
    }
}

function Test-WorkspaceInUse {
    param([string]$WorkspacePath)

    $workspaceLock = Join-Path $WorkspacePath '.metadata\.lock'
    if (-not (Test-Path $workspaceLock)) {
        return $false
    }

    try {
        $lockStream = [System.IO.File]::Open($workspaceLock, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        $lockStream.Close()
        return $false
    }
    catch {
        $lockInfoPath = Join-Path $WorkspacePath '.metadata\.lock_info'
        if (-not (Test-Path $lockInfoPath)) {
            return $true
        }

        $lockInfo = @{}
        foreach ($line in Get-Content -Path $lockInfoPath -ErrorAction SilentlyContinue) {
            if ($line.StartsWith('#')) {
                continue
            }

            $parts = $line.Split('=', 2)
            if ($parts.Count -eq 2) {
                $lockInfo[$parts[0].Trim()] = $parts[1].Trim()
            }
        }

        $lockHost = $lockInfo['host']
        if (-not [string]::IsNullOrWhiteSpace($lockHost) -and $lockHost -ne $env:COMPUTERNAME) {
            return $true
        }

        $processId = 0
        if ([int]::TryParse($lockInfo['process-id'], [ref]$processId) -and $processId -gt 0) {
            return [bool](Get-Process -Id $processId -ErrorAction SilentlyContinue)
        }

        return $false
    }
}

function Get-WorkspaceProjectNames {
    param([string]$WorkspacePath)

    $projectsRoot = Join-Path $WorkspacePath '.metadata\.plugins\org.eclipse.core.resources\.projects'
    if (-not (Test-Path $projectsRoot)) {
        return @()
    }

    return @(Get-ChildItem -Path $projectsRoot -Directory -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Name)
}

function Get-EclipseProjectName {
    param([string]$ProjectDir)

    $projectFile = Join-Path $ProjectDir '.project'
    if (-not (Test-Path $projectFile)) {
        throw "Missing .project file in $ProjectDir"
    }

    [xml]$projectXml = Get-Content -Path $projectFile
    $projectName = $projectXml.projectDescription.name
    if ([string]::IsNullOrWhiteSpace($projectName)) {
        throw "Could not resolve project name from $projectFile"
    }

    return $projectName.Trim()
}

function Get-EclipseProjectLocationUri {
    param([string]$ProjectDir)

    $fullPath = [System.IO.Path]::GetFullPath($ProjectDir)
    return "URI//file:/$($fullPath -replace '\\', '/')"
}

function Register-ProjectInWorkspaceMetadata {
    param(
        [string]$WorkspacePath,
        [string]$ProjectName,
        [string]$ProjectDir
    )

    $projectsRoot = Join-Path $WorkspacePath '.metadata\.plugins\org.eclipse.core.resources\.projects'
    $projectMetadataDir = Join-Path $projectsRoot $ProjectName
    New-Item -ItemType Directory -Force -Path $projectMetadataDir | Out-Null

    $locationFile = Join-Path $projectMetadataDir '.location'
    $locationUri = Get-EclipseProjectLocationUri -ProjectDir $ProjectDir
    $uriBytes = [System.Text.Encoding]::ASCII.GetBytes($locationUri)

    $header = [byte[]](0x40, 0xB1, 0x8B, 0x81, 0x23, 0xBC, 0x00, 0x14, 0x1A, 0x25, 0x96, 0xE7, 0xA3, 0x93, 0xBE, 0x1E)
    $footer = [byte[]](0xC0, 0x58, 0xFB, 0xF3, 0x23, 0xBC, 0x00, 0x14, 0x1A, 0x51, 0xF3, 0x8C, 0x7B, 0xBB, 0x77, 0xC6)
    $payloadLength = $header.Length + 2 + $uriBytes.Length + $footer.Length
    $fileLength = [Math]::Max(208, $payloadLength)
    $paddingLength = $fileLength - $payloadLength

    $lengthValue = [System.Net.IPAddress]::HostToNetworkOrder([int16]$uriBytes.Length)
    $lengthBytes = [System.BitConverter]::GetBytes($lengthValue)
    $padding = New-Object byte[] $paddingLength

    [System.IO.File]::WriteAllBytes($locationFile, $header + $lengthBytes + $uriBytes + $padding + $footer)
}

function Register-ProjectsInWorkspaceMetadata {
    param(
        [string]$WorkspacePath,
        [hashtable]$ProjectNamesByDir,
        [string[]]$ProjectDirs
    )

    foreach ($projectDir in $ProjectDirs) {
        Register-ProjectInWorkspaceMetadata -WorkspacePath $WorkspacePath -ProjectName $ProjectNamesByDir[$projectDir] -ProjectDir $projectDir
    }
}

function Wait-ForImportedProjects {
    param(
        [string]$WorkspacePath,
        [string[]]$ProjectNames,
        [int]$TimeoutSeconds = 120,
        [int]$PollIntervalSeconds = 2
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $importedProjects = Get-WorkspaceProjectNames -WorkspacePath $WorkspacePath
        $missingProjects = @($ProjectNames | Where-Object { $importedProjects -notcontains $_ })
        if ($missingProjects.Count -eq 0) {
            return $true
        }

        Start-Sleep -Seconds $PollIntervalSeconds
    } while ((Get-Date) -lt $deadline)

    return $false
}

function Import-ProjectsIntoEclipse {
    param(
        [string]$RepoRootPath,
        [string]$WorkspacePath
    )

    $eclipseExe = Join-Path $RepoRootPath 'portable\eclipse-win\eclipse.exe'
    if (-not (Test-Path $eclipseExe)) {
        throw "Eclipse executable not found: $eclipseExe"
    }

    $reposPath = Join-Path $RepoRootPath 'portable\repos'
    if (-not (Test-Path $reposPath)) {
        throw "Repos path not found: $reposPath"
    }

    if (Test-WorkspaceInUse -WorkspacePath $WorkspacePath) {
        throw "Workspace appears to be in use: $WorkspacePath. Please close Eclipse and retry."
    }

    $projectDirs = Get-ChildItem -Path $reposPath -Recurse -File -Filter '.project' -ErrorAction SilentlyContinue |
        ForEach-Object { $_.Directory.FullName } |
        Sort-Object -Unique

    if (-not $projectDirs -or $projectDirs.Count -eq 0) {
        Write-Warning "No .project files found under $reposPath. Nothing to import."
        return
    }

    $projectNamesByDir = @{}
    foreach ($projectDir in $projectDirs) {
        $projectNamesByDir[$projectDir] = Get-EclipseProjectName -ProjectDir $projectDir
    }

    $eclipsecExe = Join-Path $RepoRootPath 'portable\eclipse-win\eclipsec.exe'
    $launcherExe = if (Test-Path $eclipsecExe) { $eclipsecExe } else { $eclipseExe }
    $headlessApp = 'de.geograt.eclipse.workspaceimporter.application'

    Ensure-WorkspaceImporterInstalled -RepoRootPath $RepoRootPath

    $batchSize = 20
    $timeoutSeconds = 120
    for ($i = 0; $i -lt $projectDirs.Count; $i += $batchSize) {
        $upper = [Math]::Min($i + $batchSize - 1, $projectDirs.Count - 1)
        $batch = @($projectDirs[$i..$upper])
        $expectedProjectNames = @($batch | ForEach-Object { $projectNamesByDir[$_] })

        $importArgs = @(
            '-nosplash',
            '-consoleLog',
            '-application', $headlessApp,
            '-data', $WorkspacePath
        )
        foreach ($projectDir in $batch) {
            $importArgs += @('-importProject', $projectDir)
        }
        $importArgs += @(
            '-vmargs',
            '--add-opens=java.base/java.util=ALL-UNNAMED',
            '--add-opens=java.base/java.lang=ALL-UNNAMED',
            '--add-opens=java.base/java.lang.reflect=ALL-UNNAMED',
            '--add-opens=java.base/java.text=ALL-UNNAMED',
            '--add-opens=java.desktop/java.awt.font=ALL-UNNAMED'
        )

        $proc = Start-Process -FilePath $launcherExe -ArgumentList $importArgs -NoNewWindow -PassThru
        try {
            Wait-Process -Id $proc.Id -Timeout $timeoutSeconds -ErrorAction Stop
        }
        catch {
            if (-not $proc.HasExited) {
                Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
            }
            throw "Workspace importer timed out in batch starting at index $i"
        }

        $importCompleted = Wait-ForImportedProjects -WorkspacePath $WorkspacePath -ProjectNames $expectedProjectNames -TimeoutSeconds 10 -PollIntervalSeconds 1
        if ((-not $importCompleted) -and ($proc.ExitCode -ne 0)) {
            throw "Workspace importer failed in batch starting at index $i with exit code $($proc.ExitCode)"
        }

        if (-not $importCompleted) {
            $importedProjects = Get-WorkspaceProjectNames -WorkspacePath $WorkspacePath
            $missingProjects = @($expectedProjectNames | Where-Object { $importedProjects -notcontains $_ })
            throw "Workspace importer did not register all projects in batch starting at index $i. Missing projects: $($missingProjects -join ', ')"
        }
    }
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Resolve-RepoRoot -ScriptPath $scriptDir
$manifestPath = Join-Path $root 'repos-manifest.txt'
$cloneScript = Join-Path $root 'win11-portable-eclipse\scripts\clone-repos.ps1'

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# Format: <git-url>|<branch>|<target-subdir-under-portable/repos>') | Out-Null
$lines.Add('# Generated by win11-portable-eclipse/scripts/setup-projects.ps1') | Out-Null
$lines.Add('') | Out-Null

Add-ManifestEntry -List $lines -RepoUrl $MasterRepoUrl -Branch $MasterBranch -TargetDir $MasterTargetDir
Add-ManifestEntry -List $lines -RepoUrl $SubRepoUrl1 -Branch $SubBranch1 -TargetDir $SubTargetDir1
Add-ManifestEntry -List $lines -RepoUrl $SubRepoUrl2 -Branch $SubBranch2 -TargetDir $SubTargetDir2

Set-Content -Path $manifestPath -Value $lines -Encoding UTF8

if ($DisableSaros -and $EnableSaros) {
    throw 'Use either -DisableSaros or -EnableSaros, not both.'
}

if ($DisableSaros) {
    Set-SarosEnabled -RepoRootPath $root -Enabled:$false
}

if ($EnableSaros) {
    Set-SarosEnabled -RepoRootPath $root -Enabled:$true
}

if (-not $SkipSync) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $cloneScript -RepoRoot $root -ManifestPath $manifestPath
    if ($LASTEXITCODE -ne 0) {
        throw "clone-repos.ps1 failed with exit code $LASTEXITCODE"
    }
}

if ($GenerateEclipseProjects) {
    $reposRoot = Join-Path $root 'portable\repos'

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
        Join-Path $root 'portable\workspace-win'
    } else {
        $WorkspacePath
    }
    New-Item -ItemType Directory -Force -Path $workspace | Out-Null
    Import-ProjectsIntoEclipse -RepoRootPath $root -WorkspacePath $workspace
}
