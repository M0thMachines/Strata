@echo off
rem Strata WoA turnkey model fetcher.
rem   models-fetch.cmd          -> fetch core pack (if missing) then the GGUF pair
rem   models-fetch.cmd core     -> core pack only (tokenizer/dense/mtp/profile zip, ~2.4 GB)
rem   models-fetch.cmd pair     -> GGUF pair only (~83.6 GB, URLs from models-url.txt)
rem Resume-safe (curl -C -), retried, size+SHA-256 verified, single-instance locked.
setlocal
set "D=%STRATA_WOA_DATA%"
if "%D%"=="" set "D=C:\strata-woa"
set "M=%D%\models\IQ3_S"
set "MODE=%~1"
if "%MODE%"=="" set "MODE=all"
set "LIST=%LOCALAPPDATA%\StrataWoA\models-url.txt"
if not exist "%LIST%" set "LIST=%~dp0models-url.txt"

mkdir "%D%" 2>nul
rem Single-instance lock: two fetchers writing the same file corrupt it.
set "LCK=%D%\.fetch.lock"
mkdir "%LCK%" 2>nul
if errorlevel 1 (
  echo Another model fetch is already running ^(lock: %LCK%^). Exiting.
  exit /b 0
)

set "OK=1"
if not "%MODE%"=="pair" call :core
if "%OK%"=="0" goto :fin
if not "%MODE%"=="core" call :pair

:fin
rmdir /q "%LCK%" 2>nul
if "%OK%"=="1" (
  echo ALL REQUESTED MODEL DATA COMPLETE.
  exit /b 0
)
echo Model data INCOMPLETE - re-run "Strata Gateway (start)" to resume.
exit /b 1

:core
if exist "%D%\packs\iq3_s\tokenizer" (echo core pack: already installed & exit /b 0)
set "P1=%D%\iq3_core.zip.part1"
set "P2=%D%\iq3_core.zip.part2"
set "ZIP=%D%\iq3_core.zip"
echo [iq3_core.zip.part1] downloading ^(1.5 GB^) at %time% ...
curl -L -s -C - --retry 30 --retry-delay 10 -m 86400 -o "%P1%" "https://github.com/M0thMachines/Strata/releases/download/v1.0.7-woa/iq3_core.zip.part1"
if errorlevel 1 (echo core part1 did NOT complete at %time% & set "OK=0" & exit /b 0)
echo [iq3_core.zip.part2] downloading ^(0.87 GB^) at %time% ...
curl -L -s -C - --retry 30 --retry-delay 10 -m 86400 -o "%P2%" "https://github.com/M0thMachines/Strata/releases/download/v1.0.7-woa/iq3_core.zip.part2"
if errorlevel 1 (echo core part2 did NOT complete at %time% & set "OK=0" & exit /b 0)
call :checkf "%P1%" 1500000000
call :checkf "%P2%" 873101431
if "%OK%"=="0" exit /b 0
echo Merging core pack parts at %time% ...
del /q "%ZIP%" 2>nul
set "MR=0"
:merge_try
copy /b "%P1"+"%P2%" "%ZIP%" 1>nul
if exist "%ZIP%" call :checkf "%ZIP%" 2373101431
if "%OK%"=="1" if exist "%ZIP%" goto :merged
set "OK=1"
set /a MR+=1
if %MR% lss 3 (
  echo merge attempt %MR% incomplete at %time% - retrying in 10s...
  del /q "%ZIP%" 2>nul
  ping -n 11 127.0.0.1 >nul
  goto merge_try
)
echo copy failed - falling back to PowerShell stream merge at %time% ...
powershell -NoProfile -NonInteractive -Command "$o=[IO.File]::Create('%ZIP%'); foreach($f in @('%P1%','%P2%')){$i=[IO.File]::OpenRead($f); $i.CopyTo($o); $i.Close()}; $o.Close()"
call :checkf "%ZIP%" 2373101431
:merged
if "%OK%"=="0" (del /q "%ZIP%" 2>nul & exit /b 0)
call :shaf "%ZIP%" 92d9b554601ecefd56473917aa56c0b88d5d68a8d052a1306ceab82b5c6d5fb2
if "%OK%"=="0" exit /b 0
echo Extracting core pack at %time% ...
"%SystemRoot%\System32\tar.exe" -xf "%ZIP%" -C "%D%"
if errorlevel 1 (echo extraction failed - delete %ZIP% and re-run. & set "OK=0" & exit /b 0)
if not exist "%D%\packs\iq3_s\tokenizer" (echo extraction incomplete. & set "OK=0" & exit /b 0)
del /q "%ZIP%" "%P1%" "%P2%" 2>nul
echo core pack: installed OK
exit /b 0

:pair
if exist "%M%\Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00002-of-00002.gguf" if exist "%M%\Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00001-of-00002.gguf" (
  echo GGUF pair: already installed & exit /b 0
)
if not exist "%LIST%" (
  echo models-url.txt missing - put one line per shard: ^<url^>   ^<filename^>
  set "OK=0" & exit /b 0
)
mkdir "%M%" 2>nul
for /f "usebackq eol=# tokens=1,*" %%u in ("%LIST%") do (
  echo [%%v] fetching at %time% ... ^(resumes if interrupted^)
  curl -L -s -C - --retry 30 --retry-delay 10 -m 604800 -o "%M%\%%v" "%%u"
  if errorlevel 1 echo [%%v] curl did NOT complete at %time% - it resumes on next run.
)
call :checkf "%M%\Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00001-of-00002.gguf" 54817524224
call :checkf "%M%\Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00002-of-00002.gguf" 28800138432
if "%OK%"=="1" (
  echo Size OK - verifying SHA-256 ^(takes a few minutes^)...
  call :shaf "%M%\Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00001-of-00002.gguf" 4c1eb2ceb4915e1192f4f386021897bde56a97f40a0bb78bb86465e0f7d2aca3
  call :shaf "%M%\Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00002-of-00002.gguf" 316b46f3a2dbd68c900f43136ab9449f9dcc3725dfd8c794847c204bc161e113
)
exit /b 0

:checkf
if not exist "%~1" (echo %~nx1 : MISSING& set "OK=0"& exit /b 0)
for %%A in ("%~1") do if not "%%~zA"=="%~2" (
  echo %~nx1 : WRONG SIZE %%~zA, expected %~2& set "OK=0"
) else echo %~nx1 : size OK
exit /b 0

:shaf
set "GOT="
for /f "skip=1 delims=" %%h in ('certutil -hashfile "%~1" SHA256 2^>nul') do if not defined GOT set "GOT=%%h"
if /i "%GOT%"=="%~2" (echo %~nx1 : sha256 OK) else (
  echo %~nx1 : SHA-256 MISMATCH - deleting so next run re-fetches it fresh.
  del /q "%~1" 2>nul
  set "OK=0"
)
exit /b 0
