@echo off
setlocal
rem 口令：调试密钥库公开口令 123456 兜底；换正式证书后用 FLUXDO_SIGN_PWD 传真实口令。
if not defined FLUXDO_SIGN_PWD set "FLUXDO_SIGN_PWD=123456"
set LIB=C:\Users\iceblock\DevEcoStudio\sdk\default\openharmony\toolchains\lib
set W=C:\Users\iceblock\fluxdo\.cache\signing
set JAVA=C:\Users\iceblock\DevEcoStudio\jbr\bin\java.exe
set CERT=%~3
if "%CERT%"=="" set CERT=%W%\app-cert-chain.pem
"%JAVA%" -jar "%LIB%\hap-sign-tool.jar" sign-app -mode localSign -keyAlias "openharmony application release" -keyPwd %FLUXDO_SIGN_PWD% -appCertFile "%CERT%" -profileFile "%W%\profile.p7b" -inFile "%~1" -signAlg SHA256withECDSA -keystoreFile "%LIB%\OpenHarmony.p12" -keystorePwd %FLUXDO_SIGN_PWD% -outFile "%~2"
echo EXITCODE=%ERRORLEVEL%
