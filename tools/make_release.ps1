# Assemble a release: the APK, the base game data, and an installer for both.
#
# The base data is the 230 MB that Speed Dreams itself ships - one track, one
# car, and everything that is not a track or a car: menus, fonts, sounds, the
# drivers, the car categories. That is a complete, working game. The other 74
# tracks and 90 cars are published separately and the player fetches the ones
# they want from Options -> Downloads inside the headset.
#
# tools\fetch_assets.py puts those downloads into stage\ as well, so anything
# with a .revision file in it came from there and is skipped here. Pass
# -WithAssets to package the lot instead, which makes it about 5.6 GB - too big
# to be convenient, and far too big for an APK, which is a zip that Android's
# package parser reads without zip64.
#
#   tools\make_release.ps1                -> dist\SpeedDreamsVR-<version>.zip
#   tools\make_release.ps1 -NoZip         -> just the folder
#   tools\make_release.ps1 -WithAssets    -> every published car and track too
#
# Run tools\stage_data.py first; this packages what is in stage\.

param(
    [switch]$NoZip,
    [switch]$WithAssets
)

$ErrorActionPreference = "Stop"
$root  = Split-Path -Parent $PSScriptRoot
$stage = Join-Path $root "stage\SpeedDreamsVR"
$apk   = Join-Path $root "android\app\build\outputs\apk\release\app-release.apk"

if (-not (Test-Path $apk))   { throw "no release APK: run android\gradlew.bat assembleRelease" }
if (-not (Test-Path $stage)) { throw "stage dir missing: run python tools\stage_data.py" }

# The version the APK actually carries, rather than one written down twice.
$gradle  = Get-Content (Join-Path $root "android\app\build.gradle") -Raw
$version = ([regex]::Match($gradle, "versionName\s+'([^']+)'")).Groups[1].Value
if (-not $version) { throw "could not read versionName from android\app\build.gradle" }

$name = "SpeedDreamsVR-$version"
$out  = Join-Path $root "dist\$name"

Write-Host "Packaging $name"
if (Test-Path $out) { Remove-Item -Recurse -Force $out }
New-Item -ItemType Directory -Force -Path $out | Out-Null

Copy-Item $apk (Join-Path $out "$name.apk")
Write-Host ("  apk    {0:N1} MB" -f ((Get-Item $apk).Length / 1MB))

# --- the data ----------------------------------------------------------------
$dataOut = Join-Path $out "SpeedDreamsVR"
$stageLen = $stage.Length

# Directories holding a downloaded asset, and so everything under them.
$skip = @()
if (-not $WithAssets) {
    $skip = Get-ChildItem -Recurse -Force -Filter ".revision" -File $stage |
            ForEach-Object { $_.DirectoryName }
}
Write-Host ("  data   copying{0}..." -f $(if ($skip.Count) { ", skipping $($skip.Count) downloadable assets" } else { "" }))

$copied = 0
foreach ($file in Get-ChildItem -Recurse -File $stage) {
    $dir = $file.DirectoryName
    $isAsset = $false
    foreach ($s in $skip) {
        if ($dir -eq $s -or $dir.StartsWith($s + [IO.Path]::DirectorySeparatorChar)) { $isAsset = $true; break }
    }
    if ($isAsset) { continue }

    $dest = Join-Path $dataOut $file.FullName.Substring($stageLen).TrimStart('\')
    $destDir = Split-Path -Parent $dest
    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Force -Path $destDir | Out-Null }
    Copy-Item $file.FullName $dest
    $copied++
}
$bytes = (Get-ChildItem -Recurse -File $dataOut | Measure-Object -Property Length -Sum).Sum
Write-Host ("  data   {0:N1} MB in {1:N0} files" -f ($bytes / 1MB), $copied)

# --- the installer -----------------------------------------------------------
# A .cmd rather than a .ps1: it runs on a double click without anyone having to
# think about the execution policy.
$install = @"
@echo off
setlocal
cd /d "%~dp0"

echo Speed Dreams VR $version
echo.
echo Connect the headset, allow USB debugging on it, and press a key.
pause >nul

where adb >nul 2>&1
if errorlevel 1 (
  echo.
  echo adb is not on the PATH. Install the Android platform-tools and try again:
  echo   https://developer.android.com/tools/releases/platform-tools
  echo.
  pause
  exit /b 1
)

adb wait-for-device
if errorlevel 1 goto :fail

echo.
echo Installing the app...
adb install -r "$name.apk"
if errorlevel 1 goto :fail

echo.
echo Copying the game data (about 230 MB). Safe to run again if it is
echo interrupted - only what is missing or changed gets sent.
echo.
adb shell mkdir -p /sdcard/SpeedDreamsVR
adb push --sync "SpeedDreamsVR\." /sdcard/SpeedDreamsVR/
if errorlevel 1 goto :fail

echo.
echo Done. Speed Dreams VR is under Unknown Sources in the headset's library.
pause
exit /b 0

:fail
echo.
echo That did not work. Check that the headset is connected and that you
echo accepted the "Allow USB debugging" prompt inside it, then try again.
pause
exit /b 1
"@
Set-Content -Path (Join-Path $out "install.cmd") -Value $install -Encoding ASCII

# --- and a note for whoever is holding the folder ----------------------------
$readme = @"
Speed Dreams VR $version
========================

Speed Dreams 2.4 as a standalone Meta Quest application: stereo rendering
through OpenXR, a curved menu panel, and the full game.

Quest 2, Quest 3, Quest Pro. About 500 MB free on the headset to start with.


Installing
----------

Windows, with the headset plugged in and developer mode on:

    double-click install.cmd

It needs adb, from the Android platform-tools:
https://developer.android.com/tools/releases/platform-tools

By hand, or on macOS and Linux:

    adb install -r "$name.apk"
    adb shell mkdir -p /sdcard/SpeedDreamsVR
    adb push --sync SpeedDreamsVR/. /sdcard/SpeedDreamsVR/

The game appears in the headset's library under Unknown Sources.

The data goes on the sdcard rather than inside the app, so it survives
reinstalling and updating the APK. Only the APK needs replacing for an update
unless the notes say otherwise.


More cars and tracks
--------------------

This ships with what Speed Dreams itself ships: one track and one car, which is
enough to race. Another 74 tracks and 90 cars are published separately - get
them from inside the headset, in Options -> Downloads, over wifi. Pick the ones
you want; the whole set is about 5.4 GB.


Controls
--------

    Right trigger        throttle          Left trigger      brake
    Left stick           steer             Left stick click  reverse gear
    Right grip           shift up          Left grip         shift down
    A                    ABS / confirm     X                 ASR
    Right stick click    rear-view mirror
    Y                    next camera; hold 1 second to recentre the menu panel

If the menu panel is not in front of you, hold Y for a second - it is anchored
to the room, not to your head, so it stays where it was when you last moved.


Settings
--------

/sdcard/SpeedDreamsVR/vr.cfg holds the things worth trying without a new build:
eye buffer scale, refresh rate, antialiasing, where the mirror sits, and the
steering curve. It is commented; edit it and restart the app.

Everything else is in the game's own Options menu. If a track will not hold
frame rate, turn the sky dome off first - with it on, nothing is distance
culled and the whole track is drawn every frame, twice.


Known limits
------------

- Practice and qualifying run one car at a time. That is how the game works,
  not a fault of the port: use Quick Race or a championship to race opponents.
"@
Set-Content -Path (Join-Path $out "README.txt") -Value $readme -Encoding UTF8

Write-Host "  ->     $out"

if (-not $NoZip) {
    $zip = "$out.zip"
    if (Test-Path $zip) { Remove-Item -Force $zip }
    Write-Host "  zip    compressing..."
    Compress-Archive -Path (Join-Path $out "*") -DestinationPath $zip -CompressionLevel Optimal
    Write-Host ("  ->     {0} ({1:N1} MB)" -f $zip, ((Get-Item $zip).Length / 1MB))
}
