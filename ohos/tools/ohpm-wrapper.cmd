@echo off
setlocal
set "NODE_OPTIONS=--max-old-space-size=8192"
set "DEVECO_NODE=C:\Users\iceblock\DevEcoStudio\tools\node\node.exe"
set "OHPM_CLI=C:\Users\iceblock\DevEcoStudio\tools\ohpm\bin\pm-cli.js"
if not exist "%DEVECO_NODE%" exit /b 1
if not exist "%OHPM_CLI%" exit /b 1
"%DEVECO_NODE%" "%OHPM_CLI%" %*
exit /b %ERRORLEVEL%
