# Build (optional), install, launch Speed Dreams VR and stream its logcat.
param(
    [switch]$Build,
    [switch]$NoLog
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
if ($Build) {
    Push-Location (Join-Path $root "android")
    try { & .\gradlew assembleDebug -q } finally { Pop-Location }
    if ($LASTEXITCODE -ne 0) { throw "gradle build failed" }
}
$apk = Join-Path $root "android\app\build\outputs\apk\debug\app-debug.apk"
adb install -r $apk
adb shell appops set com.speeddreamsvr MANAGE_EXTERNAL_STORAGE allow
adb logcat -c
adb shell am start -n com.speeddreamsvr/.SDVRActivity
if (-not $NoLog) {
    adb logcat -s SpeedDreamsVR:V TBXR:V AndroidRuntime:E DEBUG:E
}
