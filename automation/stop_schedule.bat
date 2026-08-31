@echo off
:: stop_schedule.bat
:: Disables the LebanonTrafficMonitor scheduled task WITHOUT deleting it.
:: You can re-enable it at any time by running start_schedule.bat.
:: Must be run as Administrator.

echo ============================================
echo  Lebanon Traffic Monitor — STOP Scheduler
echo ============================================
echo.

net session >nul 2>&1
if errorlevel 1 (
    echo [ERROR] This script must be run as Administrator.
    echo         Right-click stop_schedule.bat ^> Run as administrator
    pause
    exit /b 1
)

:: Check task exists
schtasks /query /tn "LebanonTrafficMonitor" >nul 2>&1
if errorlevel 1 (
    echo [INFO] Task "LebanonTrafficMonitor" does not exist — nothing to stop.
    pause
    exit /b 0
)

:: Disable (not delete) the task so it can be re-enabled easily
schtasks /change /tn "LebanonTrafficMonitor" /disable >nul
if errorlevel 1 (
    echo [ERROR] Failed to disable the task.
    pause
    exit /b 1
)

echo [OK] Scheduler is now DISABLED.
echo      The pipeline will no longer run automatically.
echo      Your database and data are untouched.
echo.
echo      To re-enable it, run: start_schedule.bat
echo      To run it manually right now: double-click run_pipeline.bat
echo.
pause
