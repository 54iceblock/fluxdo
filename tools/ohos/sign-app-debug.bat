@echo off
setlocal
if not defined DEVECO_HOME set "DEVECO_HOME=C:\Program Files\Huawei\DevEco Studio"
if not defined FLUXDO_WS set "FLUXDO_WS=%~dp0..\.."
set LIB=%DEVECO_HOME%\sdk\default\openharmony\toolchains\lib
set W=%FLUXDO_WS%\.cache\signing
set JAVA=%DEVECO_HOME%\jbr\bin\java.exe
"%JAVA%" -jar "%LIB%\hap-sign-tool.jar" sign-app -mode localSign -keyAlias "openharmony application release" -keyPwd 123456 -appCertFile "%~3" -profileFile "%W%\profile.p7b" -inFile "%~1" -signAlg SHA256withECDSA -keystoreFile "%LIB%\OpenHarmony.p12" -keystorePwd 123456 -outFile "%~2" > "%W%\signapp.log" 2>&1
echo EXITCODE=%ERRORLEVEL%
