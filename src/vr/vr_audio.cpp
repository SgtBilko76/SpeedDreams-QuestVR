/*
 * vr_audio.cpp - shared OpenAL device/context + WAV loader for Speed Dreams VR.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#include <AL/al.h>
#include <AL/alc.h>

#include "vr_audio.h"
#include "vr_log.h"

static ALCdevice* sDevice = NULL;
static ALCcontext* sContext = NULL;

extern "C" {

int VrAudioInit(void)
{
    if (sDevice) {
        return 0;
    }
    /* Cheaper resampler: the default cubic spline costs ~4-5% CPU; linear is
     * plenty for engine loops. Written next to the config and pointed at with
     * ALSOFT_CONF before the device opens. */
    {
        const char* base = getenv("SDVR_DATA_DIR");
        char confpath[1024];
        snprintf(confpath, sizeof(confpath), "%s/.speed-dreams/alsoft.conf", base && base[0] ? base : "/sdcard/SpeedDreamsVR");
        FILE* cf = fopen(confpath, "w");
        if (cf) {
            fputs("[general]\nresampler = linear\n", cf);
            fclose(cf);
            setenv("ALSOFT_CONF", confpath, 1);
            ALOGI("VrAudioInit: ALSOFT_CONF=%s (linear resampler)", confpath);
        }
    }
    sDevice = alcOpenDevice(NULL);
    if (!sDevice) {
        ALOGE("VrAudioInit: alcOpenDevice failed");
        return -1;
    }
    sContext = alcCreateContext(sDevice, NULL);
    if (!sContext) {
        ALOGE("VrAudioInit: alcCreateContext failed");
        alcCloseDevice(sDevice);
        sDevice = NULL;
        return -1;
    }
    alcMakeContextCurrent(sContext);
    alcGetError(sDevice);
    alGetError();
    ALOGI("VrAudioInit: OpenAL %s / %s", alGetString(AL_VERSION), alGetString(AL_RENDERER));
    return 0;
}

void VrAudioShutdown(void)
{
    if (sContext) {
        alcMakeContextCurrent(NULL);
        alcDestroyContext(sContext);
        sContext = NULL;
    }
    if (sDevice) {
        alcCloseDevice(sDevice);
        sDevice = NULL;
    }
}

void* VrAudioDevice(void)
{
    if (!sDevice) {
        VrAudioInit();
    }
    return sDevice;
}

void* VrAudioContext(void)
{
    if (!sContext) {
        VrAudioInit();
    }
    return sContext;
}

static uint32_t rd32(const unsigned char* p) { return p[0] | (p[1] << 8) | (p[2] << 16) | ((uint32_t)p[3] << 24); }
static uint16_t rd16(const unsigned char* p) { return p[0] | (p[1] << 8); }

int VrLoadWav(const char* filename, int* format, void** data, int* size, int* freq)
{
    *data = NULL;
    *size = 0;
    FILE* f = fopen(filename, "rb");
    if (!f) {
        ALOGE("VrLoadWav: cannot open %s", filename);
        return 0;
    }
    unsigned char hdr[12];
    if (fread(hdr, 1, 12, f) != 12 || memcmp(hdr, "RIFF", 4) != 0 || memcmp(hdr + 8, "WAVE", 4) != 0) {
        ALOGE("VrLoadWav: %s is not a RIFF/WAVE file", filename);
        fclose(f);
        return 0;
    }
    int channels = 0, bits = 0, rate = 0;
    int haveFmt = 0;
    unsigned char ch[8];
    while (fread(ch, 1, 8, f) == 8) {
        uint32_t csize = rd32(ch + 4);
        if (memcmp(ch, "fmt ", 4) == 0) {
            unsigned char fmt[16];
            if (csize < 16 || fread(fmt, 1, 16, f) != 16) {
                break;
            }
            int tag = rd16(fmt);
            channels = rd16(fmt + 2);
            rate = (int)rd32(fmt + 4);
            bits = rd16(fmt + 14);
            if (tag != 1) {
                ALOGE("VrLoadWav: %s: unsupported format tag %d", filename, tag);
                fclose(f);
                return 0;
            }
            haveFmt = 1;
            if (csize > 16) {
                fseek(f, csize - 16, SEEK_CUR);
            }
        } else if (memcmp(ch, "data", 4) == 0) {
            if (!haveFmt) {
                break;
            }
            void* buf = malloc(csize);
            if (!buf) {
                break;
            }
            size_t got = fread(buf, 1, csize, f);
            fclose(f);
            if (channels == 1) {
                *format = bits == 8 ? AL_FORMAT_MONO8 : AL_FORMAT_MONO16;
            } else {
                *format = bits == 8 ? AL_FORMAT_STEREO8 : AL_FORMAT_STEREO16;
            }
            *data = buf;
            *size = (int)got;
            *freq = rate;
            return 1;
        } else {
            fseek(f, csize + (csize & 1), SEEK_CUR);
        }
    }
    ALOGE("VrLoadWav: %s: no data chunk", filename);
    fclose(f);
    return 0;
}

} /* extern "C" */
