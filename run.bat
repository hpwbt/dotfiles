@echo off
setlocal

set "SCRIPTS=%~dp0scripts"

chcp 65001 >nul
<nul set /p ="______      _      _    _____ " & echo.
<nul set /p ="|  _  \    | |  /\| |/\|____ |" & echo.
<nul set /p ="| | | |___ | |_ \ ` ' /    / /" & echo.
<nul set /p ="| | | / _ \| __|_     _|   \ \" & echo.
<nul set /p ="| |/ / (_) | |_ / , . \.___/ /" & echo.
<nul set /p ="|___/ \___/ \__|\/|_|\/\____/ " & echo.

rem Set the execution policy for the current user to "bypass".
powershell -NoProfile -Command "Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass -Force"

rem Set custom environmental variable.
powershell -NoProfile -File "%SCRIPTS%\env.ps1"
if errorlevel 1 (
    echo Could not set custom environmental variables.
    <nul set /p ="Press any key to quit . . . "
    pause >nul
    exit /b 1
)

rem Apply stored settings.
powershell -NoProfile -File "%SCRIPTS%\apply.ps1"
if errorlevel 1 (
    echo One or more steps failed. Check the output above.
) else (
    echo All steps succeeded.
)

echo(
echo Tasks finished.
pause
endlocal