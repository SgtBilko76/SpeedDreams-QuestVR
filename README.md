# Speed Dreams VR — Speed Dreams 2.4 on Meta Quest (standalone, OpenXR)

A native Android port of [Speed Dreams](https://www.speed-dreams.net/) 2.4 for Meta Quest 2 / 3
headsets. The game's fixed-function OpenGL renderer (`ssggraph`) runs on top of
[gl4es](https://github.com/ptitSeb/gl4es); stereo rendering, head tracking and controller input go
through OpenXR using the Team Beef framework from
[QuakeQuest](https://github.com/Team-Beef-Studios/QuakeQuest), the same base as the TORCS VR port
next door.

Built and started on a Quest 3 (Horizon OS, Android 14). Should run on Quest 2 / Pro as well.

## Layout

| Path | What |
|---|---|
| `../speed-dreams-code` | Speed Dreams source (branch `quest-port`, Android changes under `#ifdef ANDROID`) |
| `src/vr` | VR glue: OpenXR framework (`tbxr/`), event/input bridge, stereo camera, audio, on-screen keyboard, GLU shim |
| `android/` | Gradle project (AGP 8.2.1, CMake, prefab OpenXR loader) |
| `CMakeLists.txt`, `cmake/` | Native build: core `libsdvr.so` + one `libsd_<module>.so` per module/robot |
| `third_party/` | gl4es, openal-soft, SDL2 (+ttf, +mixer), freetype, libjpeg-turbo, enet, curl, cJSON, rhash, plib, zlib, libpng |
| `tools/` | data staging / push / run scripts |
| `templates/` | VR-specific settings copied over the staged data |

## Build

Requirements: Android SDK with NDK 27.2, CMake 3.22.1 (SDK), Java 17, Python 3.

```powershell
cd E:\speed-dreams-code
git checkout quest-port
git submodule update --init --depth 1 speed-dreams-data freesolid

cd E:\SpeedDreamsVR\android
.\gradlew assembleDebug        # -> app\build\outputs\apk\debug\app-debug.apk
```

The third-party sources in `third_party/` are git clones; `third_party/gl4es` and
`third_party/SDL2` carry local patches (see "How it works").

Fast native-only rebuilds after a first Gradle build:

```powershell
ninja -C android\app\.cxx\Debug\<hash>\arm64-v8a sdvr sd_ssggraph   # etc.
cd android; .\gradlew assembleDebug -q                              # repackage
```

## Game data

The game data (~230 MB) is not in the APK. Stage and push it once:

```powershell
python tools\stage_data.py                     # builds stage\SpeedDreamsVR from speed-dreams-data
.\tools\push-data.ps1 -Full                    # adb push to /sdcard/SpeedDreamsVR
```

On device the layout is

```
/sdcard/SpeedDreamsVR/data/            the installed data tree (config, data, cars, tracks, drivers)
/sdcard/SpeedDreamsVR/.speed-dreams/   user settings, created by the game on first run
/sdcard/SpeedDreamsVR/vr.cfg           VR tunables (see below)
```

Delete `.speed-dreams` to reset settings. The app needs "All files access"; grant it in the dialog
or with `adb shell appops set com.speeddreamsvr MANAGE_EXTERNAL_STORAGE allow`.

Note: the `speed-dreams-data` submodule ships one track (Jarama) and one car model; everything else
is downloadable content, which the in-game download manager can fetch.

## Run

```powershell
adb install -r android\app\build\outputs\apk\debug\app-debug.apk
adb shell am start -n com.speeddreamsvr/.SDVRActivity
adb logcat -s SpeedDreamsVR:V TBXR:V AndroidRuntime:E DEBUG:E
```

`tools\run.ps1 -Build` does all of the above.

## Controls

Menus are on a floating screen in front of you. Point at it with the right hand and pull the right
trigger to click; the left thumbstick moves through lists. The race is rendered in stereo with head
tracking.

| Input | Menus | Race |
|---|---|---|
| Right hand pointer | move the cursor | — |
| Right trigger | click | throttle |
| Left trigger | — | brake |
| Left thumbstick | up/down/left/right in lists | steering |
| A | Enter | — |
| B / left menu button | Escape / back | pause menu |
| X | — | ASR toggle |
| Y | — | next camera; hold 1 s to recenter the seated view |
| Right thumbstick click | — | reverse gear |
| Left thumbstick click | — | neutral |
| Right grip | — | up shift |
| Left grip | — | down shift |

**Text entry:** selecting a text field (the player name, for instance) brings up an on-screen
keyboard at the bottom of the menu. Point at a key and pull the right trigger, or move the highlight
with the left thumbstick and press the trigger.

The driving controls are a virtual joystick, so they can be remapped in Options → Players like any
other joystick. `templates/data/drivers/human/preferences.xml` ships the player profile that binds
them; the stock one drives with the mouse and the arrow keys, which do not exist on a headset. The
game refreshes an existing user profile from it because the file carries a higher version number, so
a control change on your side survives only until that number is bumped again.

## Settings

Edit `/sdcard/SpeedDreamsVR/vr.cfg` and restart the app:

| Key | Default | Effect |
|---|---|---|
| `refresh` | 72 | Display Hz (72/80/90/120). Higher is smoother only if the frame rate keeps up. |
| `supersampling` | 1.0 | Eye-buffer scale, as a fraction of the runtime's recommended resolution (2800x2933 per eye on a Quest 3). Lower it for a faster, softer picture. Pixels are not what this port is short of, so it buys less than you would think - see "Performance". |
| `screen_distance` | 2.5 | Distance of the floating menu screen, in metres. |

`vr.cfg` also understands `startrace = <race name>` (for instance `practice`), which skips the
menus and starts that race directly. It is meant for testing over adb, where there is no way to
point at menu items.

Only the `ssggraph` renderer is available: `osggraph` needs OpenSceneGraph, which is not part of
this build, and the port forces `ssggraph` whatever the settings file says.

`templates/data/config/graph.xml` ships the VR graphics defaults, and the game refreshes an
existing user copy from it because the file carries a higher version number - so a change you make
in Options → Graphics survives only until that number is bumped again. The settings that matter
here are view distance ("fov factor"), sky dome distance, precipitation and scene level of detail;
"Performance" below explains why.

## Performance

The renderer is bound by the **number of draw calls**, not by pixels, vertices or physics. A race
frame on a Quest 3 profiles as 60% gl4es, 22% the Adreno driver and 1% the game's own render code,
with the GPU around half busy: each GLES draw costs roughly ten microseconds, because gl4es rebuilds
the whole fixed-function state as shader uniforms for every one of them. Everything below follows
from that.

- **One draw per mesh.** `cgrVtxTable::draw_geometry_array` used to issue one `glDrawElements` per
  triangle strip; on Android the strips are flattened once into a single `GL_TRIANGLES` index list.
  Static track meshes are additionally compiled into a gl4es display list, so their vertices are not
  re-marshaled per frame and per eye.
- **Sky dome off** (`graph.xml`). With a dome the game pins the far clip plane at 2.1 x its distance,
  25 km with the stock 12000, so nothing is ever distance-culled and the whole track is drawn twice
  a frame. Without it the far plane is `600 * fov factor` and the fog closes in with it.
- **`fov factor`** is then the draw-distance dial: it scales that far plane directly, so it trades
  how far you can see against how many meshes are in view.
- **No rain particles**, no smoke, no skid marks: many small draws is the one thing to avoid.

Every few seconds the app prints what it is doing to logcat:

```
perf: 36.0 fps (181 frames, 181 in stereo) | wait 0.0  event 0.0  sim 0.0  draw 27.7 ms
perf: draws per frame by phase | sky 0 | cars 0 | track 1500 | scene 551 | rain 0 | hud 154 | leaves 981
```

`sim` against `draw` says whether the physics or the renderer is the problem, and the phase line
says which part of the scene the draws belong to. Compare `draw` with the GPU's own load
(`adb shell cat /sys/class/kgsl/kgsl-3d0/gpu_busy_percentage`) to tell a GPU-bound frame from a
draw-call-bound one. For a full profile, `adb shell simpleperf record --app com.speeddreamsvr -e
cpu-clock --duration 12 -o /data/local/tmp/sd.data` works on a debug build.

**Shaders** are compiled by gl4es on first use, which stutters. They are saved to
`/sdcard/SpeedDreamsVR/.gl4es.psa` when a race ends and when the game quits, and reloaded at
startup. A pre-warmed archive can be shipped in the APK as `android/app/src/main/assets/gl4es.psa`;
the activity copies it into place on a fresh install.

## How it works

- **GL**: Speed Dreams and plib call GL 1.x; gl4es (static, `NOEGL`) translates to GLES 2 on the EGL
  context created by the OpenXR framework. Four local patches are applied to the gl4es v1.1.6
  clone: a `gl4es_registerExternalTexture` addition so the OpenXR swapchain images can be used as
  framebuffers, an `#ifdef __ANDROID__` block in `src/glx/hardext.c` that force-enables program
  binaries (the Quest driver supports them but gl4es' probe reports otherwise) so the precompiled
  shader archive works, a log on a failed archive write, and a draw-call counter in `src/gl/fpe.c`
  that the frame instrumentation reads.
- **No window**: `GfScrInit` has an Android branch that skips SDL video entirely; the "screen" is one
  eye buffer, and the 2D menus are drawn into a 4:3 view centred in it and shown on an OpenXR quad
  layer. `GfuiSwapBuffers` submits the OpenXR frame instead of swapping a window.
- **Event loop**: `GfuiEventLoop::operator()` has an Android branch that runs one OpenXR frame per
  iteration and takes its events from the VR input layer rather than `SDL_PollEvent`. Frame pacing
  comes from the compositor (`xrWaitFrame`), not from a sleep.
- **Stereo**: `rmRedisplay` renders the race twice per frame, once per eye. `cGrPerspCamera::
  setProjection/setModelView` apply the per-eye OpenXR field of view and pose on top of whichever
  camera the game selected, so head tracking works in every view. The sky box gets rotation only, so
  it stays at infinity. HUD and race messages are drawn on a head-locked plane 1.5 m in front of the
  eyes.
- **Modules**: the `dlopen` plugin scheme is kept. Each module and robot is `libsd_<name>.so` in the
  APK; the Android branches of `module.cpp` and `linuxspec.cpp` map the requested path to the
  packaged library. The core is linked with `-Wl,-z,global` and defines the type_info for every
  module interface (`src/vr/vr_rtti.cpp`), so all modules resolve those symbols against the one
  copy: that is what makes the `dynamic_cast` in `GfModule::getInterface()` work. `-Wl,-E` does the
  same job for the desktop executable.
- **Audio**: openal-soft (OpenSL ES backend) for the race, SDL_mixer for menu music and SFX. SDL runs
  without any `org.libsdl.app` Java classes, so two local SDL patches make the paths that need JNI
  degrade gracefully instead of dereferencing null: the audio thread priority call and
  `SDL_AndroidGetInternalStoragePath`, plus `SDL_RWFromFile` now tries a plain relative open first.
- **Input**: the Touch controllers are exposed as a virtual joystick read by
  `GfctrlJoyGetCurrentStates`, and as synthetic key/mouse events for the menus.

### Things that are off in VR

- The rear-view mirror: it needs a second render pass into a texture, which gl4es cannot do on the
  OpenXR eye framebuffers. Turn your head instead.
- Screenshots: `glReadPixels` on the eye framebuffer comes back empty.
- The track map is rasterised on the CPU instead of being rendered and read back.
- Texture compression and multisampling: not available through gl4es here.

## License

Speed Dreams is GPL-2.0. gl4es is MIT, openal-soft LGPL-2.1, SDL2 zlib, the Team Beef OpenXR
framework files follow QuakeQuest's license (GPL-2.0). The VR glue in `src/vr` is GPL-2.0.
