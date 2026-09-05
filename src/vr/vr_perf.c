/*
 * vr_perf.c - frame time and draw call breakdown, one logcat line every few seconds.
 *
 * The Quest gives no frame counter an app can read, and the in-game FPS display
 * is drawn into an eye buffer we cannot capture. So the event loop marks the end
 * of each phase of its iteration and this accumulates the deltas:
 *
 *   wait   blocked in xrWaitFrame, i.e. the app is ahead of the display and the
 *          compositor is pacing it. Most of this is reported by VrPresent, which
 *          opens the next frame at the end of its work, and is taken back out of
 *          the phase it was measured in - otherwise a frame that idles against
 *          the refresh rate reads as one that exactly fills it.
 *   event  controller/menu event dispatch.
 *   sim    physics, robots, sound and the race engine's own update.
 *   draw   the render itself, including the OpenXR submit at the end of it.
 *
 * The counters come from a local addition to gl4es (src/gl/fpe.c): realize_glenv()
 * runs exactly once per draw, so gl4es_drawCalls is the number of GLES draws the
 * frame really costs, whatever the game issued to get there (immediate mode,
 * display lists, vertex arrays). Draw calls, not pixels or vertices, are what
 * this port is short of: every one of them makes gl4es rebuild the fixed-function
 * state as shader uniforms. cGrScreen::drawScene tags them by scene phase
 * (VrPerfScene) so the expensive part is visible rather than guessed at.
 *
 * Compare "draw" against the GPU's own load with
 *   adb shell cat /sys/class/kgsl/kgsl-3d0/gpu_busy_percentage
 * to tell a GPU-bound frame from a draw-call-bound (CPU) one.
 */

#include <stdint.h>
#include <time.h>

#include "vr_log.h"
#include "vr_state.h"

/* gl4es local addition, third_party/gl4es/src/gl/fpe.c */
extern int gl4es_drawCalls;
extern long gl4es_drawVerts;

#define REPORT_PERIOD_NS 5000000000LL   /* 5 s */

static int64_t sPhase[VR_PERF_PHASES];  /* accumulated ns per phase */
static int64_t sPendingWait;            /* compositor wait inside the current phase */
static int64_t sLast;                   /* end of the previous phase */
static int64_t sReportStart;
static int     sFrames;
static int     sStereoFrames;

static long    sScene[VR_PERF_SCENES];  /* accumulated draw calls per scene phase */
static int     sScenePrev;              /* gl4es_drawCalls at the last scene tag */
static long    sDrawCalls;
static long    sDrawVerts;
static long    sLeaves;                 /* scene graph leaves drawn */
static int     sLeavesPrev;
static long    sTrackParts;             /* of which track meshes */

static const char* const kSceneName[VR_PERF_SCENES] = { "sky", "cars", "track", "scene", "rain", "hud" };

static int64_t nowNs(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

void VrPerfWaited(long long ns)
{
    if (ns > 0)
        sPendingWait += ns;
}

void VrPerfScene(int slot)
{
    if (slot >= 0 && slot < VR_PERF_SCENES)
        sScene[slot] += gl4es_drawCalls - sScenePrev;
    sScenePrev = gl4es_drawCalls;
}

void VrPerfTrackPart(void)
{
    sTrackParts++;
}

void VrPerfLeaves(int total)
{
    sLeaves += total - sLeavesPrev;
    sLeavesPrev = total;
}

void VrPerfMark(int phase)
{
    int64_t now = nowNs();

    if (sReportStart == 0) {
        sReportStart = now;
        sLast = now;
        return;
    }
    if (phase >= 0 && phase < VR_PERF_PHASES) {
        int64_t delta = now - sLast;
        if (sPendingWait > 0) {
            int64_t waited = sPendingWait < delta ? sPendingWait : delta;
            sPhase[VR_PERF_WAIT] += waited;
            delta -= waited;
        }
        sPhase[phase] += delta;
    }
    sPendingWait = 0;
    sLast = now;

    if (phase != VR_PERF_DRAW)
        return;

    /* Whatever was drawn outside the tagged scene phases (HUD, menus, keyboard). */
    VrPerfScene(VR_PERF_SCENE_HUD);

    sFrames++;
    if (VrFrameWasStereo())
        sStereoFrames++;
    sDrawCalls = gl4es_drawCalls;
    sDrawVerts = gl4es_drawVerts;

    int64_t elapsed = now - sReportStart;
    if (elapsed < REPORT_PERIOD_NS)
        return;

    double secs = (double)elapsed / 1e9;
    double f = (double)sFrames;

    ALOGI("perf: %.1f fps (%d frames, %d in stereo) | wait %.1f  event %.1f  sim %.1f  draw %.1f ms"
          " | %.0f draws %.0fk verts per frame",
          f / secs, sFrames, sStereoFrames,
          (double)sPhase[VR_PERF_WAIT] / 1e6 / f,
          (double)sPhase[VR_PERF_EVENT] / 1e6 / f,
          (double)sPhase[VR_PERF_SIM] / 1e6 / f,
          (double)sPhase[VR_PERF_DRAW] / 1e6 / f,
          (double)sDrawCalls / f, (double)sDrawVerts / 1000.0 / f);
    ALOGI("perf: draws per frame by phase | %s %.0f | %s %.0f | %s %.0f | %s %.0f | %s %.0f | %s %.0f"
          " | leaves %.0f (%.0f track)",
          kSceneName[0], (double)sScene[0] / f,
          kSceneName[1], (double)sScene[1] / f,
          kSceneName[2], (double)sScene[2] / f,
          kSceneName[3], (double)sScene[3] / f,
          kSceneName[4], (double)sScene[4] / f,
          kSceneName[5], (double)sScene[5] / f,
          (double)sLeaves / f, (double)sTrackParts / f);

    for (int i = 0; i < VR_PERF_PHASES; i++)
        sPhase[i] = 0;
    for (int i = 0; i < VR_PERF_SCENES; i++)
        sScene[i] = 0;
    sLeaves = 0;
    sTrackParts = 0;
    gl4es_drawCalls = 0;
    gl4es_drawVerts = 0;
    sScenePrev = 0;
    sFrames = 0;
    sStereoFrames = 0;
    sReportStart = now;
}
