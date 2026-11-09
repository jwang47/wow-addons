# Switch an addon between its release copy ("prod", from update.cmd) and a
# developer copy: a link from Interface\AddOns\<Addon> to this checkout.
#   powershell -NoProfile -ExecutionPolicy Bypass -File dev.ps1 Omni            # dev: link Omni to this checkout
#   powershell -NoProfile -ExecutionPolicy Bypass -File dev.ps1 -Off Omni       # back to the release copy
#   powershell -NoProfile -ExecutionPolicy Bypass -File dev.ps1 -Off            # every addon back to the release
#   powershell -NoProfile -ExecutionPolicy Bypass -File dev.ps1 -Status         # which addons are dev or prod
# Add -Client "<WoW _forever_ folder>" the first time, or run update.cmd once
# (it saves the folder). -Source "<folder>" links another checkout.
# The release copy waits in <client>\wow-addons-prod\ while an addon is in dev
# mode. update.cmd never changes a linked folder; it lists it as a dev copy.
# After a switch, /reload in the game (a new folder needs a full restart).
# Windows PowerShell 5.1 compatible.
param(
  [Parameter(Position = 0, ValueFromRemainingArguments = $true)][string[]]$Addons = @(),
  [string]$Client = '',
  [string]$Source = $PSScriptRoot,
  [switch]$Off,
  [switch]$Status
)
$ErrorActionPreference = 'Stop'
$clientFile = Join-Path (Join-Path $env:LOCALAPPDATA 'wow-addons') 'client.txt'
if (-not $Client -and (Test-Path $clientFile)) { $Client = (Get-Content $clientFile -Raw).Trim() }
if (-not $Client -or -not (Test-Path (Join-Path $Client 'Interface'))) {
  throw "Give the WoW folder with -Client `"D:\World of Warcraft\_forever_`" (the one with Interface), or run update.cmd once."
}
$addonsDir = Join-Path $Client 'Interface\AddOns'
$parked = Join-Path $Client 'wow-addons-prod'
$Source = (Resolve-Path $Source).Path

# The addons this checkout has: folders with <name>\<name>.toc.
$known = @(Get-ChildItem -LiteralPath $Source -Directory | Where-Object { Test-Path (Join-Path $_.FullName "$($_.Name).toc") } |
  ForEach-Object { $_.Name })

function Test-Link([string]$path) {
  (Test-Path -LiteralPath $path) -and ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)
}
function Get-LinkTarget([string]$path) {
  $t = (Get-Item -LiteralPath $path -Force).Target
  if ($t -is [array]) { $t = $t[0] }
  return [string]$t
}
# Directory.Delete on a link removes the link, never the files it points to.
function Remove-Link([string]$path) { [IO.Directory]::Delete($path, $false) }

if ($Status) {
  foreach ($n in $known) {
    $dst = Join-Path $addonsDir $n
    if (Test-Link $dst) { Write-Host "  ${n}: dev (link to $(Get-LinkTarget $dst))" -ForegroundColor Yellow }
    elseif (Test-Path -LiteralPath $dst) { Write-Host "  ${n}: release copy" }
    else { Write-Host "  ${n}: not installed" }
  }
  exit 0
}

if ($Off -and $Addons.Count -eq 0) { $Addons = $known }
if ($Addons.Count -eq 0) { throw "Name the addons to switch, for example: dev.ps1 Omni. This checkout has: $($known -join ', ')" }
foreach ($n in $Addons) {
  if ($known -notcontains $n) { throw "$n is not an addon in $Source (it has: $($known -join ', '))." }
}

foreach ($n in $Addons) {
  $dst = Join-Path $addonsDir $n
  $keep = Join-Path $parked $n
  if ($Off) {
    if (-not (Test-Link $dst)) { Write-Host "  ${n}: already the release copy"; continue }
    Remove-Link $dst
    if (Test-Path -LiteralPath $keep) {
      Move-Item -LiteralPath $keep $dst
      Write-Host "  ${n}: release copy back" -ForegroundColor Green
    } else {
      Write-Host "  ${n}: dev link removed; no release copy was kept. Run update.cmd to install it." -ForegroundColor Yellow
    }
    continue
  }
  $src = Join-Path $Source $n
  if (Test-Link $dst) {
    if ((Get-LinkTarget $dst).TrimEnd('\') -eq $src.TrimEnd('\')) { Write-Host "  ${n}: already dev ($src)"; continue }
    Remove-Link $dst   # a link to another checkout: point it here
  } elseif (Test-Path -LiteralPath $dst) {
    New-Item -ItemType Directory -Force $parked | Out-Null
    if (Test-Path -LiteralPath $keep) { [IO.Directory]::Delete($keep, $true) }   # an older parked copy
    Move-Item -LiteralPath $dst $keep
  }
  New-Item -ItemType Junction -Path $dst -Target $src | Out-Null
  Write-Host "  ${n}: dev, linked to $src" -ForegroundColor Green
}
Write-Host ''
if ($Off) { Write-Host 'Type /reload in the game.' }
else { Write-Host 'Type /reload in the game (restart it if the addon was not installed before). dev.ps1 -Off switches back.' }
