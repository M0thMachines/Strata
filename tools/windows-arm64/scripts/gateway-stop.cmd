@echo off
rem Stop the Strata WoA gateway and its engine.
schtasks /end /tn StrataWoAGateway >nul 2>&1
taskkill /f /im strata.exe >nul 2>&1
echo Strata WoA gateway stopped.
