@echo off
:: start_schedule.bat
:: Enables the LebanonTrafficMonitor scheduled task (runs every 15 minutes).
:: Must be run as Administrator.

echo ============================================
echo  Lebanon Traffic Monitor — START Scheduler
echo ============================================
echo.

net session >nul 2>&1
if errorlevel 1 (
    echo [ERROR] This script must be run as Administrator.
    echo         Right-click start_schedule.bat ^> Run as administrator
    pause
    exit /b 1
)

:: Check if task exists — if not, register it first
schtasks /query /tn "LebanonTrafficMonitor" >nul 2>&1
if errorlevel 1 (
    echo [INFO] Task not found. Registering from XML...
    set "XML=%~dp0schedule_pipeline.xml"
    if not exist "%XML%" (
        echo [ERROR] schedule_pipeline.xml not found at: %XML%
        pause
        exit /b 1
    )
    schtasks /create /xml "%XML%" /tn "LebanonTrafficMonitor" /f >nul
    if errorlevel 1 (
        echo [ERROR] Failed to register task. Check the XML file.
        pause
        exit /b 1
    )
    echo [OK] Task registered.
)

:: Enable the task
schtasks /change /tn "LebanonTrafficMonitor" /enable >nul
if errorlevel 1 (
    echo [ERROR] Failed to enable the task.
    pause
    exit /b 1
)

echo [OK] Scheduler is now ENABLED.
echo      The pipeline will run automatically every 15 minutes.
echo.
echo      To stop it at any time, run: stop_schedule.bat
echo      To run it manually right now: double-click run_pipeline.bat
echo.
pause
