/*
 * vr_paths.cpp - data / user-settings directory setup for Speed Dreams on Android.
 *
 * On desktop, Speed Dreams uses four directories (data, lib, bin, local).  On the
 * Quest there is only one writable place the user can push files to, so:
 *
 *   /sdcard/SpeedDreamsVR/data/           <- the whole installed data tree (adb push)
 *   /sdcard/SpeedDreamsVR/.speed-dreams/  <- user settings (config/, results/, drivers/)
 *
 * The user settings tree is populated by Speed Dreams itself (GfFileSetup() copies
 * every file listed in <data>/user-files); we only create the directory and make
 * sure it is writable before the framework starts.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <pthread.h>
#include <dirent.h>
#include <sys/stat.h>
#include <sys/types.h>

#include "vr_paths.h"
#include "vr_log.h"

static char gBaseDir[1024];
static char gDataDir[1024];
static char gLocalDir[1024];

/* ------------------------------------------------------------------ logcat */
static void* stdioPumpThread(void* arg)
{
    int fd = (int)(intptr_t)arg;
    char buf[1024];
    size_t used = 0;
    for (;;) {
        ssize_t n = read(fd, buf + used, sizeof(buf) - 1 - used);
        if (n <= 0) {
            if (used) {
                buf[used] = 0;
                __android_log_write(ANDROID_LOG_INFO, VR_LOG_TAG, buf);
            }
            break;
        }
        used += n;
        buf[used] = 0;
        char* start = buf;
        char* nl;
        while ((nl = strchr(start, '\n')) != NULL) {
            *nl = 0;
            if (nl > start) {
                __android_log_write(ANDROID_LOG_INFO, VR_LOG_TAG, start);
            }
            start = nl + 1;
        }
        used = strlen(start);
        memmove(buf, start, used + 1);
        if (used == sizeof(buf) - 1) {
            __android_log_write(ANDROID_LOG_INFO, VR_LOG_TAG, buf);
            used = 0;
        }
    }
    close(fd);
    return NULL;
}

extern "C" void VrLogRedirectStdio(void)
{
    int fds[2];
    if (pipe(fds) != 0) {
        return;
    }
    setvbuf(stdout, NULL, _IOLBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);
    dup2(fds[1], STDOUT_FILENO);
    dup2(fds[1], STDERR_FILENO);
    close(fds[1]);
    pthread_t t;
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    pthread_create(&t, &attr, stdioPumpThread, (void*)(intptr_t)fds[0]);
    pthread_attr_destroy(&attr);
}

/* ------------------------------------------------------------------ files */
static bool isDir(const char* path)
{
    struct stat st;
    return stat(path, &st) == 0 && S_ISDIR(st.st_mode);
}

static int mkdirP(const char* path)
{
    char tmp[1024];
    snprintf(tmp, sizeof(tmp), "%s", path);
    size_t len = strlen(tmp);
    if (len && tmp[len - 1] == '/') {
        tmp[len - 1] = 0;
    }
    for (char* p = tmp + 1; *p; p++) {
        if (*p == '/') {
            *p = 0;
            if (mkdir(tmp, 0775) != 0 && errno != EEXIST) {
                return -1;
            }
            *p = '/';
        }
    }
    if (mkdir(tmp, 0775) != 0 && errno != EEXIST) {
        return -1;
    }
    return 0;
}

/* ------------------------------------------------------------------ init */
extern "C" int VrPathsInit(const char* base)
{
    char tmp[1024];
    snprintf(gBaseDir, sizeof(gBaseDir), "%s/", base);
    snprintf(gDataDir, sizeof(gDataDir), "%s/data/", base);
    snprintf(gLocalDir, sizeof(gLocalDir), "%s/.speed-dreams/", base);

    if (!isDir(base)) {
        ALOGE("VrPathsInit: %s does not exist (push the game data first)", base);
        return -1;
    }

    snprintf(tmp, sizeof(tmp), "%s/data", base);
    if (!isDir(tmp)) {
        ALOGE("VrPathsInit: %s missing: game data not pushed?", tmp);
        return -1;
    }

    /* User settings tree. GfFileSetup() fills it from <data>/user-files, but the
     * directories have to exist first (GfParmWriteFile does not create them). */
    snprintf(tmp, sizeof(tmp), "%s/.speed-dreams/config/raceman", base);
    mkdirP(tmp);
    snprintf(tmp, sizeof(tmp), "%s/.speed-dreams/config/raceman/extra", base);
    mkdirP(tmp);
    snprintf(tmp, sizeof(tmp), "%s/.speed-dreams/results", base);
    mkdirP(tmp);
    snprintf(tmp, sizeof(tmp), "%s/.speed-dreams/drivers/human", base);
    mkdirP(tmp);
    snprintf(tmp, sizeof(tmp), "%s/.speed-dreams/drivers/networkhuman", base);
    mkdirP(tmp);
    snprintf(tmp, sizeof(tmp), "%s/.speed-dreams/cars", base);
    mkdirP(tmp);
    snprintf(tmp, sizeof(tmp), "%s/.speed-dreams/tmp", base);
    mkdirP(tmp);

    /* Speed Dreams opens several files by a path relative to the data dir
     * (GfFileSetup, for one), so make it the working directory. main.cpp does
     * this too, but do it here as well and report the result. */
    if (chdir(gDataDir) != 0) {
        ALOGE("VrPathsInit: chdir(%s) failed: %s", gDataDir, strerror(errno));
    }
    char cwd[1024];
    if (getcwd(cwd, sizeof(cwd))) {
        ALOGI("VrPathsInit: cwd=%s", cwd);
    }

    ALOGI("VrPathsInit: data=%s local=%s", gDataDir, gLocalDir);
    return 0;
}

extern "C" const char* VrBaseDir(void)  { return gBaseDir;  }
extern "C" const char* VrDataDir(void)  { return gDataDir;  }
extern "C" const char* VrLocalDir(void) { return gLocalDir; }
