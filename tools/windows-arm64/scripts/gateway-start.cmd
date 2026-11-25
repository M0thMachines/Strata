@echo off
rem Start the Strata WoA OpenAI gateway (native ARM64 engine on :18500).
rem First run also installs and configures Hermes to talk to Strata (turnkey bootstrap).
if not exist "%LOCALAPPDATA%\StrataWoA" mkdir "%LOCALAPPDATA%\StrataWoA"

if not exist "%LOCALAPPDATA%\StrataWoA\hermes-setup.done" (
    echo [1/2] First run: installing and configuring Hermes for Strata...
    echo         This downloads Hermes if missing and may take several minutes.
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0hermes-setup.ps1"
    if errorlevel 1 (
        echo Hermes setup reported an error - see %LOCALAPPDATA%\StrataWoA\hermes-setup.log
        echo Gateway will start anyway; retry by running this shortcut again.
    ) else (
        echo Hermes configured. In Hermes run:  /model strata
        type nul >> "%LOCALAPPDATA%\StrataWoA\hermes-setup.done"
    )
)

echo [2/2] Starting gateway...
set "DATA=%STRATA_WOA_DATA%"
if "%DATA%"=="" set "DATA=C:\strata-woa"
rem The gateway cannot bind without the IQ3_S core pack: fetch+extract it first (one time, ~2.4 GB).
if not exist "%DATA%\packs\iq3_s\tokenizer" (
  echo [2a] IQ3_S core pack not present - downloading it now ^(2.4 GB, one time^)...
  call "%~dp0models-fetch.cmd" core
)
rem The GGUF chat pair (~84 GB) streams in the background - gateway + model listing work without it.
if not exist "%DATA%\models\IQ3_S\Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00002-of-00002.gguf" (
  echo [2b] IQ3_S model pair not present - auto-download started in the background.
  echo      Progress log: %LOCALAPPDATA%\StrataWoA\models-fetch.log
  start "" /min cmd.exe /c ""%~dp0models-fetch.cmd" pair >> "%LOCALAPPDATA%\StrataWoA\models-fetch.log" 2>&1""
)
rem Retire any old scheduled-task launch from earlier builds (harmless if absent).
schtasks /end /tn StrataWoAGateway >nul 2>&1
schtasks /delete /tn StrataWoAGateway /f >nul 2>&1
rem Already listening? leave it alone.
powershell.exe -NoProfile -Command "if ((Test-NetConnection 127.0.0.1 -Port 18500 -WarningAction SilentlyContinue).TcpTestSucceeded) { exit 10 }" 
if errorlevel 10 (
    echo Gateway already listening on 18500.
) else (
    start "StrataWoAGateway" /min cmd.exe /c "%~dp0gateway-run.cmd"
    echo Gateway launching; give the engine a minute to warm up.
)
echo Strata WoA gateway launched. API: http://127.0.0.1:18500/v1  (status: /v1/status, metrics: /metrics)
echo Log: %LOCALAPPDATA%\StrataWoA\gw.log
