@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
set "ECLIPSE_HOME=%SCRIPT_DIR%eclipse-win"
if "%WORKSPACE_DIR%"=="" set "WORKSPACE_DIR=%SCRIPT_DIR%workspace-win"

if not exist "%ECLIPSE_HOME%\eclipse.exe" (
  echo Eclipse executable not found: "%ECLIPSE_HOME%\eclipse.exe"
  echo Run shared\scripts\bootstrap-portable-eclipse-win11.bat first.
  exit /b 1
)

start "" "%ECLIPSE_HOME%\eclipse.exe" -data "%WORKSPACE_DIR%" %*
endlocal
