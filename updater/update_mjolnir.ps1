# Mjolnir updater: rebuilds Mjolnir's game package from YOUR installed copy of Phantom Blade Zero, so the mod
# keeps working after a game patch.  Nothing is downloaded except, once, the Oodle library retoc needs.
#   -Force         rebuild even if the game's files look unchanged since the last update
#   -OutDir <dir>  build only, into <dir>; do not install (for testing)
param([switch]$Force, [string]$OutDir = '', [switch]$NoPause)
$ErrorActionPreference = 'Stop'
$tools = $PSScriptRoot
$updater = Split-Path $tools -Parent
$game = Split-Path $updater -Parent
$paks = Join-Path $game 'ProjectPBZ\Content\Paks'
$mods = Join-Path $paks '~mods'
$src = Join-Path $updater 'source'
$retoc = Join-Path $tools 'retoc\retoc-pbz.exe'
$ed = Join-Path $tools 'PBZEdit\PBZEdit.exe'
$packText = Join-Path $tools 'pack_menu_text\pack_menu_text.exe'
$oodle = Join-Path $tools 'retoc\oo2core_9_win64.dll'
$stamp = Get-Date -Format yyyyMMdd_HHmmss
$work = Join-Path $env:TEMP "MjolnirUpdate_$stamp"
$log = Join-Path $updater 'update_log.txt'
Start-Transcript -Path $log -Append | Out-Null

function Say($m, $ForegroundColor = 'Gray') { Write-Host $m -ForegroundColor $ForegroundColor }
function Fail($m) {
    Write-Host ''; Write-Host "UPDATE STOPPED: $m" -ForegroundColor Red
    Write-Host 'Your installed Mjolnir was NOT changed.'
    Write-Host "Details are in $log"
    Stop-Transcript | Out-Null
    if (-not $NoPause) { Read-Host 'Press Enter to close' }
    exit 1
}
function Run($what) { if ($LASTEXITCODE -ne 0) { Fail "$what failed (exit $LASTEXITCODE)." } }

Say '=== Mjolnir updater ==='
Say "Game folder: $game"
if (-not (Test-Path (Join-Path $paks 'global.utoc'))) { Fail "This doesn't look like the Phantom Blade Zero folder. Put the MjolnirUpdater folder in the game's main folder (the one with ProjectPBZ and platform)." }
foreach ($f in $retoc, $ed, $packText, (Join-Path $tools 'aes.txt'), (Join-Path $src 'Game.locres')) { if (-not (Test-Path $f)) { Fail "Missing updater file: $f (re-extract the MjolnirUpdater folder)." } }
if (Get-Process -Name 'PBZ','PBZ-Win64-Shipping','ProjectPBZ-Win64-Shipping' -ErrorAction SilentlyContinue) { Fail 'Phantom Blade Zero is running. Close the game first.' }
$key = (Get-Content (Join-Path $tools 'aes.txt') -Raw).Trim()
New-Item -ItemType Directory -Force $work | Out-Null

# 1. Fresh copies of the game files Mjolnir adds to, straight from the installed game (never from ~mods).
Say ''; Say '[1/4] Reading the game''s current files...'
$fresh = Join-Path $work 'fresh'
& $retoc --aes-key $key to-legacy --version UE5_7 --no-shaders -f '/DT_WeaponData.' -f '/DT_WeaponSnapSoulText.' -f '/DT_LocTable.' $paks $fresh
Run 'Reading the game''s tables (if this mentions Oodle, check your internet connection once and try again)'
$dt = Join-Path $fresh 'ProjectPBZ\Content\PBZContent\DataTable'
$tables = [ordered]@{ 'UI\DT_WeaponData' = 'Mjolnir'; 'UI\DT_WeaponSnapSoulText' = 'Mjolnir'; 'Localizaion\DT_LocTable' = 'Mjolnir_*' }
foreach ($t in $tables.Keys) { if (-not (Test-Path "$dt\$t.uasset")) { Fail "The game no longer has $t where Mjolnir expects it. This patch needs a new Mjolnir release." } }
if (-not (Test-Path $oodle)) { Fail 'The Oodle library was not downloaded. Connect to the internet once and run the updater again.' }
$rawDir = Join-Path $work 'fresh_raw'
& $ed extract $paks $key $oodle $rawDir 'Localization/Game/en-US/Game\.locres$' ; Run 'Reading the game''s English text'
$freshLoc = Join-Path $rawDir 'ProjectPBZ\Content\Localization\Game\en-US\Game.locres'

# Unchanged game? (fingerprint of the files Mjolnir builds on)
$fp = (@($tables.Keys | ForEach-Object { (Get-FileHash "$dt\$_.uasset").Hash; (Get-FileHash "$dt\$_.uexp").Hash }) + (Get-FileHash $freshLoc).Hash + (Get-FileHash (Join-Path $paks 'global.utoc')).Hash) -join ','
$fpFile = Join-Path $updater 'game_fingerprint.txt'
if (-not $Force -and -not $OutDir -and (Test-Path $fpFile) -and ((Get-Content $fpFile -Raw).Trim() -eq $fp) -and (Test-Path (Join-Path $mods 'zz_Mjolnir_P.utoc'))) {
    Say ''; Say 'The game files Mjolnir depends on have not changed. Mjolnir is already up to date.' -ForegroundColor Green
    Say '(Run "Update Mjolnir (force).bat" to rebuild anyway.)'
    Stop-Transcript | Out-Null; Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
    if (-not $NoPause) { Read-Host 'Press Enter to close' }; exit 0
}

# 2. Mjolnir's own assets + Mjolnir's rows laid onto the fresh tables.
Say ''; Say '[2/4] Adding Mjolnir to the game''s weapon list and text...'
$stage = Join-Path $work 'stage'
Copy-Item (Join-Path $src 'legacy') $stage -Recurse
foreach ($t in $tables.Keys) {
    $out = Join-Path $stage "ProjectPBZ\Content\PBZContent\DataTable\$t.uasset"
    & $ed transplant "$dt\$t.uasset" $out (Join-Path $src "tables\$(Split-Path $t -Leaf).uasset") $tables[$t]
    if ($LASTEXITCODE -ne 0) { Fail "The patch changed the layout of $(Split-Path $t -Leaf) in a way this updater can't adapt to. This patch needs a new Mjolnir release." }
}
$newLoc = Join-Path $work 'Game.locres'
& $ed locres merge $freshLoc $newLoc (Join-Path $src 'Game.locres') 'Mjolnir_*'; Run 'Adding Mjolnir''s English text'

# 3. Pack.
Say ''; Say '[3/4] Packing Mjolnir...'
$build = if ($OutDir) { $OutDir } else { Join-Path $work 'out' }
New-Item -ItemType Directory -Force $build | Out-Null
foreach ($e in 'utoc','ucas','pak') { $p = Join-Path $build "zz_Mjolnir_P.$e"; if (Test-Path $p) { Remove-Item $p -Force } }
& $retoc to-zen --version UE5_7 $stage (Join-Path $build 'zz_Mjolnir_P.utoc'); Run 'Packing'
& $retoc verify (Join-Path $build 'zz_Mjolnir_P.utoc'); Run 'Checking the package'
& $packText $newLoc (Join-Path $build 'zz_Mjolnir_P.pak'); Run 'Packing the text'
if ($OutDir) { Say ''; Say "Built into $OutDir (not installed)."; Stop-Transcript | Out-Null; exit 0 }

# 4. Install, keeping the previous version.
Say ''; Say '[4/4] Installing...'
$backup = Join-Path $updater "backup\$stamp"
New-Item -ItemType Directory -Force $backup | Out-Null
foreach ($e in 'utoc','ucas','pak') {
    $live = Join-Path $mods "zz_Mjolnir_P.$e"
    if (Test-Path $live) { Copy-Item $live $backup; Remove-Item $live -Force }
    Copy-Item (Join-Path $build "zz_Mjolnir_P.$e") $live
}
Set-Content $fpFile $fp
Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
Say ''; Say 'Mjolnir is updated for this version of the game.' -ForegroundColor Green
Say "The previous version was saved in $backup"
Stop-Transcript | Out-Null
if (-not $NoPause) { Read-Host 'Press Enter to close' }
exit 0
