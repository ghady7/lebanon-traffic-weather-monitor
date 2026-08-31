@echo off
:: schedule_status.bat
:: Shows whether the LebanonTrafficMonitor task is enabled, disabled, or not registered.
:: Does NOT require Administrator.

echo ============================================
echo  Lebanon Traffic Monitor — Scheduler Status
echo ============================================
echo.

schtasks /query /tn "LebanonTrafficMonitor" /fo LIST 2>nul | findstr /i "Status\|Next Run\|Last Run\|Task Name"
if errorlevel 1 (
    echo  Status : NOT REGISTERED
    echo.
    echo  Run automation\install_schedule.bat (as Administrator) to register it.
) else (
    echo.
    echo  To START auto-run : automation\start_schedule.bat  (as Administrator)
    echo  To STOP  auto-run : automation\stop_schedule.bat   (as Administrator)
    echo  To run NOW        : double-click run_pipeline.bat
)
echo.
pause
