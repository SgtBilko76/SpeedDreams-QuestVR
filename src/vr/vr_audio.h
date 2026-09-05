#ifndef VR_AUDIO_H
#define VR_AUDIO_H

/* One OpenAL device/context for the whole process (menu music and race
 * sounds each used to open their own). Also a tiny WAV loader (Speed Dreams uses SDL_LoadWAV, kept for the menu SFX path). */

#ifdef __cplusplus
extern "C" {
#endif

int   VrAudioInit(void);
void  VrAudioShutdown(void);
void* VrAudioDevice(void);     /* ALCdevice*  */
void* VrAudioContext(void);    /* ALCcontext* */

/* RIFF/WAVE PCM (8/16 bit, mono/stereo). *data is malloc'ed; free() it.
 * format is an AL_FORMAT_* enum. Returns 1 on success. */
int VrLoadWav(const char* filename, int* format, void** data, int* size, int* freq);

#ifdef __cplusplus
}
#endif

#endif
