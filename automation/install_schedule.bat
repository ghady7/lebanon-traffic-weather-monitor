@echo off
:: install_schedule.bat
:: Registers the Lebanon Traffic Monitor task with Windows Task Scheduler.
:: Must be run as Administrator.

echo ============================================
echo  Lebanon Traffic Monitor — Task Scheduler
echo ============================================
echo.

net session >nul 2>&1
if errorlevel 1 (
    echo [ERROR] This script must be run as Administrator.
    echo         Right-click install_schedule.bat and choose "Run as administrator".
    pause
    exit /b 1
)

set "XML=%~dp0schedule_pipeline.xml"
if not exist "%XML%" (
    echo [ERROR] schedule_pipeline.xml not found at: %XML%
    pause
    exit /b 1
)

schtasks /create /xml "%XML%" /tn "LebanonTrafficMonitor" /f
if errorlevel 1 (
    echo [ERROR] Failed to register the task. Check the XML file and try again.
    pause
    exit /b 1
)

echo.
echo [OK] Task "LebanonTrafficMonitor" registered successfully.
echo      It will run every 15 minutes starting 2026-09-01 at 07:00.
echo      Manage it in: Task Scheduler ^> Task Scheduler Library ^> LebanonTrafficMonitor
echo.
pause
