/*
 * vr_keyboard.cpp - on-screen keyboard for Speed Dreams text fields on Meta Quest.
 *
 * Speed Dreams edit boxes expect a physical keyboard (gfuiKeyboard -> gfuiEditboxKey).
 * There is none in VR, so this draws a key grid over the menu in the 640x480 GUI
 * ortho space and, when the aim cursor clicks a key, injects the corresponding
 * character as a key event (VrQueueKey), exactly as a real keystroke.
 */

#include <string.h>
#include <math.h>

#include <GL/gl.h>
#include <SDL_keycode.h>

#include "vr_keyboard.h"
#include "vr_events.h"

/* From tgfclient (declared here to keep the VR layer independent of its headers). */
void GfScrGetSize(int* scrW, int* scrH, int* viewW, int* viewH);
void GfuiDrawString(const char* text, float* fgColor, int font,
                               int x, int y, int width, int hAlign);
/* Set by the ANDROID branch of gui.cpp: is a text field focused? */
extern "C" int GfuiEditboxFocused(void);

#define SD_FONT_MEDIUM_C 6      /* GFUI_FONT_MEDIUM_C */
#define SD_ALIGN_HC      0x01   /* GFUI_ALIGN_HC      */

/* GUI virtual space (the menu screens are laid out in 640x480, origin bottom-left). */
static const float GUI_W = 640.0f;
static const float GUI_H = 480.0f;

struct VrKey {
    float x, y, w, h;   /* in GUI coords, y up */
    char lower;         /* character injected (unshifted) */
    char upper;         /* shifted */
    const char* label;  /* NULL -> use the char */
    int   row;          /* keyboard row (for stick navigation) */
    float cx, cy;       /* centre */
};

/* special sentinels in 'lower' */
#define K_SHIFT 1
#define K_BACK  8
#define K_ENTER 13
#define K_SPACE 32

static VrKey sKeys[80];
static int sNumKeys = 0;
static bool sBuilt = false;
static bool sShift = false;
static float sCurWinX = 0, sCurWinY = 0;  /* live cursor in window px (y down) */
static int   sSel = -1;   /* selected key for stick navigation (-1 = none) */

static void addKey(float x, float y, float w, float h, char lo, char up, const char* label, int row)
{
    VrKey& k = sKeys[sNumKeys++];
    k.x = x; k.y = y; k.w = w; k.h = h; k.lower = lo; k.upper = up; k.label = label;
    k.row = row; k.cx = x + w / 2; k.cy = y + h / 2;
}

static void build(void)
{
    if (sBuilt) return;
    sBuilt = true;
    sNumKeys = 0;

    const float kw = 52.0f, kh = 40.0f, gap = 5.0f;
    const float x0 = 25.0f;
    float y = 175.0f;   /* top row baseline (GUI y up) */

    const char* rows[]  = {"1234567890", "qwertyuiop", "asdfghjkl", "zxcvbnm"};
    const char* rowsU[] = {"!?#@-_.,:/", "QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM"};
    for (int r = 0; r < 4; r++) {
        float x = x0 + r * (kw * 0.4f);
        const char* lo = rows[r];
        const char* up = rowsU[r];
        for (int i = 0; lo[i]; i++) {
            addKey(x, y, kw, kh, lo[i], up[i], NULL, r);
            x += kw + gap;
        }
        y -= kh + gap;
    }
    /* bottom row: Shift, Space, Back, Enter */
    float x = x0;
    addKey(x, y, kw * 1.6f, kh, K_SHIFT, K_SHIFT, "Shift", 4); x += kw * 1.6f + gap;
    addKey(x, y, kw * 4.0f, kh, K_SPACE, K_SPACE, "Space", 4); x += kw * 4.0f + gap;
    addKey(x, y, kw * 1.8f, kh, K_BACK, K_BACK, "Back", 4);    x += kw * 1.8f + gap;
    addKey(x, y, kw * 1.8f, kh, K_ENTER, K_ENTER, "Enter", 4);
    if (sSel < 0) sSel = 11; /* start on 'q' */
}

static int keyAt(float gx, float gy)
{
    for (int i = 0; i < sNumKeys; i++) {
        const VrKey& k = sKeys[i];
        if (gx >= k.x && gx <= k.x + k.w && gy >= k.y && gy <= k.y + k.h) {
            return i;
        }
    }
    return -1;
}

static void guiCursor(float* gx, float* gy)
{
    int sw = 640, sh = 480, vw = 640, vh = 480;
    GfScrGetSize(&sw, &sh, &vw, &vh);
    if (vw <= 0 || vh <= 0) { *gx = *gy = -1; return; }
    *gx = (sCurWinX - (sw - vw) / 2.0f) * GUI_W / vw;
    *gy = (vh - sCurWinY + (sh - vh) / 2.0f) * GUI_H / vh;  /* y up */
}

/* Speed Dreams keeps SDL keycodes: printable characters are their own keycode,
 * and the edit box uses the unicode field for insertion. */
static void injectChar(char c)
{
    int keycode = (unsigned char)c;
    int unicode = (c == K_BACK || c == K_ENTER) ? 0 : (unsigned char)c;
    if (c == K_BACK)  { keycode = SDLK_BACKSPACE; }
    if (c == K_ENTER) { keycode = SDLK_RETURN; }
    if (c == K_SPACE) { keycode = SDLK_SPACE; unicode = ' '; }
    VrQueueKey(keycode, 1, 0, unicode);
    VrQueueKey(keycode, 0, 0, unicode);
}

static int activateKey(int i)
{
    if (i < 0 || i >= sNumKeys) return 0;
    if (sKeys[i].lower == K_SHIFT) { sShift = !sShift; return 1; }
    injectChar(sShift ? sKeys[i].upper : sKeys[i].lower);
    return 1;
}

extern "C" {

void VrKeyboardSetCursor(int winX, int winY)
{
    sCurWinX = (float)winX;
    sCurWinY = (float)winY;
}

int VrKeyboardActive(void)
{
    return GfuiEditboxFocused();
}

void VrKeyboardRender(void)
{
    if (!VrKeyboardActive()) {
        return;
    }
    build();

    int sw, sh, vw, vh;
    GfScrGetSize(&sw, &sh, &vw, &vh);
    glViewport((sw - vw) / 2, (sh - vh) / 2, vw, vh);
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glOrtho(0, GUI_W, 0, GUI_H, -1, 1);
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();

    glDisable(GL_DEPTH_TEST);
    glDisable(GL_TEXTURE_2D);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    float gx, gy; guiCursor(&gx, &gy);
    int hover = keyAt(gx, gy);

    /* backing panel */
    glColor4f(0.05f, 0.05f, 0.10f, 0.85f);
    glBegin(GL_QUADS);
    glVertex2f(15, 15); glVertex2f(GUI_W - 15, 15);
    glVertex2f(GUI_W - 15, 215); glVertex2f(15, 215);
    glEnd();

    for (int i = 0; i < sNumKeys; i++) {
        const VrKey& k = sKeys[i];
        bool isShift = (k.lower == K_SHIFT);
        if (i == sSel) {
            glColor4f(0.90f, 0.65f, 0.20f, 0.98f);   /* stick selection */
        } else if (i == hover) {
            glColor4f(0.35f, 0.55f, 0.90f, 0.95f);
        } else if (isShift && sShift) {
            glColor4f(0.30f, 0.45f, 0.30f, 0.95f);
        } else {
            glColor4f(0.20f, 0.20f, 0.26f, 0.95f);
        }
        glBegin(GL_QUADS);
        glVertex2f(k.x, k.y); glVertex2f(k.x + k.w, k.y);
        glVertex2f(k.x + k.w, k.y + k.h); glVertex2f(k.x, k.y + k.h);
        glEnd();
    }

    /* labels */
    static float white[4] = {1.0f, 1.0f, 1.0f, 1.0f};
    char buf[2] = {0, 0};
    for (int i = 0; i < sNumKeys; i++) {
        const VrKey& k = sKeys[i];
        const char* text = k.label;
        if (!text) {
            buf[0] = sShift ? k.upper : k.lower;
            text = buf;
        }
        int cx = (int)(k.x + k.w / 2);
        int cy = (int)(k.y + k.h / 2 - 8);
        GfuiDrawString(text, white, SD_FONT_MEDIUM_C, cx, cy, 0, SD_ALIGN_HC);
    }

    glDisable(GL_BLEND);
}

int VrKeyboardTryClick(void)
{
    if (!VrKeyboardActive()) {
        return 0;
    }
    build();
    float gx, gy; guiCursor(&gx, &gy);
    int i = keyAt(gx, gy);
    if (i < 0) {
        return 0;
    }
    sSel = i;
    return activateKey(i);
}

/* Move the highlighted selection with the stick. dir: 0=up 1=down 2=left 3=right. */
void VrKeyboardMove(int dir)
{
    if (!VrKeyboardActive()) return;
    build();
    if (sSel < 0) sSel = 0;
    const VrKey& cur = sKeys[sSel];
    int best = -1;
    float bestScore = 1e9f;
    for (int i = 0; i < sNumKeys; i++) {
        if (i == sSel) continue;
        const VrKey& k = sKeys[i];
        float dx = k.cx - cur.cx, dy = k.cy - cur.cy;
        bool ok = false;
        float score = 0;
        if (dir == 2) { ok = (k.row == cur.row && dx < -1.0f); score = -dx; }        /* left  */
        else if (dir == 3) { ok = (k.row == cur.row && dx > 1.0f); score = dx; }     /* right */
        else if (dir == 0) { ok = (dy > 1.0f); score = dy + fabsf(dx) * 2.0f; }      /* up    */
        else if (dir == 1) { ok = (dy < -1.0f); score = -dy + fabsf(dx) * 2.0f; }    /* down  */
        if (ok && score < bestScore) { bestScore = score; best = i; }
    }
    if (best >= 0) sSel = best;
}

/* Activate the highlighted key (stick / button press). */
int VrKeyboardActivate(void)
{
    if (!VrKeyboardActive()) return 0;
    build();
    return activateKey(sSel);
}

} /* extern "C" */
