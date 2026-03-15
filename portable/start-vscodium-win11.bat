@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
set "CODIUM_HOME=%SCRIPT_DIR%vscodium-win"
set "WORKSPACE_DIR=%SCRIPT_DIR%workspace-vscodium"
set "CODIUM_EXE=%CODIUM_HOME%\VSCodium.exe"

if not exist "%CODIUM_EXE%" (
  echo VSCodium executable not found: "%CODIUM_EXE%"
  echo Run shared\scripts\bootstrap-portable-vscodium-win11.bat first.
  exit /b 1
)

start "" "%CODIUM_EXE%" "%WORKSPACE_DIR%" %*
endlocal
