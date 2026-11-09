@echo off
rem Install or update Jiahua's WoW addons (LootValue, Omni, UpgradeFinder). Double-click to run.
rem It downloads the newest update.ps1 from GitHub and runs it.
set "WOWADDONS_PS1=%TEMP%\wow-addons-update.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12; $ProgressPreference='SilentlyContinue'; Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/jwang47/wow-addons/releases/latest/download/update.ps1' -OutFile $env:WOWADDONS_PS1"
if errorlevel 1 (
  echo Could not download the updater from GitHub.
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%WOWADDONS_PS1%" %*
pause
