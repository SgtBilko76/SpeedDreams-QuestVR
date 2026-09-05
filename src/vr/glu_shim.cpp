/*
 * glu_shim.cpp - the handful of GLU functions Speed Dreams/plib use, on top of gl4es.
 */

#include <math.h>
#include <string.h>

#include <GL/gl.h>
#include <GL/glu.h>

extern "C" {

void gluOrtho2D(GLdouble left, GLdouble right, GLdouble bottom, GLdouble top)
{
    glOrtho(left, right, bottom, top, -1.0, 1.0);
}

void gluPerspective(GLdouble fovy, GLdouble aspect, GLdouble zNear, GLdouble zFar)
{
    GLdouble ymax = zNear * tan(fovy * M_PI / 360.0);
    GLdouble xmax = ymax * aspect;
    glFrustum(-xmax, xmax, -ymax, ymax, zNear, zFar);
}

void gluLookAt(GLdouble eyex, GLdouble eyey, GLdouble eyez,
               GLdouble centerx, GLdouble centery, GLdouble centerz,
               GLdouble upx, GLdouble upy, GLdouble upz)
{
    float f[3] = {(float)(centerx - eyex), (float)(centery - eyey), (float)(centerz - eyez)};
    float len = sqrtf(f[0] * f[0] + f[1] * f[1] + f[2] * f[2]);
    if (len > 0) { f[0] /= len; f[1] /= len; f[2] /= len; }
    float up[3] = {(float)upx, (float)upy, (float)upz};
    float s[3] = {f[1] * up[2] - f[2] * up[1], f[2] * up[0] - f[0] * up[2], f[0] * up[1] - f[1] * up[0]};
    len = sqrtf(s[0] * s[0] + s[1] * s[1] + s[2] * s[2]);
    if (len > 0) { s[0] /= len; s[1] /= len; s[2] /= len; }
    float u[3] = {s[1] * f[2] - s[2] * f[1], s[2] * f[0] - s[0] * f[2], s[0] * f[1] - s[1] * f[0]};
    float m[16] = {
        s[0], u[0], -f[0], 0,
        s[1], u[1], -f[1], 0,
        s[2], u[2], -f[2], 0,
        0, 0, 0, 1};
    glMultMatrixf(m);
    glTranslatef((float)-eyex, (float)-eyey, (float)-eyez);
}

/* gl4es honours GL_GENERATE_MIPMAP; upload level 0 and let it build the chain. */
GLint gluBuild2DMipmaps(GLenum target, GLint internalFormat, GLsizei width, GLsizei height,
                        GLenum format, GLenum type, const void* data)
{
    glTexParameteri(target, 0x8191 /* GL_GENERATE_MIPMAP */, GL_TRUE);
    glTexImage2D(target, 0, internalFormat, width, height, 0, format, type, data);
    return 0;
}

const GLubyte* gluErrorString(GLenum errorCode)
{
    switch (errorCode) {
    case GL_NO_ERROR: return (const GLubyte*)"no error";
    case GL_INVALID_ENUM: return (const GLubyte*)"invalid enumerant";
    case GL_INVALID_VALUE: return (const GLubyte*)"invalid value";
    case GL_INVALID_OPERATION: return (const GLubyte*)"invalid operation";
    case GL_STACK_OVERFLOW: return (const GLubyte*)"stack overflow";
    case GL_STACK_UNDERFLOW: return (const GLubyte*)"stack underflow";
    case GL_OUT_OF_MEMORY: return (const GLubyte*)"out of memory";
    }
    return (const GLubyte*)"unknown GL error";
}

const GLubyte* gluGetString(GLenum name)
{
    if (name == GLU_VERSION) return (const GLubyte*)"1.3 (sdvr shim)";
    if (name == GLU_EXTENSIONS) return (const GLubyte*)"";
    return (const GLubyte*)"";
}

} /* extern "C" */
