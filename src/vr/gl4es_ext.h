#ifndef GL4ES_EXT_H
#define GL4ES_EXT_H
/* SpeedDreamsVR additions to gl4es (implemented in third_party/gl4es/src/gl/texture_params.c). */
#include <GL/gl.h>
#ifdef __cplusplus
extern "C" {
#endif
void gl4es_registerExternalTexture(GLuint name, GLenum target, GLsizei width, GLsizei height);
#ifdef __cplusplus
}
#endif
#endif
