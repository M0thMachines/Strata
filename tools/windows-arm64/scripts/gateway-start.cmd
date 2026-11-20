@echo off
rem Start the Strata WoA OpenAI gateway (native ARM64 engine on :18500).
schtasks /create /tn StrataWoAGateway /tr "\"%~dp0gateway-run.cmd\"" /sc ONCE /st 00:00 /f >nul 2>&1
schtasks /run /tn StrataWoAGateway
echo Strata WoA gateway launched. API: http://127.0.0.1:18500/v1  (status: /v1/status, metrics: /metrics)
echo Log: %LOCALAPPDATA%\StrataWoA\gw.log
