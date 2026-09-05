#ifndef VR_CONFIG_H
#define VR_CONFIG_H

/* Tiny key=value config: <base>/vr.cfg (seeded from templates/vr.cfg). */

#ifdef __cplusplus
extern "C" {
#endif

void  VrConfigLoad(const char* path);
float VrConfigGetFloat(const char* key, float def);
int   VrConfigGetInt(const char* key, int def);

#ifdef __cplusplus
}
#endif

#endif
