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
Say ''; Say '[1/5] Reading the game''s current files...'
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

# 1b. Other installed mods that change the same tables or text: merge their changes (row by row) onto
# the game's, so Mjolnir adds to them instead of overwriting them.
Say ''; Say '[2/5] Checking other installed mods...'
$merged = Join-Path $work 'merged'; Copy-Item $fresh $merged -Recurse
$mdt = Join-Path $merged 'ProjectPBZ\Content\PBZContent\DataTable'
$mergedLoc = Join-Path $work 'merged_Game.locres'; Copy-Item $freshLoc $mergedLoc
function PriorityKey($stem) {  # same order rule as the engine/retoc: _P (and _N_P) above plain, then by name
    $base = $stem; $v = 0
    if ($base.EndsWith('_P')) { $base = $base.Substring(0, $base.Length - 2); $v = 1; if ($base -match '^(.*)_(\d+)$') { $base = $Matches[1]; $v = [int]$Matches[2] + 2 } }
    return ('{0:D6}|{1}' -f $v, $base)
}
$myKey = PriorityKey 'zz_Mjolnir_P'
$stems = @(Get-ChildItem $mods -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in '.utoc','.pak' -and $_.BaseName -notlike 'zz_Mjolnir*' } | ForEach-Object BaseName | Sort-Object -Unique)
$stems = @($stems | Sort-Object { PriorityKey $_ })
$report = @(); $after = @()
foreach ($stem in $stems) {
    $md = Join-Path $work "mods\$stem"; $view = Join-Path $md 'view'
    New-Item -ItemType Directory -Force $view | Out-Null
    Get-ChildItem $mods -File | Where-Object { $_.BaseName -eq $stem } | Copy-Item -Destination $view
    Copy-Item (Join-Path $paks 'global.utoc'), (Join-Path $paks 'global.ucas') $view
    $touched = @()
    if (Test-Path (Join-Path $view "$stem.utoc")) {
        $leg = Join-Path $md 'legacy'
        & $retoc --aes-key $key to-legacy --version UE5_7 --no-shaders -f '/DT_WeaponData.' -f '/DT_WeaponSnapSoulText.' -f '/DT_LocTable.' $view $leg 2>&1 | Out-Null
        foreach ($t in $tables.Keys) {
            $mt = Join-Path $leg "ProjectPBZ\Content\PBZContent\DataTable\$t.uasset"
            if (-not (Test-Path $mt)) { continue }
            $list = Join-Path $md "$(Split-Path $t -Leaf).rows.txt"
            & $ed rowdiff "$dt\$t.uasset" $mt $list | Out-Null
            $n = @(Get-Content $list -Encoding UTF8 | Where-Object { $_ }).Count
            if ($n -eq 0) { continue }
            & $ed transplant "$mdt\$t.uasset" "$mdt\$t.uasset" $mt "@$list" | Out-Null
            if ($LASTEXITCODE -ne 0) { Say "  ! $stem changes $(Split-Path $t -Leaf) but its version doesn't fit this game version - its changes there are skipped." 'Yellow'; continue }
            $touched += "$(Split-Path $t -Leaf) ($n rows)"
        }
    }
    $rawm = Join-Path $md 'raw'
    & $ed extract $view $key $oodle $rawm 'Localization/Game/en-US/Game\.locres$' 2>&1 | Out-Null
    $ml = Join-Path $rawm 'ProjectPBZ\Content\Localization\Game\en-US\Game.locres'
    if (Test-Path $ml) {
        $klist = Join-Path $md 'locres.keys.txt'
        & $ed locres diff $freshLoc $ml $klist | Out-Null
        $k = @(Get-Content $klist -Encoding UTF8 | Where-Object { $_ }).Count
        if ($k -gt 0) { & $ed locres merge $mergedLoc $mergedLoc $ml "@$klist" | Out-Null; if ($LASTEXITCODE -eq 0) { $touched += "English text ($k entries)" } }
    }
    if ($touched.Count) {
        $report += "  - $stem : $($touched -join ', ')"
        if ((PriorityKey $stem) -gt $myKey) { $after += $stem }
    }
}
if ($report.Count) {
    Say 'Other mods that change the same files as Mjolnir (their changes are kept and merged):'
    $report | ForEach-Object { Say $_ 'Cyan' }
    if ($after.Count) {
        Say ''; Say "WARNING: these load after Mjolnir and replace the same files, so the game may not see Mjolnir: $($after -join ', ')" 'Yellow'
        Say 'Fix: rename that mod''s files so they sort before "zz_Mjolnir_P" (e.g. add "zy_" in front of all its .pak/.utoc/.ucas names), then run this updater again.' 'Yellow'
    }
    Say 'Run this updater again whenever you install, update or remove one of these mods.'
} else { Say 'No other installed mod changes the same files - nothing to merge.' }

# Unchanged game and mods? (fingerprint of what Mjolnir builds on, after merging)
$fp = (@($tables.Keys | ForEach-Object { (Get-FileHash "$mdt\$_.uasset").Hash; (Get-FileHash "$mdt\$_.uexp").Hash }) + (Get-FileHash $mergedLoc).Hash + (Get-FileHash (Join-Path $paks 'global.utoc')).Hash) -join ','
$fpFile = Join-Path $updater 'game_fingerprint.txt'
if (-not $Force -and -not $OutDir -and (Test-Path $fpFile) -and ((Get-Content $fpFile -Raw).Trim() -eq $fp) -and (Test-Path (Join-Path $mods 'zz_Mjolnir_P.utoc'))) {
    Say ''; Say 'Nothing Mjolnir depends on has changed (game or other mods). Mjolnir is already up to date.' -ForegroundColor Green
    Say '(Run "Update Mjolnir (force).bat" to rebuild anyway.)'
    Stop-Transcript | Out-Null; Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
    if (-not $NoPause) { Read-Host 'Press Enter to close' }; exit 0
}

# 2. Mjolnir's own assets + Mjolnir's rows laid onto the fresh tables.
Say ''; Say '[3/5] Adding Mjolnir to the game''s weapon list and text...'
$stage = Join-Path $work 'stage'
Copy-Item (Join-Path $src 'legacy') $stage -Recurse
foreach ($t in $tables.Keys) {
    $out = Join-Path $stage "ProjectPBZ\Content\PBZContent\DataTable\$t.uasset"
    & $ed transplant "$mdt\$t.uasset" $out (Join-Path $src "tables\$(Split-Path $t -Leaf).uasset") $tables[$t]
    if ($LASTEXITCODE -ne 0) { Fail "The patch changed the layout of $(Split-Path $t -Leaf) in a way this updater can't adapt to. This patch needs a new Mjolnir release." }
}
$newLoc = Join-Path $work 'Game.locres'
& $ed locres merge $mergedLoc $newLoc (Join-Path $src 'Game.locres') 'Mjolnir_*'; Run 'Adding Mjolnir''s English text'

# 3. Pack.
Say ''; Say '[4/5] Packing Mjolnir...'
$build = if ($OutDir) { $OutDir } else { Join-Path $work 'out' }
New-Item -ItemType Directory -Force $build | Out-Null
foreach ($e in 'utoc','ucas','pak') { $p = Join-Path $build "zz_Mjolnir_P.$e"; if (Test-Path $p) { Remove-Item $p -Force } }
& $retoc to-zen --version UE5_7 $stage (Join-Path $build 'zz_Mjolnir_P.utoc'); Run 'Packing'
& $retoc verify (Join-Path $build 'zz_Mjolnir_P.utoc'); Run 'Checking the package'
& $packText $newLoc (Join-Path $build 'zz_Mjolnir_P.pak'); Run 'Packing the text'
if ($OutDir) { Say ''; Say "Built into $OutDir (not installed)."; Stop-Transcript | Out-Null; exit 0 }

# 4. Install, keeping the previous version.
Say ''; Say '[5/5] Installing...'
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
