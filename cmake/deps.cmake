# Third-party dependencies, all built from source (static) for arm64-v8a.
#   zlib, libpng, minizip           : third_party/zlib, third_party/libpng (vendored copies)
#   libjpeg-turbo, freetype, SDL2,
#   SDL2_ttf, SDL2_mixer, enet,
#   curl, cJSON, rhash              : git clones in third_party/
#   SOLID                           : Speed Dreams' freesolid submodule
#   gl4es, openal-soft              : third_party/ (gl4es carries local patches)

set(DEP_C_QUIET -Wno-deprecated-non-prototype -Wno-implicit-function-declaration -Wno-int-conversion
    -Wno-deprecated-declarations -Wno-unused-but-set-variable -Wno-unused-function)

# ---------------------------------------------------------------- zlib
set(ZLIB_DIR ${TP_DIR}/zlib)
add_library(zlib STATIC
    ${ZLIB_DIR}/adler32.c ${ZLIB_DIR}/compress.c ${ZLIB_DIR}/crc32.c ${ZLIB_DIR}/deflate.c
    ${ZLIB_DIR}/gzclose.c ${ZLIB_DIR}/gzlib.c ${ZLIB_DIR}/gzread.c ${ZLIB_DIR}/gzwrite.c
    ${ZLIB_DIR}/infback.c ${ZLIB_DIR}/inffast.c ${ZLIB_DIR}/inflate.c ${ZLIB_DIR}/inftrees.c
    ${ZLIB_DIR}/trees.c ${ZLIB_DIR}/uncompr.c ${ZLIB_DIR}/zutil.c)
target_include_directories(zlib PUBLIC ${ZLIB_DIR})
target_compile_definitions(zlib PRIVATE HAVE_UNISTD_H Z_HAVE_UNISTD_H)
target_compile_options(zlib PRIVATE ${DEP_C_QUIET})

# ---------------------------------------------------------------- minizip (from zlib/contrib)
set(MINIZIP_DIR ${ZLIB_DIR}/contrib/minizip)
file(MAKE_DIRECTORY ${GEN_INC}/minizip)
file(COPY ${MINIZIP_DIR}/unzip.h ${MINIZIP_DIR}/zip.h ${MINIZIP_DIR}/ioapi.h ${MINIZIP_DIR}/crypt.h
     DESTINATION ${GEN_INC}/minizip)
add_library(minizip STATIC ${MINIZIP_DIR}/ioapi.c ${MINIZIP_DIR}/unzip.c ${MINIZIP_DIR}/zip.c)
target_include_directories(minizip PUBLIC ${GEN_INC} ${MINIZIP_DIR})
target_link_libraries(minizip PUBLIC zlib)
target_compile_options(minizip PRIVATE ${DEP_C_QUIET})
add_library(minizip::minizip ALIAS minizip)

# ---------------------------------------------------------------- libpng
set(PNG_DIR ${TP_DIR}/libpng)
set(PNG_GEN ${CMAKE_BINARY_DIR}/gen_png)
file(MAKE_DIRECTORY ${PNG_GEN})
configure_file(${PNG_DIR}/scripts/pnglibconf.h.prebuilt ${PNG_GEN}/pnglibconf.h COPYONLY)
add_library(png STATIC
    ${PNG_DIR}/png.c ${PNG_DIR}/pngerror.c ${PNG_DIR}/pngget.c ${PNG_DIR}/pngmem.c
    ${PNG_DIR}/pngpread.c ${PNG_DIR}/pngread.c ${PNG_DIR}/pngrio.c ${PNG_DIR}/pngrtran.c
    ${PNG_DIR}/pngrutil.c ${PNG_DIR}/pngset.c ${PNG_DIR}/pngtrans.c ${PNG_DIR}/pngwio.c
    ${PNG_DIR}/pngwrite.c ${PNG_DIR}/pngwtran.c ${PNG_DIR}/pngwutil.c)
target_include_directories(png PUBLIC ${PNG_DIR} ${PNG_GEN})
target_compile_definitions(png PRIVATE PNG_ARM_NEON_OPT=0)
target_link_libraries(png PUBLIC zlib)

# ---------------------------------------------------------------- libjpeg-turbo
# Its own CMakeLists refuses add_subdirectory(), so the (few) sources are built
# here directly: 8-bit only, no SIMD, no arithmetic coding, no TurboJPEG API.
set(JPEG_DIR ${TP_DIR}/libjpeg-turbo)
set(JPEG_GEN ${CMAKE_BINARY_DIR}/gen_jpeg)
file(MAKE_DIRECTORY ${JPEG_GEN})

set(JPEG_LIB_VERSION 62)
set(VERSION 3.0.4)
set(LIBJPEG_TURBO_VERSION_NUMBER 3000004)
set(BUILD "sdvr")
set(HIDDEN "__attribute__((visibility(\"hidden\")))")
set(INLINE "inline __attribute__((always_inline))")
set(THREAD_LOCAL "__thread")
set(SIZE_T 8)
set(HAVE_BUILTIN_CTZL 1)
configure_file(${JPEG_DIR}/jconfig.h.in    ${JPEG_GEN}/jconfig.h)
configure_file(${JPEG_DIR}/jconfigint.h.in ${JPEG_GEN}/jconfigint.h)
configure_file(${JPEG_DIR}/jversion.h.in   ${JPEG_GEN}/jversion.h)

set(JPEG16_SOURCES jcapistd.c jccolor.c jcdiffct.c jclossls.c jcmainct.c
    jcprepct.c jcsample.c jdapistd.c jdcolor.c jddiffct.c jdlossls.c jdmainct.c
    jdpostct.c jdsample.c jutils.c)
set(JPEG12_SOURCES ${JPEG16_SOURCES} jccoefct.c jcdctmgr.c jdcoefct.c
    jddctmgr.c jdmerge.c jfdctfst.c jfdctint.c jidctflt.c jidctfst.c jidctint.c
    jidctred.c jquant1.c jquant2.c)
set(JPEG_SOURCES ${JPEG12_SOURCES} jcapimin.c jchuff.c jcicc.c jcinit.c
    jclhuff.c jcmarker.c jcmaster.c jcomapi.c jcparam.c jcphuff.c jctrans.c
    jdapimin.c jdatadst.c jdatasrc.c jdhuff.c jdicc.c jdinput.c jdlhuff.c
    jdmarker.c jdmaster.c jdphuff.c jdtrans.c jerror.c jfdctflt.c jmemmgr.c
    jmemnobs.c jpeg_nbits.c)

function(jpeg_prefix out)
    set(l "")
    foreach(f ${ARGN})
        list(APPEND l ${JPEG_DIR}/${f})
    endforeach()
    set(${out} ${l} PARENT_SCOPE)
endfunction()
jpeg_prefix(JPEG16_SRCS ${JPEG16_SOURCES})
jpeg_prefix(JPEG12_SRCS ${JPEG12_SOURCES})
jpeg_prefix(JPEG8_SRCS  ${JPEG_SOURCES})

add_library(jpeg12-static OBJECT ${JPEG12_SRCS})
target_include_directories(jpeg12-static PRIVATE ${JPEG_DIR} ${JPEG_GEN})
target_compile_definitions(jpeg12-static PRIVATE BITS_IN_JSAMPLE=12)
target_compile_options(jpeg12-static PRIVATE ${DEP_C_QUIET})

add_library(jpeg16-static OBJECT ${JPEG16_SRCS})
target_include_directories(jpeg16-static PRIVATE ${JPEG_DIR} ${JPEG_GEN})
target_compile_definitions(jpeg16-static PRIVATE BITS_IN_JSAMPLE=16)
target_compile_options(jpeg16-static PRIVATE ${DEP_C_QUIET})

add_library(jpeg-static STATIC ${JPEG8_SRCS}
    $<TARGET_OBJECTS:jpeg12-static> $<TARGET_OBJECTS:jpeg16-static>)
target_include_directories(jpeg-static PUBLIC ${JPEG_DIR} ${JPEG_GEN})
target_compile_options(jpeg-static PRIVATE ${DEP_C_QUIET})
set(JPEG_INCLUDE ${JPEG_DIR} ${JPEG_GEN})

# ---------------------------------------------------------------- freetype
set(FT_DISABLE_ZLIB ON CACHE BOOL "" FORCE)
set(FT_DISABLE_BZIP2 ON CACHE BOOL "" FORCE)
set(FT_DISABLE_PNG ON CACHE BOOL "" FORCE)
set(FT_DISABLE_HARFBUZZ ON CACHE BOOL "" FORCE)
set(FT_DISABLE_BROTLI ON CACHE BOOL "" FORCE)
set(SKIP_INSTALL_ALL ON)
add_subdirectory(${TP_DIR}/freetype EXCLUDE_FROM_ALL)

# ---------------------------------------------------------------- SDL2 (static, no Java side)
# Only the non-video subsystems are used at runtime: the OpenXR session owns the
# display and there is no SDLActivity.  Video is initialised with the "dummy"
# driver so that SDL_GL_* / mouse calls stay harmless; audio goes through the
# native OpenSL ES backend (SDL_AUDIODRIVER=openslES, see sd_vr.cpp).
set(SDL_SHARED OFF CACHE BOOL "" FORCE)
set(SDL_STATIC ON CACHE BOOL "" FORCE)
set(SDL_STATIC_PIC ON CACHE BOOL "" FORCE)
set(SDL_TEST OFF CACHE BOOL "" FORCE)
set(SDL_TESTS OFF CACHE BOOL "" FORCE)
set(SDL_HIDAPI OFF CACHE BOOL "" FORCE)
set(SDL_SENSOR OFF CACHE BOOL "" FORCE)
set(SDL_RENDER OFF CACHE BOOL "" FORCE)
set(SDL_POWER OFF CACHE BOOL "" FORCE)
set(SDL_LOCALE OFF CACHE BOOL "" FORCE)
set(SDL_MISC OFF CACHE BOOL "" FORCE)
set(SDL_FILESYSTEM OFF CACHE BOOL "" FORCE)
set(SDL_VULKAN OFF CACHE BOOL "" FORCE)
set(SDL_INSTALL OFF CACHE BOOL "" FORCE)
add_subdirectory(${TP_DIR}/SDL2 EXCLUDE_FROM_ALL)
# SDL's JNI_OnLoad registers natives on org.libsdl.app.* classes which are not in
# this APK (and would leave a pending ClassNotFoundException). Rename it away.
target_compile_definitions(SDL2-static PRIVATE JNI_OnLoad=SDL_JNI_OnLoad_unused)
target_compile_options(SDL2-static PRIVATE -fvisibility=default)
set(SDL2_INCLUDE ${TP_DIR}/SDL2/include)

# Speed Dreams includes <SDL2/SDL.h>, <SDL2/SDL_ttf.h>, <SDL2/SDL_opengl.h> in places.
file(MAKE_DIRECTORY ${GEN_INC}/SDL2)
file(GLOB SDL2_HDRS ${TP_DIR}/SDL2/include/*.h)
file(COPY ${SDL2_HDRS} ${TP_DIR}/SDL2_ttf/SDL_ttf.h ${TP_DIR}/SDL2_mixer/include/SDL_mixer.h
     DESTINATION ${GEN_INC}/SDL2)

# ---------------------------------------------------------------- SDL2_ttf (single file on top of freetype)
add_library(SDL2_ttf STATIC ${TP_DIR}/SDL2_ttf/SDL_ttf.c)
target_include_directories(SDL2_ttf PUBLIC ${TP_DIR}/SDL2_ttf)
target_compile_definitions(SDL2_ttf PRIVATE TTF_USE_HARFBUZZ=0)
target_link_libraries(SDL2_ttf PUBLIC SDL2-static freetype)
target_compile_options(SDL2_ttf PRIVATE ${DEP_C_QUIET})

# ---------------------------------------------------------------- SDL2_mixer (WAV + OGG via stb_vorbis + MP3 via minimp3)
set(MIX_DIR ${TP_DIR}/SDL2_mixer)
add_library(SDL2_mixer STATIC
    ${MIX_DIR}/src/mixer.c ${MIX_DIR}/src/effect_position.c ${MIX_DIR}/src/effect_stereoreverse.c
    ${MIX_DIR}/src/effects_internal.c ${MIX_DIR}/src/music.c ${MIX_DIR}/src/utils.c
    ${MIX_DIR}/src/codecs/load_aiff.c ${MIX_DIR}/src/codecs/load_voc.c
    ${MIX_DIR}/src/codecs/music_wav.c ${MIX_DIR}/src/codecs/music_ogg_stb.c
    ${MIX_DIR}/src/codecs/music_minimp3.c ${MIX_DIR}/src/codecs/mp3utils.c)
target_include_directories(SDL2_mixer PUBLIC ${MIX_DIR}/include PRIVATE ${MIX_DIR}/src ${MIX_DIR}/src/codecs)
target_compile_definitions(SDL2_mixer PRIVATE MUSIC_WAV MUSIC_OGG OGG_USE_STB MUSIC_MP3_MINIMP3)
target_link_libraries(SDL2_mixer PUBLIC SDL2-static)
target_compile_options(SDL2_mixer PRIVATE ${DEP_C_QUIET})

# ---------------------------------------------------------------- enet
add_subdirectory(${TP_DIR}/enet EXCLUDE_FROM_ALL)
# Only .../include: .../include/enet holds time.h and list.h, which would shadow
# the libc / libc++ headers of the same name.
target_include_directories(enet PUBLIC ${TP_DIR}/enet/include)
target_compile_options(enet PRIVATE ${DEP_C_QUIET})

# ---------------------------------------------------------------- curl (HTTP only, no TLS)
set(BUILD_CURL_EXE OFF CACHE BOOL "" FORCE)
set(BUILD_STATIC_LIBS ON CACHE BOOL "" FORCE)
set(BUILD_STATIC_CURL OFF CACHE BOOL "" FORCE)
set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(BUILD_LIBCURL_DOCS OFF CACHE BOOL "" FORCE)
set(BUILD_MISC_DOCS OFF CACHE BOOL "" FORCE)
set(ENABLE_CURL_MANUAL OFF CACHE BOOL "" FORCE)
set(CURL_ENABLE_SSL OFF CACHE BOOL "" FORCE)
set(CURL_USE_OPENSSL OFF CACHE BOOL "" FORCE)
set(CURL_USE_LIBPSL OFF CACHE BOOL "" FORCE)
set(CURL_USE_LIBSSH2 OFF CACHE BOOL "" FORCE)
set(USE_LIBIDN2 OFF CACHE BOOL "" FORCE)
set(USE_NGHTTP2 OFF CACHE BOOL "" FORCE)
set(CURL_ZLIB OFF CACHE BOOL "" FORCE)
set(CURL_BROTLI OFF CACHE BOOL "" FORCE)
set(CURL_ZSTD OFF CACHE BOOL "" FORCE)
set(HTTP_ONLY ON CACHE BOOL "" FORCE)
set(CURL_DISABLE_INSTALL ON CACHE BOOL "" FORCE)
set(CURL_CA_BUNDLE "none" CACHE STRING "" FORCE)
set(CURL_CA_PATH "none" CACHE STRING "" FORCE)
add_subdirectory(${TP_DIR}/curl EXCLUDE_FROM_ALL)
set(CURL_INCLUDE ${TP_DIR}/curl/include)

# ---------------------------------------------------------------- cJSON
file(MAKE_DIRECTORY ${GEN_INC}/cjson)
file(COPY ${TP_DIR}/cJSON/cJSON.h DESTINATION ${GEN_INC}/cjson)
add_library(cjson STATIC ${TP_DIR}/cJSON/cJSON.c)
target_include_directories(cjson PUBLIC ${GEN_INC} ${TP_DIR}/cJSON)

# ---------------------------------------------------------------- rhash (librhash only, sha256 is all SD needs)
file(GLOB RHASH_SRCS ${TP_DIR}/rhash/librhash/*.c)
list(FILTER RHASH_SRCS EXCLUDE REGEX "plug_openssl|test_lib|test_utils")
add_library(rhash STATIC ${RHASH_SRCS})
target_include_directories(rhash PUBLIC ${TP_DIR}/rhash/librhash)
# RHASH_XVERSION is normally passed by rhash's own makefiles (0xMMmmpp).
target_compile_definitions(rhash PRIVATE NO_IMPORT_EXPORT RHASH_XVERSION=0x01040500)
target_compile_options(rhash PRIVATE ${DEP_C_QUIET})
add_library(rhash::rhash ALIAS rhash)

# ---------------------------------------------------------------- SOLID (Speed Dreams' freesolid submodule)
add_subdirectory(${SD_ROOT}/freesolid ${CMAKE_BINARY_DIR}/freesolid EXCLUDE_FROM_ALL)
foreach(t solid moto broad)
    target_compile_options(${t} PRIVATE -Wno-deprecated-declarations -Wno-unused-variable)
endforeach()

# ---------------------------------------------------------------- gl4es
set(NOEGL ON CACHE BOOL "" FORCE)
set(NOX11 ON CACHE BOOL "" FORCE)
set(STATICLIB ON CACHE BOOL "" FORCE)
set(NO_INIT_CONSTRUCTOR ON CACHE BOOL "" FORCE)
set(NO_LOADER OFF CACHE BOOL "" FORCE)
set(USE_ANDROID_LOG ON CACHE BOOL "" FORCE)
set(DEFAULT_ES 2 CACHE STRING "" FORCE)
set(GBM OFF CACHE BOOL "" FORCE)
add_subdirectory(${TP_DIR}/gl4es EXCLUDE_FROM_ALL)
set(GL4ES_INCLUDE ${TP_DIR}/gl4es/include)
# gl4es compiles with -fvisibility=hidden; the core must export gl* to the dlopen-ed modules.
target_compile_options(GL PRIVATE -fvisibility=default)

# ---------------------------------------------------------------- openal-soft
set(LIBTYPE STATIC CACHE STRING "" FORCE)
set(ALSOFT_UTILS OFF CACHE BOOL "" FORCE)
set(ALSOFT_EXAMPLES OFF CACHE BOOL "" FORCE)
set(ALSOFT_TESTS OFF CACHE BOOL "" FORCE)
set(ALSOFT_INSTALL OFF CACHE BOOL "" FORCE)
set(ALSOFT_INSTALL_CONFIG OFF CACHE BOOL "" FORCE)
set(ALSOFT_INSTALL_HRTF_DATA OFF CACHE BOOL "" FORCE)
set(ALSOFT_INSTALL_AMBDEC_PRESETS OFF CACHE BOOL "" FORCE)
set(ALSOFT_INSTALL_EXAMPLES OFF CACHE BOOL "" FORCE)
set(ALSOFT_INSTALL_UTILS OFF CACHE BOOL "" FORCE)
set(ALSOFT_UPDATE_BUILD_VERSION OFF CACHE BOOL "" FORCE)
set(ALSOFT_BACKEND_OPENSL ON CACHE BOOL "" FORCE)
set(ALSOFT_REQUIRE_OPENSL ON CACHE BOOL "" FORCE)
set(ALSOFT_BACKEND_OBOE OFF CACHE BOOL "" FORCE)
set(ALSOFT_BACKEND_WAVE OFF CACHE BOOL "" FORCE)
set(ALSOFT_EAX OFF CACHE BOOL "" FORCE)
set(ALSOFT_RTKIT OFF CACHE BOOL "" FORCE)
add_subdirectory(${TP_DIR}/openal-soft EXCLUDE_FROM_ALL)
set(OPENAL_INCLUDE ${TP_DIR}/openal-soft/include)
foreach(t OpenAL common alcommon)
    if(TARGET ${t})
        set_target_properties(${t} PROPERTIES C_VISIBILITY_PRESET default CXX_VISIBILITY_PRESET default)
        target_compile_options(${t} PRIVATE -fvisibility=default)
    endif()
endforeach()
