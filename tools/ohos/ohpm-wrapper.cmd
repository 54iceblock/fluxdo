@echo off
setlocal
if not defined DEVECO_HOME set "DEVECO_HOME=C:\Program Files\Huawei\DevEco Studio"
if not defined FLUXDO_WS set "FLUXDO_WS=%~dp0..\.."
set "NODE_OPTIONS=--max-old-space-size=8192"
set "DEVECO_NODE=%DEVECO_HOME%\tools\node\node.exe"
set "OHPM_CLI=%DEVECO_HOME%\tools\ohpm\bin\pm-cli.js"
if not exist "%DEVECO_NODE%" exit /b 1
if not exist "%OHPM_CLI%" exit /b 1
"%DEVECO_NODE%" "%OHPM_CLI%" %*
exit /b %ERRORLEVEL%
