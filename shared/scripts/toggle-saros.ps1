[CmdletBinding()]
param(
    [ValidateSet("enable", "disable")]
    [string]$Mode,
    [string]$RepoRoot
)

$ErrorActionPreference = 'Stop'

function Resolve-RepoRoot {
    param([string]$ScriptPath)
    if ($RepoRoot) {
        return (Resolve-Path $RepoRoot).Path
    }
    return (Resolve-Path (Join-Path $ScriptPath "..\..")).Path
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

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Resolve-RepoRoot -ScriptPath $scriptDir

if ($Mode -eq "enable") {
    Set-SarosEnabled -RepoRootPath $root -Enabled:$true
}
else {
    Set-SarosEnabled -RepoRootPath $root -Enabled:$false
}

