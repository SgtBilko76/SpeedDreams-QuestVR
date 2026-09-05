# Push the staged game data to the headset (/sdcard/SpeedDreamsVR).
# Run tools/stage_data.py first.
param(
    [switch]$Full,     # re-push everything (default: only if the data dir is missing)
    [switch]$Reset     # also delete the on-device user settings (.speed-dreams)
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$stage = Join-Path $root "stage\SpeedDreamsVR"
if (-not (Test-Path $stage)) { throw "stage dir missing: run python tools/stage_data.py" }

$hasData = (adb shell "test -d /sdcard/SpeedDreamsVR/data && echo yes") -match "yes"
if ($Full -or -not $hasData) {
    Write-Host "Pushing the full data set (~230 MB)..."
    adb shell mkdir -p /sdcard/SpeedDreamsVR
    adb push --sync "$stage\." /sdcard/SpeedDreamsVR/
} else {
    Write-Host "Refreshing config only (use -Full for everything)"
    adb push --sync "$stage\data\config" /sdcard/SpeedDreamsVR/data/
    adb push "$stage\vr.cfg" /sdcard/SpeedDreamsVR/vr.cfg
}
if ($Reset) {
    Write-Host "Removing /sdcard/SpeedDreamsVR/.speed-dreams"
    adb shell rm -rf /sdcard/SpeedDreamsVR/.speed-dreams
}
adb shell "du -sh /sdcard/SpeedDreamsVR"
