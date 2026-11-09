# Install or update Jiahua's WoW addons (LootValue, Omni, UpgradeFinder) for WoW Forever.
# Friends run update.cmd (it downloads and runs this file); or, in PowerShell:
#   powershell -NoProfile -ExecutionPolicy Bypass -File update.ps1 [-Client "D:\World of Warcraft\_forever_"]
# It reads addons.json from the latest GitHub release of jwang47/wow-addons,
# downloads each addon that is
# new or changed, checks its SHA-256, and replaces only that addon's folder
# in Interface\AddOns. Other addons and your settings (WTF\) are not touched.
# Windows PowerShell 5.1 compatible.
param(
  [string]$Client = '',
  [string]$Manifest = 'https://github.com/jwang47/wow-addons/releases/latest/download/addons.json',  # a URL or a local file (tests)
  [switch]$Check                                             # show what would change; change nothing
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest is very slow with the progress bar
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$state = Join-Path $env:LOCALAPPDATA 'wow-addons'
New-Item -ItemType Directory -Force $state | Out-Null
$clientFile = Join-Path $state 'client.txt'

function Test-Client([string]$path) {
  if (-not $path -or -not (Test-Path $path)) { return $false }
  if (Test-Path (Join-Path $path 'Interface')) { return $true }
  return [bool](Get-ChildItem $path -Filter 'Wow*.exe' -ErrorAction SilentlyContinue)
}

function Find-Client {
  if ($Client) { return $Client }
  if (Test-Path $clientFile) {
    $saved = (Get-Content $clientFile -Raw).Trim()
    if (Test-Client $saved) { return $saved }
  }
  $roots = @('Program Files (x86)\World of Warcraft', 'Program Files\World of Warcraft', 'World of Warcraft',
    'Games\World of Warcraft', 'Battle.net\World of Warcraft')
  foreach ($drive in (Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Root })) {
    foreach ($r in $roots) {
      $p = Join-Path (Join-Path $drive $r) '_forever_'
      if (Test-Client $p) { return $p }
    }
  }
  Write-Host 'Could not find WoW Forever. Paste the _forever_ folder (the one with Wow.exe and Interface),'
  Write-Host 'for example D:\World of Warcraft\_forever_'
  return (Read-Host 'Folder').Trim('"', ' ')
}

function Get-Text([string]$src) {
  if ($src -match '^https?://') {
    return (Invoke-WebRequest -UseBasicParsing -Uri $src -Headers @{ 'Cache-Control' = 'no-cache' }).Content
  }
  return Get-Content $src -Raw
}

function Get-File([string]$src, [string]$dst) {
  if ($src -match '^https?://') { Invoke-WebRequest -UseBasicParsing -Uri $src -OutFile $dst }
  else { Copy-Item $src $dst -Force }
}

$Client = Find-Client
if (-not (Test-Client $Client)) { throw "Not a WoW folder: $Client" }
if (-not $Check) { Set-Content -Path $clientFile -Value $Client -Encoding UTF8 }
$addons = Join-Path $Client 'Interface\AddOns'
New-Item -ItemType Directory -Force $addons | Out-Null
Write-Host "WoW folder: $Client"

$text = Get-Text $Manifest
if ($text -is [byte[]]) { $text = [Text.Encoding]::UTF8.GetString($text) }
$m = $text | ConvertFrom-Json
if ($m.schema -ne 1) { throw "Unknown addons.json schema: $($m.schema). Download update.cmd again." }
$base = if ($Manifest -match '^https?://') { $null } else { Split-Path -Parent (Resolve-Path $Manifest) }

# installed.json remembers the SHA-256 of what this script installed, per
# WoW folder: { "<full client path, lower case>": { "<addon>": "<sha256>" } }.
$installedFile = Join-Path $state 'installed.json'
$clientKey = ([IO.Path]::GetFullPath($Client)).TrimEnd('\').ToLowerInvariant()
$all = @{}
if (Test-Path $installedFile) {
  try {
    (Get-Content $installedFile -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object {
      if ($_.Value -is [System.Management.Automation.PSCustomObject]) {
        $h = @{}
        $_.Value.PSObject.Properties | ForEach-Object { $h[$_.Name] = [string]$_.Value }
        $all[$_.Name] = $h
      }
    }
  } catch { $all = @{} }   # an old or broken file: everything is checked again
}
if (-not $all.ContainsKey($clientKey)) { $all[$clientKey] = @{} }
$installed = $all[$clientKey]

function Save-Installed { $all | ConvertTo-Json -Depth 3 | Set-Content -Path $installedFile -Encoding UTF8 }

$changed = 0
$failed = @()
$dev = @()       # addons in dev mode (a link), left as they are
$fresh = $false   # a folder that did not exist before needs a game restart
# Staging sits in the WoW folder, on the same drive as AddOns: Move-Item
# cannot move a folder to another drive (%TEMP% is usually on C:).
# Directory.Delete removes a junction or link inside the folder, not its target
# (Remove-Item -Recurse in PowerShell 5.1 can follow it).
function Remove-Dir([string]$path) { if (Test-Path -LiteralPath $path) { [IO.Directory]::Delete($path, $true) } }

# A run that stopped between its two moves (window closed, power cut) left the
# old addon in a staging folder. Put it back if the addon is missing, then
# remove the staging folder.
if (-not $Check) {
  foreach ($s in @(Get-ChildItem -LiteralPath $Client -Directory -Filter 'wow-addons-staging-*' -ErrorAction SilentlyContinue)) {
    $restored = $true
    foreach ($o in @(Get-ChildItem -LiteralPath $s.FullName -Directory -Filter '*.old' -ErrorAction SilentlyContinue)) {
      $back = Join-Path $addons ($o.Name -replace '\.old$', '')
      if (-not (Test-Path -LiteralPath $back)) {
        try { Move-Item -LiteralPath $o.FullName $back; Write-Host "  Put back $($o.Name -replace '\.old$', '') from an unfinished update." }
        catch { $restored = $false; Write-Host "  An unfinished update left $($o.FullName); move it to $back by hand." -ForegroundColor Yellow }
      }
    }
    if ($restored) { try { Remove-Dir $s.FullName } catch { } }
  }
}

$tmp = Join-Path $Client ('wow-addons-staging-' + [Guid]::NewGuid().ToString('N'))
$keepTmp = $false   # true when a backup could not be put back: never delete it
if (-not $Check) {
  try { New-Item -ItemType Directory -Force $tmp | Out-Null }
  catch {
    throw "Cannot write in $Client ($($_.Exception.Message)). Run update.cmd as administrator, or move WoW out of Program Files."
  }
}
try {
  foreach ($a in $m.addons) {
    $name = [string]$a.name
    $old = $null
    if ($name -notmatch '^[A-Za-z0-9_]+$') { throw "Bad addon name in addons.json: $name" }
    $dst = Join-Path $addons $name
    # A link is a developer copy (dev.ps1): never change it, just say so.
    if ((Test-Path -LiteralPath $dst) -and ((Get-Item -LiteralPath $dst -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
      $t = (Get-Item -LiteralPath $dst -Force).Target
      if ($t -is [array]) { $t = $t[0] }
      Write-Host "  ${name}: dev copy (link to $t), not changed. dev.ps1 -Off $name goes back to the release." -ForegroundColor Yellow
      $dev += $name
      continue
    }
    $have = (Test-Path (Join-Path $dst "$name.toc")) -and ($installed[$name] -eq $a.sha256)
    foreach ($req in @($a.requires)) {
      if ($req -and -not (Test-Path (Join-Path $addons "$req\$req.toc"))) {
        $link = @{ 'Auctionator' = 'https://www.curseforge.com/wow/addons/auctionator' }[$req]
        Write-Host "  $name needs the $req addon, which is not installed. Install $req first$(if ($link) { ": $link" } else { '' })" -ForegroundColor Yellow
        Write-Host "  (WoW does not load $name without it.)" -ForegroundColor Yellow
      }
    }
    if ($have) { Write-Host "  $name $($a.version): up to date"; continue }
    if ($Check) { Write-Host "  $name $($a.version): would install"; $changed++; continue }
    try {

    $zip = Join-Path $tmp "$name.zip"
    # A local manifest (a test build) has the zips beside it, as in the release.
    $src = if ($base) { Join-Path $base (([string]$a.url -split '/')[-1]) } else { $a.url }
    Get-File $src $zip
    $sha = (Get-FileHash -Algorithm SHA256 $zip).Hash.ToLower()
    if ($sha -ne $a.sha256) { throw "$name download is damaged (SHA-256 $sha, expected $($a.sha256)). Its folder was not changed." }
    $out = Join-Path $tmp $name
    Expand-Archive -Path $zip -DestinationPath $out -Force
    $new = Join-Path $out $name
    if (-not (Test-Path (Join-Path $new "$name.toc"))) { throw "$name zip has no $name\$name.toc. Its folder was not changed." }

    # Keep the player's own files (for example notes) from the old folder.
    foreach ($k in @($a.keep)) {
      if ($k -and (Test-Path (Join-Path $dst $k))) { Copy-Item (Join-Path $dst $k) (Join-Path $new $k) -Force }
    }
    if (Test-Path $dst) {
      $old = Join-Path $tmp "$name.old"
      Move-Item $dst $old
    } else { $fresh = $true }
    try { Move-Item $new $dst }
    catch {
      $why = $_.Exception.Message
      if ($old -and (Test-Path $old)) {
        try { Move-Item $old $dst }
        catch {
          $keepTmp = $true
          throw "could not install ($why) and could not put the old folder back. Your old $name is in $old; move it back to $dst by hand."
        }
      }
      throw "could not install: $why. The old folder is back in place."
    }
    $installed[$name] = $a.sha256
    Save-Installed
    $changed++
    Write-Host "  $name $($a.version): installed" -ForegroundColor Green
    } catch {
      # One bad addon does not stop the others; its old folder stays as it was.
      Write-Host "  ${name}: $($_.Exception.Message)" -ForegroundColor Red
      $failed += $name
    }
  }
} finally {
  if (-not $keepTmp) { try { Remove-Dir $tmp } catch { } }
}
Write-Host ''
if ($Check) {
  if ($changed -gt 0) { Write-Host "$changed addon(s) would be installed or updated." } else { Write-Host 'Everything is up to date.' }
} elseif ($changed -gt 0) {
  if ($fresh) {
    Write-Host 'Done. Restart WoW fully (/reload does not find a new addon folder),'
    Write-Host 'and check the addons are on in the AddOns list on the character screen.'
  } else {
    Write-Host 'Done. Type /reload in the game (or restart it) to load the update.'
  }
} elseif ($failed.Count -eq 0) {
  Write-Host 'Everything is up to date.'
}
if ($dev.Count -gt 0) { Write-Host "In dev mode (not updated): $($dev -join ', ')." -ForegroundColor Yellow }
if ($failed.Count -gt 0) {
  Write-Host "Not updated: $($failed -join ', '). Run update.cmd again later." -ForegroundColor Red
  exit 1
}
