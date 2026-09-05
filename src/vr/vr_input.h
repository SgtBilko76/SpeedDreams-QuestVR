#ifndef VR_INPUT_H
#define VR_INPUT_H

#ifdef __cplusplus
extern "C" {
#endif

/* Called once per frame (from TBXR_FrameSetup, after TBXR_UpdateControllers) to
 * translate the Touch controller state into the virtual joystick plus the
 * synthetic key / mouse events consumed by the event loop. */
void VrInputUpdate(void);

/* Virtual joystick read used by tgfclient/control.cpp (GfctrlJoyGetCurrentStates).
 * Fills *buttons (bitmask, bit N = "BTN(N+1)-0") and axes[] (8 axes) for joystick
 * 'index' (only index 0 exists). Returns 0 on success, -1 otherwise. */
int VrJoyRead(int index, int* buttons, float* axes);

#ifdef __cplusplus
}
#endif

#endif
