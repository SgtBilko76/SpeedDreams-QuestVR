#ifndef VR_PATHS_H
#define VR_PATHS_H

#ifdef __cplusplus
extern "C" {
#endif

/* Redirect stdout/stderr into logcat (tag "SpeedDreamsVR"). */
void VrLogRedirectStdio(void);

/* Prepare the directory layout under <base> (e.g. /sdcard/SpeedDreamsVR):
 *   <base>/data/            the game data (pushed with adb, = the install datadir)
 *   <base>/lib/             unused (modules live in the APK)
 *   <base>/.speed-dreams/   user settings, seeded from <base>/data/... on first run
 * Returns 0 when <base>/data exists. */
int VrPathsInit(const char* base);

const char* VrBaseDir(void);    /* "<base>/"                */
const char* VrDataDir(void);    /* "<base>/data/"           */
const char* VrLocalDir(void);   /* "<base>/.speed-dreams/"  */

#ifdef __cplusplus
}
#endif

#endif
