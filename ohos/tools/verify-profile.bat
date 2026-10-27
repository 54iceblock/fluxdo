@echo off
setlocal
set LIB=C:\Users\iceblock\DevEcoStudio\sdk\default\openharmony\toolchains\lib
set W=C:\Users\iceblock\fluxdo\.cache\signing
set JAVA=C:\Users\iceblock\DevEcoStudio\jbr\bin\java.exe
"%JAVA%" -jar "%LIB%\hap-sign-tool.jar" verify-profile -inFile "%W%\profile.p7b" -outFile "%W%\verify.json"
echo EXITCODE=%ERRORLEVEL%
