[CmdletBinding()]
param(
    [string]$RepoRoot
)

$ErrorActionPreference = 'Stop'

function Get-RepoRoot {
    param([string]$ScriptPath)

    if ($RepoRoot) {
        return (Resolve-Path $RepoRoot).Path
    }

    return (Resolve-Path (Join-Path $ScriptPath '..\..')).Path
}

function Get-SinglePluginJar {
    param(
        [string]$PluginsDir,
        [string]$Prefix
    )

    $match = Get-ChildItem -Path $PluginsDir -Filter "$Prefix*.jar" -ErrorAction Stop |
        Sort-Object Name -Descending |
        Select-Object -First 1

    if (-not $match) {
        throw "Required Eclipse plugin not found: $Prefix"
    }

    return $match.FullName
}

function Resolve-JavaTool {
    param(
        [string]$PreferredPath,
        [string]$CommandName
    )

    if ($PreferredPath -and (Test-Path $PreferredPath)) {
        return $PreferredPath
    }

    $command = Get-Command $CommandName -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    throw "$CommandName not found."
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Get-RepoRoot -ScriptPath $scriptDir
$portableRoot = Join-Path $root 'portable'
$eclipseHome = Join-Path $portableRoot 'eclipse-win'
$pluginsDir = Join-Path $eclipseHome 'plugins'
$dropinsDir = Join-Path $eclipseHome 'dropins'
$sourceRoot = Join-Path $scriptDir 'src'
$buildRoot = Join-Path $scriptDir 'build'
$classesDir = Join-Path $buildRoot 'classes'
$stagingDir = Join-Path $buildRoot 'staging'
$distDir = Join-Path $scriptDir 'dist'
$manifestFile = Join-Path $scriptDir 'META-INF\MANIFEST.MF'
$pluginXml = Join-Path $scriptDir 'plugin.xml'
$jarName = 'local.win11.portableeclipse.workspaceimporter_1.0.0.jar'
$jarPath = Join-Path $distDir $jarName
$javacExe = Resolve-JavaTool -PreferredPath (Join-Path $eclipseHome 'jre\bin\javac.exe') -CommandName 'javac'
$jarExe = Resolve-JavaTool -PreferredPath (Join-Path $eclipseHome 'jre\bin\jar.exe') -CommandName 'jar'

$compileDeps = @(
    'org.eclipse.core.runtime_',
    'org.eclipse.core.resources_',
    'org.eclipse.equinox.app_',
    'org.eclipse.buildship.core_',
    'org.eclipse.jdt.core_',
    'org.eclipse.osgi_',
    'org.eclipse.equinox.common_',
    'org.eclipse.core.jobs_',
    'org.eclipse.core.contenttype_',
    'org.eclipse.core.expressions_',
    'org.eclipse.core.filesystem_',
    'org.eclipse.equinox.preferences_',
    'org.eclipse.jdt.core.compiler.batch_',
    'org.eclipse.core.variables_'
) | ForEach-Object { Get-SinglePluginJar -PluginsDir $pluginsDir -Prefix $_ }

$classpath = [string]::Join(';', $compileDeps)
$sourcesFile = Join-Path $buildRoot 'sources.txt'

if (Test-Path $buildRoot) {
    Remove-Item -Recurse -Force $buildRoot
}
if (Test-Path $distDir) {
    Remove-Item -Recurse -Force $distDir
}

New-Item -ItemType Directory -Force -Path $classesDir, $stagingDir, $distDir, $dropinsDir, $buildRoot | Out-Null

$javaSources = Get-ChildItem -Path $sourceRoot -Recurse -Filter '*.java' | Select-Object -ExpandProperty FullName
Set-Content -Path $sourcesFile -Value $javaSources -Encoding ASCII
$javacArgs = @(
    '-cp',
    $classpath,
    '-d',
    $classesDir,
    "@$sourcesFile"
)
& $javacExe @javacArgs
if ($LASTEXITCODE -ne 0) {
    throw "javac failed with exit code $LASTEXITCODE"
}

Copy-Item -Recurse -Force (Join-Path $classesDir '*') $stagingDir
New-Item -ItemType Directory -Force -Path (Join-Path $stagingDir 'META-INF') | Out-Null
Copy-Item -Force $manifestFile (Join-Path $stagingDir 'META-INF\MANIFEST.MF')
Copy-Item -Force $pluginXml (Join-Path $stagingDir 'plugin.xml')

Push-Location $stagingDir
try {
    & $jarExe 'cfm' $jarPath 'META-INF\MANIFEST.MF' '.'
}
finally {
    Pop-Location
}

if ($LASTEXITCODE -ne 0) {
    throw "jar creation failed with exit code $LASTEXITCODE"
}

Copy-Item -Force $jarPath (Join-Path $dropinsDir $jarName)
Write-Host "Workspace importer installed: $(Join-Path $dropinsDir $jarName)"
