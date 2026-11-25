# Strata WoA turnkey v1.0.7: install Hermes (if missing) and preconfigure it for the
# Strata WoA OpenAI endpoint. Primary path is OFFLINE-WHEEL (no admin, no VS BuildTools,
# no compile): bundled arm64 wheels + portable MinGit + uv. Falls back to the official
# install.ps1 only if the fast path fails. Idempotent; safe to run repeatedly.
$ErrorActionPreference = 'Continue'
$log = Join-Path $env:LOCALAPPDATA 'StrataWoA\hermes-setup.log'
New-Item -ItemType Directory -Force (Split-Path $log) | Out-Null
function Log($m) { ($((Get-Date).ToString('s')) + '  ' + $m) | Add-Content $log }
Log 'hermes-setup start (v1.0.7)'

$hermesHome = Join-Path $env:LOCALAPPDATA 'hermes'
$hermesExe  = Join-Path $hermesHome 'bin\hermes.exe'
if (-not (Test-Path $hermesExe)) {
  foreach ($alt in @('hermes-agent\venv\Scripts\hermes.exe','hermes-agent\.venv\Scripts\hermes.exe')) {
    $a = Join-Path $hermesHome $alt
    if (Test-Path $a) { $hermesExe = $a; break }
  }
}

function Fast-Hermes {
  # git: prefer system git, else bundled portable MinGit
  $git = (Get-Command git.exe -ErrorAction SilentlyContinue).Source
  if (-not $git) {
    $gitDir = Join-Path $hermesHome 'tools\git'
    $gitExe = Join-Path $gitDir 'cmd\git.exe'
    if (-not (Test-Path $gitExe)) {
      $zip = Join-Path $PSScriptRoot 'tools\MinGit-2.56.1-arm64.zip'
      if (-not (Test-Path $zip)) { Log 'fast-path: no git and no bundled MinGit'; return }
      Log 'fast-path: extracting bundled MinGit'
      New-Item -ItemType Directory -Force $gitDir | Out-Null
      Expand-Archive -Force -LiteralPath $zip -DestinationPath $gitDir
    }
    $git = $gitExe
  }
  # uv: prefer system uv, else Hermes tools, else download arm64 uv
  $uv = (Get-Command uv.exe -ErrorAction SilentlyContinue).Source
  if (-not $uv) {
    $cand = Get-ChildItem (Join-Path $hermesHome 'tools') -Filter 'uv-*' -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName 'uv.exe' } | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($cand) { $uv = $cand }
  }
  if (-not $uv) {
    $uvZip = Join-Path $env:TEMP 'uv-arm64.zip'
    $uvDir = Join-Path $hermesHome 'tools\uv-aarch64'
    if (-not (Test-Path (Join-Path $uvDir 'uv.exe'))) {
      Log 'fast-path: downloading uv (arm64)'
      try {
        Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/astral-sh/uv/releases/download/0.13.5/uv-aarch64-pc-windows-msvc.zip' -OutFile $uvZip
        New-Item -ItemType Directory -Force $uvDir | Out-Null
        Expand-Archive -Force -LiteralPath $uvZip -DestinationPath $uvDir
      } catch { Log "fast-path: uv download failed: $($_.Exception.Message)"; return }
    }
    $uv = Join-Path $uvDir 'uv.exe'
    if (-not (Test-Path $uv)) { Log 'fast-path: no uv'; return }
  }
  # source tree at the release tag the turnkey package was validated against
  $src = Join-Path $hermesHome 'hermes-agent'
  $tag = 'v0.23.4'
  if (-not (Test-Path (Join-Path $src '.git'))) {
    Log "fast-path: git clone hermes-agent $tag"
    & $git clone --depth 1 --branch $tag https://github.com/NousResearch/hermes-agent.git $src *>> $log
    if ($LASTEXITCODE -ne 0) { Log 'fast-path: clone failed'; return }
  }
  # venv: create only if no working one exists
  $venvExe = $null
  foreach ($v in @('.venv\Scripts\hermes.exe','venv\Scripts\hermes.exe')) {
    $p = Join-Path $src $v
    if (Test-Path $p) { $venvExe = $p; break }
  }
  if (-not $venvExe) {
    Log 'fast-path: uv venv + pip install (offline wheels)'
    Push-Location $src
    try {
      & $uv venv --clear .venv *>> $log
      $wl = Join-Path $PSScriptRoot 'wheels'
      if (Test-Path $wl) { & $uv pip install -e . --find-links $wl *>> $log } else { & $uv pip install -e . *>> $log }
      # junction so installers/scripts also find venv\Scripts
      $j = Join-Path $src 'venv'
      if (-not (Test-Path $j)) { New-Item -ItemType Junction -Path $j -Target (Join-Path $src '.venv') *>> $log }
    } finally { Pop-Location }
    $venvExe = Join-Path $src '.venv\Scripts\hermes.exe'
  }
  if (Test-Path $venvExe) {
    # bin shim: the official launcher location hermes-setup and users expect
    $binDir = Join-Path $hermesHome 'bin'
    New-Item -ItemType Directory -Force $binDir | Out-Null
    foreach ($n in @('hermes.exe','hermes-acp.exe','hermes-agent.exe')) {
      $s = Join-Path $src ('.venv\Scripts\' + $n)
      $d = Join-Path $binDir $n
      if ((Test-Path $s) -and -not (Test-Path $d)) { Copy-Item $s $d *>> $log }
    }
    Log 'fast-path: hermes ready'
  } else {
    Log 'fast-path: venv hermes.exe not found after install'
  }
}

if (-not (Test-Path $hermesExe)) {
  Fast-Hermes
  $hermesExe = Join-Path $hermesHome 'bin\hermes.exe'
  if (-not (Test-Path $hermesExe)) { $hermesExe = Join-Path $hermesHome 'hermes-agent\.venv\Scripts\hermes.exe' }
}
if (-not (Test-Path $hermesExe)) {
  Log 'fast-path did not produce hermes.exe; falling back to bundled install.ps1 -NonInteractive'
  & (Join-Path $PSScriptRoot 'hermes-install.ps1') -NonInteractive *>> $log
  $hermesExe = Join-Path $hermesHome 'bin\hermes.exe'
  if (-not (Test-Path $hermesExe)) { $hermesExe = Join-Path $hermesHome 'hermes-agent\venv\Scripts\hermes.exe' }
}
if (-not (Test-Path $hermesExe)) { Log 'FATAL: hermes.exe still missing'; exit 1 }
Log "hermes exe: $hermesExe"

$baseUrl = 'http://127.0.0.1:18500/v1'
$model   = 'qwen3.8-flash-next-iq3_s'

# Always (additive, never destructive): a /model strata alias for the WoA endpoint.
& $hermesExe config set model.aliases.strata.model     $model     *>> $log
& $hermesExe config set model.aliases.strata.provider  lmstudio   *>> $log
& $hermesExe config set model.aliases.strata.base_url  $baseUrl   *>> $log
Log 'alias strata set'

# Fresh install only: make Strata the default model so chat works out of the box.
$configYaml = Join-Path $hermesHome 'config.yaml'
$fresh = -not (Test-Path $configYaml)
if ($fresh) {
  Log 'fresh config: pointing default model at Strata WoA'
  & $hermesExe config set model.provider  lmstudio *>> $log
  & $hermesExe config set model.base_url  $baseUrl *>> $log
  & $hermesExe config set model.model     $model   *>> $log
}
Log 'hermes-setup done'
