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

rem Execution policy
powershell -NoProfile -Command "Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass -Force"

rem Set custom environmental variable and apply stored settings.
powershell -NoProfile -Command ^
  "& { $ErrorActionPreference='Stop'; & '%SCRIPTS%\env.ps1'; & '%SCRIPTS%\apply.ps1' }"
if errorlevel 1 (
    echo(
    echo One or more steps failed. Check the output above.
) else (
    echo(
    echo All steps succeeded.
)

pause
endlocal
