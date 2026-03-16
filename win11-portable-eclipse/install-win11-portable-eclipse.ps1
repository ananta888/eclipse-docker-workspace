[CmdletBinding()]
param(
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
    [string]$UbuntuDistribution = 'Ubuntu',
    [switch]$SkipWslSetup,
    [switch]$SkipRepoSetup,
    [switch]$SkipPluginInstall,
    [switch]$SkipPreferenceImport
)

$ErrorActionPreference = 'Stop'
$script:OriginalBoundParameters = @{} + $PSBoundParameters

function Resolve-RepoRoot {
    param([string]$ScriptPath)
    if ($RepoRoot) {
        return (Resolve-Path $RepoRoot).Path
    }

    return (Resolve-Path (Join-Path $ScriptPath '..')).Path
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-CommandAvailable {
    param([string]$CommandName)

    return [bool](Get-Command $CommandName -ErrorAction SilentlyContinue)
}

function Get-ScriptInvocationArgs {
    $argsList = New-Object System.Collections.Generic.List[string]
    $argsList.Add('-NoProfile') | Out-Null
    $argsList.Add('-ExecutionPolicy') | Out-Null
    $argsList.Add('Bypass') | Out-Null
    $argsList.Add('-File') | Out-Null
    $argsList.Add($PSCommandPath) | Out-Null

    foreach ($entry in $script:OriginalBoundParameters.GetEnumerator()) {
        $key = "-$($entry.Key)"
        $value = $entry.Value

        if ($value -is [System.Management.Automation.SwitchParameter]) {
            if ($value.IsPresent) {
                $argsList.Add($key) | Out-Null
            }
            continue
        }

        if ($null -eq $value) {
            continue
        }

        $argsList.Add($key) | Out-Null
        $argsList.Add([string]$value) | Out-Null
    }

    return $argsList.ToArray()
}

function Restart-Elevated {
    $argumentList = Get-ScriptInvocationArgs
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argumentList | Out-Null
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [string[]]$Arguments = @(),
        [switch]$AllowNonZeroExit
    )

    $output = & $FilePath @Arguments 2>&1
    $exitCode = $LASTEXITCODE

    if ((-not $AllowNonZeroExit) -and ($exitCode -ne 0)) {
        $details = ($output | Out-String).Trim()
        throw "Command failed: $FilePath $($Arguments -join ' ')`nExit code: $exitCode`n$details"
    }

    return @{
        Output = @($output)
        ExitCode = $exitCode
        Text = ($output | Out-String).Trim()
    }
}

function Test-UbuntuInstalled {
    param([string]$DistributionName)

    $result = Invoke-NativeCommand -FilePath 'wsl.exe' -Arguments @('--list', '--quiet') -AllowNonZeroExit
    if ($result.ExitCode -ne 0) {
        return $false
    }

    $names = $result.Output | ForEach-Object { "$_".Trim() } | Where-Object { $_ }
    return $names -contains $DistributionName
}

function Ensure-WslAndUbuntu {
    param([string]$DistributionName)

    if (-not (Test-CommandAvailable -CommandName 'wsl.exe')) {
        throw 'wsl.exe not found. This script must be run on Windows 11.'
    }

    $needElevation = $false
    $status = Invoke-NativeCommand -FilePath 'wsl.exe' -Arguments @('--status') -AllowNonZeroExit
    $statusText = $status.Text

    if ($status.ExitCode -ne 0) {
        $needElevation = $true
    }

    if (-not (Test-UbuntuInstalled -DistributionName $DistributionName)) {
        $needElevation = $true
    }

    if (-not $needElevation) {
        Write-Host "WSL and distribution '$DistributionName' already available."
        return
    }

    if (-not (Test-IsAdministrator)) {
        Write-Host 'Restarting PowerShell with Administrator rights for WSL/Ubuntu setup...'
        Restart-Elevated
        exit 0
    }

    if ($status.ExitCode -ne 0) {
        Write-Host 'Installing WSL base components...'
        $installBase = Invoke-NativeCommand -FilePath 'wsl.exe' -Arguments @('--install', '--no-distribution') -AllowNonZeroExit
        if ($installBase.ExitCode -ne 0 -and $installBase.Text -notmatch 'already installed') {
            throw "WSL base installation failed.`n$($installBase.Text)"
        }
    }

    if (-not (Test-UbuntuInstalled -DistributionName $DistributionName)) {
        Write-Host "Installing WSL distribution '$DistributionName'..."
        $installUbuntu = Invoke-NativeCommand -FilePath 'wsl.exe' -Arguments @('--install', '-d', $DistributionName) -AllowNonZeroExit
        if ($installUbuntu.ExitCode -ne 0 -and $installUbuntu.Text -notmatch 'already exists|already installed') {
            throw "Ubuntu installation failed.`n$($installUbuntu.Text)"
        }
    }

    $recheckStatus = Invoke-NativeCommand -FilePath 'wsl.exe' -Arguments @('--status') -AllowNonZeroExit
    $rebootRequired = $false

    foreach ($text in @($statusText, $recheckStatus.Text)) {
        if ($text -match 'restart|reboot|Neustart') {
            $rebootRequired = $true
        }
    }

    if ($rebootRequired) {
        throw 'WSL was installed or updated, but Windows reported that a restart is required. Reboot Windows and run the script again.'
    }

    if (-not (Test-UbuntuInstalled -DistributionName $DistributionName)) {
        throw "WSL setup finished, but distribution '$DistributionName' is still not registered."
    }

    Write-Host "WSL setup completed with distribution '$DistributionName'."
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Resolve-RepoRoot -ScriptPath $scriptDir
$bootstrapScript = Join-Path $root 'shared\scripts\bootstrap-portable-eclipse-win11.ps1'
$setupProjectsScript = Join-Path $root 'shared\scripts\setup-projects.ps1'

if (-not $SkipWslSetup) {
    Ensure-WslAndUbuntu -DistributionName $UbuntuDistribution
}
else {
    Write-Host 'Skipping WSL/Ubuntu setup.'
}

if (-not (Test-Path $bootstrapScript)) {
    throw "Bootstrap script not found: $bootstrapScript"
}

$bootstrapArgs = @{
    RepoRoot = $root
}

if ($SkipPluginInstall) {
    $bootstrapArgs.SkipPluginInstall = $true
}

if (-not $SkipPreferenceImport) {
    $bootstrapArgs.ImportPreferences = $true
}

Write-Host 'Running portable Eclipse bootstrap...'
& $bootstrapScript @bootstrapArgs
if ($LASTEXITCODE -ne 0) {
    throw "Portable Eclipse bootstrap failed with exit code $LASTEXITCODE"
}

if ($SkipRepoSetup) {
    Write-Host 'Skipping repository sync and Eclipse project import.'
    exit 0
}

if (-not (Test-Path $setupProjectsScript)) {
    throw "Project setup script not found: $setupProjectsScript"
}

if ([string]::IsNullOrWhiteSpace($MasterRepoUrl)) {
    Write-Warning 'No -MasterRepoUrl was provided. Eclipse is installed, but no repositories were cloned or imported.'
    exit 0
}

$setupArgs = @{
    RepoRoot = $root
    MasterRepoUrl = $MasterRepoUrl
    GenerateEclipseProjects = $true
    ImportIntoEclipse = $true
}

foreach ($name in @(
    'MasterBranch',
    'MasterTargetDir',
    'SubRepoUrl1',
    'SubBranch1',
    'SubTargetDir1',
    'SubRepoUrl2',
    'SubBranch2',
    'SubTargetDir2'
)) {
    $value = Get-Variable -Name $name -ValueOnly
    if (-not [string]::IsNullOrWhiteSpace($value)) {
        $setupArgs[$name] = $value
    }
}

Write-Host 'Cloning repositories, generating Gradle Eclipse metadata, and importing projects...'
& $setupProjectsScript @setupArgs
if ($LASTEXITCODE -ne 0) {
    throw "Project setup failed with exit code $LASTEXITCODE"
}

Write-Host ''
Write-Host 'Complete.'
Write-Host 'Start Eclipse with: win11-portable-eclipse\start-eclipse-win11.bat'
