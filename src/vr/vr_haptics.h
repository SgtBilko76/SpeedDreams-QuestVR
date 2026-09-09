#ifndef VR_HAPTICS_H
#define VR_HAPTICS_H

/* Force feedback on the Quest controllers.
 *
 * The game computes a steering force for a wheel - ForceFeedbackManager
 * returns a signed torque in +/-32760 - and gfctrlJoyConstantForce sends it to
 * an SDL haptic device, which the headset does not have. This takes the same
 * number and plays it as controller rumble instead.
 *
 * Declared without any OpenXR or TBXR types so the robot code can include it. */

#ifdef __cplusplus
extern "C" {
#endif

/* The current steering force, on the same scale ForceFeedbackManager uses:
 * signed, +/-32760 for full lock. Call it as often as the force is computed;
 * it is cheap and the rumble follows until the next call. 0 stops it.
 *
 * The sign says which way the wheel is pulling, so the hand on that side gets
 * the stronger side of the effect and the other still feels the load. */
void VrHapticsSetForce(int force);

#ifdef __cplusplus
}
#endif

#endif
