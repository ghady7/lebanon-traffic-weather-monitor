@echo off
setlocal EnableDelayedExpansion

:: ============================================================
::  run_pipeline.bat — Lebanon Traffic & Weather Monitor
::  Full end-to-end pipeline:
::    1. Fetch live traffic + weather data (Python)
::    2. Deploy SQL stored procedures
::    3. Transform staging → star schema
::    4. Validate star schema integrity
::    5. Train ML model (skipped if < 50 rows)
::    6. Generate 7-day predictions
::    7. Log pipeline run to database
:: ============================================================

:: ─────────────────────── PATHS ───────────────────────
set "ROOT=%~dp0"
set "PYTHON=%ROOT%traffic_ml_env\Scripts\python.exe"
set "SQLCMD=C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\180\Tools\Binn\SQLCMD.EXE"
set "SQL_SERVER=localhost"
set "SQL_DATABASE=lebanon_traffic_weather"

:: Log directory and timestamped log file
set "LOG_DIR=%ROOT%logs"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"
set "DT=%date:~-4%%date:~4,2%%date:~7,2%_%time:~0,2%%time:~3,2%%time:~6,2%"
set "DT=%DT: =0%"
set "LOG_FILE=%LOG_DIR%\pipeline_%DT%.log"

:: ─────────────────────── PREREQ CHECKS ───────────────────────
if not exist "%PYTHON%" (
    echo [ERROR] Python venv not found: %PYTHON%
    echo         Run: python -m venv traffic_ml_env ^&^& traffic_ml_env\Scripts\pip install -r data_pipeline\requirements.txt
    exit /b 1
)
if not exist "%SQLCMD%" (
    echo [ERROR] SQLCMD not found: %SQLCMD%
    echo         Install ODBC Driver 18 + SQLCMD from Microsoft.
    exit /b 1
)

:: Check for --mock flag (first argument)
set "MOCK_FLAG="
if /i "%~1"=="--mock" set "MOCK_FLAG=--mock"

call :log "========================================="
call :log " Lebanon Traffic Monitor — Pipeline START"
if defined MOCK_FLAG call :log " ** MOCK MODE — no live API calls **"
call :log "========================================="

:: ─────────────────────── STEP 1: FETCH DATA ───────────────────────
call :log "STEP 1/7 — Fetching live traffic + weather data..."
"%PYTHON%" "%ROOT%data_pipeline\multi_route_cached.py" %MOCK_FLAG% >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    call :log "ERROR in STEP 1: Data extraction failed. Check %LOG_FILE% for details."
    exit /b 1
)
call :log "STEP 1/7 — Done."

:: ─────────────────────── STEP 2: DEPLOY SQL PROCEDURES ───────────────────────
call :log "STEP 2/7 — Deploying SQL stored procedures..."

"%SQLCMD%" -S "%SQL_SERVER%" -E -d "%SQL_DATABASE%" -C -b -i "%ROOT%database\05_transform.sql" >> "%LOG_FILE%" 2>&1
if errorlevel 1 ( call :log "ERROR: 05_transform.sql failed." & exit /b 1 )

"%SQLCMD%" -S "%SQL_SERVER%" -E -d "%SQL_DATABASE%" -C -b -i "%ROOT%database\06_validation.sql" >> "%LOG_FILE%" 2>&1
if errorlevel 1 ( call :log "ERROR: 06_validation.sql failed." & exit /b 1 )

"%SQLCMD%" -S "%SQL_SERVER%" -E -d "%SQL_DATABASE%" -C -b -i "%ROOT%database\10_create_pipeline_run_log.sql" >> "%LOG_FILE%" 2>&1
if errorlevel 1 ( call :log "ERROR: 10_create_pipeline_run_log.sql failed." & exit /b 1 )

"%SQLCMD%" -S "%SQL_SERVER%" -E -d "%SQL_DATABASE%" -C -b -i "%ROOT%database\12_create_fact_predictions.sql" >> "%LOG_FILE%" 2>&1
if errorlevel 1 ( call :log "ERROR: 12_create_fact_predictions.sql failed." & exit /b 1 )

call :log "STEP 2/7 — Done."

:: ─────────────────────── STEP 3: ETL TRANSFORM ───────────────────────
call :log "STEP 3/7 — Transforming staging data into star schema..."
"%SQLCMD%" -S "%SQL_SERVER%" -E -d "%SQL_DATABASE%" -C -b -Q "EXEC dbo.usp_transform_staging_to_star;" >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    call :log "ERROR in STEP 3: usp_transform_staging_to_star failed."
    exit /b 1
)
call :log "STEP 3/7 — Done."

:: ─────────────────────── STEP 4: VALIDATE ───────────────────────
call :log "STEP 4/7 — Validating star schema integrity..."
"%SQLCMD%" -S "%SQL_SERVER%" -E -d "%SQL_DATABASE%" -C -Q "EXEC dbo.usp_validate_star_schema;" >> "%LOG_FILE%" 2>&1
call :log "STEP 4/7 — Done (validation output in log)."

:: ─────────────────────── STEP 5: ML TRAINING ───────────────────────
call :log "STEP 5/7 — Training ML model (requires >= 50 fact rows)..."
set "ML_TRAIN_RC=0"
"%PYTHON%" "%ROOT%machine_learning\train_model.py" --min-rows 50 >> "%LOG_FILE%" 2>&1
set "ML_TRAIN_RC=%errorlevel%"

if "%ML_TRAIN_RC%"=="2" (
    call :log "STEP 5/7 — Skipped: not enough data collected yet. Keep the pipeline running."
)
if "%ML_TRAIN_RC%"=="0" (
    call :log "STEP 5/7 — Model trained and saved to machine_learning\model.pkl"
)
if "%ML_TRAIN_RC%"=="1" (
    call :log "WARNING in STEP 5: ML training encountered an error — continuing without model update."
    set "ML_TRAIN_RC=99"
)

:: ─────────────────────── STEP 6: GENERATE PREDICTIONS ───────────────────────
if "%ML_TRAIN_RC%"=="0" (
    call :log "STEP 6/7 — Generating 7-day predictions into dbo.fact_predictions..."
    "%PYTHON%" "%ROOT%machine_learning\generate_predictions.py" --days 7 >> "%LOG_FILE%" 2>&1
    if errorlevel 1 (
        call :log "WARNING in STEP 6: Prediction generation failed — pipeline continues."
    ) else (
        call :log "STEP 6/7 — Done."
    )
) else (
    call :log "STEP 6/7 — Skipped (no trained model available)."
)

:: ─────────────────────── STEP 7: LOG PIPELINE RUN ───────────────────────
call :log "STEP 7/7 — Recording pipeline run in database..."
"%SQLCMD%" -S "%SQL_SERVER%" -E -d "%SQL_DATABASE%" -C -Q ^
    "EXEC dbo.usp_record_pipeline_run @pipeline_run_id=N'bat_run_%DT%', @status=N'success', @mock_mode=0;" ^
    >> "%LOG_FILE%" 2>&1
call :log "STEP 7/7 — Done."

:: ─────────────────────── CLEANUP: KEEP LAST 30 LOGS ───────────────────────
set "DEL_COUNT=0"
for /f "skip=30 delims=" %%F in ('dir /b /o-d "%LOG_DIR%\pipeline_*.log" 2^>nul') do (
    del "%LOG_DIR%\%%F" 2>nul
    set /a DEL_COUNT+=1
)

call :log "========================================="
call :log " Pipeline COMPLETE — Log: %LOG_FILE%"
call :log "========================================="
exit /b 0

:: ─────────────────────── HELPER ───────────────────────
:log
echo [%date% %time%] %~1
echo [%date% %time%] %~1 >> "%LOG_FILE%"
goto :eof
