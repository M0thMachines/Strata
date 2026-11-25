@echo off
rem Strata WoA gateway launcher v1.0.7 (turnkey-calibrated: safe expert/prefill tiers on any WoA box).
setlocal
set "ROOT=%~dp0.."
set "DATA=%STRATA_WOA_DATA%"
if "%DATA%"=="" set "DATA=C:\strata-woa"
set "LOGDIR=%LOCALAPPDATA%\StrataWoA"
if not exist "%LOGDIR%" mkdir "%LOGDIR%"
set "PATH=%ROOT%\bin;%PATH%"
echo ==== gateway start %date% %time% ==== >> "%LOGDIR%\gw.log"
"%ROOT%\node\node.exe" "%ROOT%\bin\gateway.mjs" --port 18500 --pack "%DATA%\packs\iq3_s" --engine "%ROOT%\bin\strata.exe" -- --pack "%DATA%\packs\iq3_s" --native "%DATA%\models\IQ3_S\Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00001-of-00002.gguf" --ple-gguf "%DATA%\models\IQ3_S\Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00002-of-00002.gguf" --expert-profile "%DATA%\extra\expert-profile.bin" --expert-cache auto --prefill 2048 --spec 4 --spec-min-p 0.5 --mtp "%DATA%\mtp\rt" --max-context 16384 --kv int8 --kv-resident 8192 --pool-workers 10 --vram-reserve-mib 4096 >> "%LOGDIR%\gw.log" 2>&1
