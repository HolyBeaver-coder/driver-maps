@echo off
rem =====================================================================
rem  build_package.bat - Sobranie i podpisanie paketa draivera
rem  Genius SPEED WHEEL RV FF (VID_0458&PID_3017) dlya Windows 11 x64
rem
rem  Trebovaniya: Windows SDK (inf2cat.exe, signtool.exe) ili WDK.
rem  Zapuskat ot administratora v папke package\Genius_SpeedWheelRVFF.
rem =====================================================================
setlocal EnableExtensions
pushd "%~dp0"

set INF_NAME=HID_RF_3017.inf
set CAT_NAME=HID_RF_3017.cat
set CERT_NAME=GeniusWheelTestCert
set OUT_DIR=%~dp0output

echo.
echo [1/6] Proverka isodnyh faylov...
for %%F in (%INF_NAME% dyncal64.sys rfvibra64.dll rfvibra264.dll rfcplsvr64.dll) do (
    if not exist "%%F" (
        echo   OSHIBKA: ne nayden fayl %%F
        goto :fail
    )
    echo   OK: %%F
)

echo.
echo [2/6] Sozdanie vyhodnoy papki...
if exist "%OUT_DIR%" rd /s /q "%OUT_DIR%"
md "%OUT_DIR%"
copy /y %INF_NAME% dyncal64.sys rfvibra64.dll rfvibra264.dll rfcplsvr64.dll "%OUT_DIR%\" >nul
if errorlevel 1 goto :fail

echo.
echo [3/6] Generaciya samopodpisannogo sertifikata (%CERT_NAME%)...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
 "$existing = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -eq 'CN=%CERT_NAME%' };" ^
 "if (-not $existing) {" ^
 " $c = New-SelfSignedCertificate -Type CodeSigningCert -Subject 'CN=%CERT_NAME%' -CertStoreLocation Cert:\LocalMachine\My -HashAlgorithm SHA256 -KeyLength 2048 -NotAfter (Get-Date).AddYears(5);" ^
 " $pwd = ConvertTo-SecureString -String 'TempPass1!' -Force -AsPlainText;" ^
 " Export-PfxCertificate -Cert $c -FilePath '%OUT_DIR%\%CERT_NAME%.pfx' -Password $pwd | Out-Null;" ^
 " Export-Certificate -Cert $c -FilePath '%OUT_DIR%\%CERT_NAME%.cer' | Out-Null;" ^
 " Write-Host '   Sertifikat sozdan; otdachka: TempPass1!'; } else { Write-Host '   Sertifikat uzhe est v LocalMachine\My.' }"
if errorlevel 1 goto :fail

echo.
echo [4/6] Sozdanie kataloga .cat (inf2cat)...
where inf2cat >nul 2>&1
if errorlevel 1 (
    echo   OSHIBKA: inf2cat.exe ne nayden v PATH.
    echo   Ustanovite Windows SDK ili dodavte put, napr.:
    echo   set PATH=%%^"C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x86%%^";%%PATH%%
    goto :fail
)
inf2cat /driver:"%OUT_DIR%" /os:10_x64,11_x64 /verbose
if errorlevel 1 (
    echo   OSHIBKA: inf2cat ne sozdal katalog. Prover'te sintaksis INF.
    goto :fail
)

echo.
echo [5/6] Podpisanie kataloga i INF (signtool)...
where signtool >nul 2>&1
if errorlevel 1 (
    echo   OSHIBKA: signtool.exe ne nayden v PATH (Windows SDK/WDK).
    goto :fail
)
for /f "delims=" %%T in ('powershell -NoProfile -Command "(Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -eq 'CN=%CERT_NAME%' } | Select-Object -First 1).Thumbprint"') do set THUMB=%%T
if "%THUMB%"=="" (
    echo   OSHIBKA: ne udalos poluchit otpechatok sertifikata.
    goto :fail
)
signtool sign /v /sha1 %THUMB% /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 "%OUT_DIR%\%CAT_NAME%"
if errorlevel 1 goto :fail
signtool sign /v /sha1 %THUMB% /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 "%OUT_DIR%\%INF_NAME%"
if errorlevel 1 goto :fail

echo.
echo [6/6] Gotovo. Paket v papke:
echo   %OUT_DIR%
echo.
echo Dalshe na TSELEVOY mashine (Windows 11):
echo   1. vklyuchit Test Mode:  bcdedit /set testsigning on  ^& reboot
echo   2. ustanovit koren sertifikata:  certutil -addstore -f TRUSTEDPUBLISHER %CERT_NAME%.cer
echo      (ili dvoynym klikom na .cer -Ustanovit'-^> "Doveryt'sya vsemu")
echo   3. ustanovit draiver:    pnputil /add-driver %INF_NAME% /install
echo.
goto :end

:fail
echo.
echo *** SBORKA PRERVANA IZ-ZA OSHIBKI ***
popd
exit /b 1

:end
popd
endlocal
