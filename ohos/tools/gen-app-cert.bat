@echo off
setlocal
rem 口令：OpenHarmony SDK 自带调试密钥库的口令是公开值 123456，这里作为兜底。
rem 换成正式证书后请用环境变量传入真实口令（不要写回本文件）：
rem   set FLUXDO_SIGN_PWD=^<正式密钥库口令^>
if not defined FLUXDO_SIGN_PWD set "FLUXDO_SIGN_PWD=123456"
set LIB=C:\Users\iceblock\DevEcoStudio\sdk\default\openharmony\toolchains\lib
set W=C:\Users\iceblock\fluxdo\.cache\signing
set JAVA=C:\Users\iceblock\DevEcoStudio\jbr\bin\java.exe
"%JAVA%" -jar "%LIB%\hap-sign-tool.jar" generate-app-cert -keyAlias "openharmony application release" -keyPwd %FLUXDO_SIGN_PWD% -issuer "C=CN,O=OpenHarmony,OU=OpenHarmony Team,CN=OpenHarmony Application CA" -issuerKeyAlias "openharmony application ca" -issuerKeyPwd %FLUXDO_SIGN_PWD% -subject "C=CN,O=OpenHarmony,OU=OpenHarmony Team,CN=OpenHarmony Application Release" -validity 3650 -signAlg SHA256withECDSA -rootCaCertFile "%W%\app-root.cer" -subCaCertFile "%W%\app-ca.cer" -keystoreFile "%LIB%\OpenHarmony.p12" -keystorePwd %FLUXDO_SIGN_PWD% -outForm certChain -outFile "%W%\app-cert-chain-gen.pem"
echo EXITCODE=%ERRORLEVEL%
