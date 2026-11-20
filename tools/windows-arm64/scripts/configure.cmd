@echo off
rem Write the Strata WoA engine instance config for the GUI/host (idempotent).
setlocal
set "ROOT=%~dp0.."
set "DATA=%STRATA_WOA_DATA%"
if "%DATA%"=="" set "DATA=C:\strata-woa"
set "OUT=%LOCALAPPDATA%\Strata\install"
if not exist "%OUT%" mkdir "%OUT%"
> "%OUT%\strata-woa.json" (
echo {
echo   "exe": "%ROOT:\=\\%\\bin\\strata.exe",
echo   "args": [
echo     "--pack", "%DATA:\=\\%\\packs\\iq3_s",
echo     "--native", "%DATA:\=\\%\\models\\IQ3_S\\Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00001-of-00002.gguf",
echo     "--ple-gguf", "%DATA:\=\\%\\models\\IQ3_S\\Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00002-of-00002.gguf",
echo     "--expert-profile", "%DATA:\=\\%\\extra\\expert-profile.bin",
echo     "--expert-cache", "auto", "--prefill", "auto",
echo     "--spec", "4", "--spec-min-p", "0.5",
echo     "--mtp", "%DATA:\=\\%\\mtp\\rt",
echo     "--max-context", "65536", "--kv", "int8", "--kv-resident", "20480",
echo     "--pool-workers", "10", "--vram-reserve-mib", "1024", "--memory-limit-mib", "18432"
echo   ],
echo   "cwd": "%ROOT:\=\\%\\bin",
echo   "tokenizer": "%DATA:\=\\%\\packs\\iq3_s\\tokenizer",
echo   "model_name": "qwen3.8-flash-next-iq3_s",
echo   "log": "%LOCALAPPDATA:\=\\%\\Strata\\install\\strata-woa.log",
echo   "port": 8080,
echo   "gpu": [0],
echo   "layer_split": "auto"
echo }
)
echo Wrote %OUT%\strata-woa.json
