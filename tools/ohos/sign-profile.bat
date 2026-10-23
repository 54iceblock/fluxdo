@echo off
setlocal
if not defined DEVECO_HOME set "DEVECO_HOME=C:\Program Files\Huawei\DevEco Studio"
if not defined FLUXDO_WS set "FLUXDO_WS=%~dp0..\.."
set LIB=%DEVECO_HOME%\sdk\default\openharmony\toolchains\lib
set W=%FLUXDO_WS%\.cache\signing
set JAVA=%DEVECO_HOME%\jbr\bin\java.exe
"%JAVA%" -jar "%LIB%\hap-sign-tool.jar" sign-profile -mode localSign -keyAlias "openharmony application profile debug" -keyPwd 123456 -profileCertFile "%LIB%\OpenHarmonyProfileDebug.pem" -inFile "%W%\profile.json" -signAlg SHA256withECDSA -keystoreFile "%LIB%\OpenHarmony.p12" -keystorePwd 123456 -outFile "%W%\profile.p7b"
echo EXITCODE=%ERRORLEVEL%
