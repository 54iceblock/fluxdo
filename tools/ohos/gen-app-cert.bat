@echo off
setlocal
if not defined DEVECO_HOME set "DEVECO_HOME=C:\Program Files\Huawei\DevEco Studio"
if not defined FLUXDO_WS set "FLUXDO_WS=%~dp0..\.."
set LIB=%DEVECO_HOME%\sdk\default\openharmony\toolchains\lib
set W=%FLUXDO_WS%\.cache\signing
set JAVA=%DEVECO_HOME%\jbr\bin\java.exe
"%JAVA%" -jar "%LIB%\hap-sign-tool.jar" generate-app-cert -keyAlias "openharmony application release" -keyPwd 123456 -issuer "C=CN,O=OpenHarmony,OU=OpenHarmony Team,CN=OpenHarmony Application CA" -issuerKeyAlias "openharmony application ca" -issuerKeyPwd 123456 -subject "C=CN,O=OpenHarmony,OU=OpenHarmony Team,CN=OpenHarmony Application Release" -validity 3650 -signAlg SHA256withECDSA -rootCaCertFile "%W%\app-root.cer" -subCaCertFile "%W%\app-ca.cer" -keystoreFile "%LIB%\OpenHarmony.p12" -keystorePwd 123456 -outForm certChain -outFile "%W%\app-cert-chain-gen.pem"
echo EXITCODE=%ERRORLEVEL%
