/* Steering force -> controller rumble. See vr_haptics.h. */

#include <cmath>

#include "vr_haptics.h"
#include "vr_config.h"

extern "C" void TBXR_SetRumble(int channel, float intensity);

/* TBXR channel bits: 1 is the left hand, 2 the right. */
static const int VR_HAND_LEFT  = 1;
static const int VR_HAND_RIGHT = 2;

static const float FORCE_FULL = 32760.0f;

/* The hand the wheel is not pulling towards still feels the load, just less of
 * it - otherwise a player holding one controller feels nothing half the time. */
static const float OFF_HAND = 0.35f;

static bool  s_loaded = false;
static bool  s_enabled = true;
static float s_scale = 1.0f;
static float s_deadzone = 0.15f;

static void load()
{
    if (s_loaded)
        return;

    s_loaded = true;
    s_enabled = VrConfigGetInt("ffb_rumble", 1) != 0;
    s_scale = VrConfigGetFloat("ffb_rumble_scale", 1.0f);
    s_deadzone = VrConfigGetFloat("ffb_rumble_deadzone", 0.15f);

    if (s_scale < 0.0f)
        s_scale = 0.0f;
    if (s_deadzone < 0.0f)
        s_deadzone = 0.0f;
    if (s_deadzone > 0.9f)
        s_deadzone = 0.9f;
}

void VrHapticsSetForce(int force)
{
    load();

    if (!s_enabled)
        return;

    float mag = (force < 0 ? -force : force) / FORCE_FULL;

    if (mag > 1.0f)
        mag = 1.0f;

    /* Below the deadzone, nothing. ForceFeedbackManager adds a constant
     * minimum to any non-zero force so a wheel is never completely slack, and
     * a wheel being never slack is fine - a controller buzzing quietly for the
     * whole race is not. Rescale what is left so the effect still starts from
     * nothing rather than jumping in at the threshold. */
    if (mag <= s_deadzone)
    {
        TBXR_SetRumble(VR_HAND_LEFT | VR_HAND_RIGHT, 0.0f);
        return;
    }

    mag = (mag - s_deadzone) / (1.0f - s_deadzone);

    /* Small forces are most of what a lap actually contains, and amplitude maps
     * to perceived strength steeply at the bottom of the range, so lift them. */
    float amp = powf(mag, 0.7f) * s_scale;

    if (amp > 1.0f)
        amp = 1.0f;

    const float weak = amp * OFF_HAND;

    if (force < 0)
    {
        TBXR_SetRumble(VR_HAND_LEFT, amp);
        TBXR_SetRumble(VR_HAND_RIGHT, weak);
    }
    else
    {
        TBXR_SetRumble(VR_HAND_LEFT, weak);
        TBXR_SetRumble(VR_HAND_RIGHT, amp);
    }
}
