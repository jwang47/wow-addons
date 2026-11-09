@echo off
rem Install or update Jiahua's WoW addons (LootValue, Omni). Double-click to run.
rem It downloads the newest update.ps1 from dl.jwhex.dev and runs it.
set "WOWADDONS_PS1=%TEMP%\wow-addons-update.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12; $ProgressPreference='SilentlyContinue'; Invoke-WebRequest -UseBasicParsing -Uri 'https://dl.jwhex.dev/wow/update.ps1' -OutFile $env:WOWADDONS_PS1"
if errorlevel 1 (
  echo Could not download the updater from dl.jwhex.dev.
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%WOWADDONS_PS1%" %*
pause
