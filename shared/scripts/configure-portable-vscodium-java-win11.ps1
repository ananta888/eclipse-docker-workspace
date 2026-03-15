[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$SettingsPath
)

$ErrorActionPreference = 'Stop'

function Get-RepoRoot {
    param([string]$ScriptPath)
    if ($RepoRoot) {
        return (Resolve-Path $RepoRoot).Path
    }

    return (Resolve-Path (Join-Path $ScriptPath "..\..")).Path
}

function Get-Java21Home {
    $candidates = New-Object System.Collections.Generic.List[string]

    foreach ($envVar in @('JAVA_HOME', 'JDK_HOME')) {
        $value = [Environment]::GetEnvironmentVariable($envVar, 'Process')
        if (-not $value) { $value = [Environment]::GetEnvironmentVariable($envVar, 'User') }
        if (-not $value) { $value = [Environment]::GetEnvironmentVariable($envVar, 'Machine') }
        if ($value) {
            $candidates.Add($value) | Out-Null
        }
    }

    foreach ($baseDir in @('C:\Program Files\Eclipse Adoptium', 'C:\Program Files\AdoptOpenJDK', 'C:\Program Files\Microsoft', 'C:\Program Files\Java')) {
        if (-not (Test-Path $baseDir)) { continue }
        Get-ChildItem -Path $baseDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.Name -match 'jdk-?21|temurin-?21|microsoft-?21|openjdk-?21') {
                $candidates.Add($_.FullName) | Out-Null
            }
        }
    }

    foreach ($candidate in $candidates | Select-Object -Unique) {
        $javaExe = Join-Path $candidate 'bin\java.exe'
        if (-not (Test-Path $javaExe)) { continue }

        $versionOutput = & $javaExe '-version' 2>&1
        if ($LASTEXITCODE -ne 0) { continue }
        if (($versionOutput | Out-String) -match 'version "21(\.|")') {
            return $candidate
        }
    }

    return $null
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$resolvedRepoRoot = Get-RepoRoot -ScriptPath $scriptDir

if (-not $SettingsPath) {
    $SettingsPath = Join-Path $resolvedRepoRoot 'portable\vscodium-win\data\user-data\User\settings.json'
}

if (-not (Test-Path $SettingsPath)) {
    throw "Settings file not found: $SettingsPath"
}

$javaHome = Get-Java21Home
if (-not $javaHome) {
    Write-Warning 'No Java 21 installation detected. Keeping existing VSCodium Java settings.'
    return
}

$settings = Get-Content -Path $SettingsPath -Raw | ConvertFrom-Json

$settings.'java.configuration.runtimes' = @(
    @{
        name = 'JavaSE-21'
        path = $javaHome
        default = $true
    }
)
$settings.'java.import.gradle.java.home' = $javaHome
$settings.'spring-boot.ls.java.home' = $javaHome

$updatedJson = $settings | ConvertTo-Json -Depth 10
Set-Content -Path $SettingsPath -Value $updatedJson -Encoding UTF8

Write-Host "Configured VSCodium Java 21 home: $javaHome"
