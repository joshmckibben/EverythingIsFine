@echo off
rem Double-click launcher for Windows: runs the checks in PowerShell 7 and keeps the window open.
where pwsh >/dev/null 2>nul
if errorlevel 1 (
    echo PowerShell 7 ^(pwsh^) was not found. Install it with:
    echo     winget install --id Microsoft.PowerShell
    echo.
    pause
    exit /b 1
)
pwsh -NoProfile -File "%~dp0Invoke-Checks.ps1"
echo.
pause
