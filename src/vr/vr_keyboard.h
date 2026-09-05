#ifndef VR_KEYBOARD_H
#define VR_KEYBOARD_H

/* Pointer-driven on-screen keyboard for text fields (e.g. the player name).
 * Appears whenever a TORCS edit box is focused; the right-hand cursor selects
 * keys and each press is injected as a keystroke through the GLUT shim. */

#ifdef __cplusplus
extern "C" {
#endif

void VrKeyboardSetCursor(int winX, int winY);  /* live cursor in window px */
int  VrKeyboardActive(void);      /* an edit box is focused */
void VrKeyboardRender(void);      /* draw it in the 640x480 GUI ortho (mono path) */
int  VrKeyboardTryClick(void);    /* pointer: if the cursor is over a key, inject it */
void VrKeyboardMove(int dir);     /* stick nav: 0=up 1=down 2=left 3=right */
int  VrKeyboardActivate(void);    /* press the highlighted key */

#ifdef __cplusplus
}
#endif

#endif
