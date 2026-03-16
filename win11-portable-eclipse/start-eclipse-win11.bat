@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
set "ECLIPSE_HOME=%SCRIPT_DIR%..\portable\eclipse-win"
set "WORKSPACE_DIR=%SCRIPT_DIR%..\portable\workspace-win"
if not exist "%ECLIPSE_HOME%\eclipse.exe" (
  echo Eclipse executable not found: "%ECLIPSE_HOME%\eclipse.exe"
  echo Run win11-portable-eclipse\install-win11-portable-eclipse.bat first.
  exit /b 1
)
start "" "%ECLIPSE_HOME%\eclipse.exe" -data "%WORKSPACE_DIR%" %*
endlocal
