/* config.h for the Android / Meta Quest build of Speed Dreams 2.4 (hand written,
 * mirrors what cmake/config.h.in.cmake would generate on Linux). */
#ifndef SD_ANDROID_CONFIG_H
#define SD_ANDROID_CONFIG_H

#define HAVE_INTTYPES_H 1
#define HAVE_LIBDL 1
#define HAVE_LIBGL 1
#define HAVE_LIBGLU 1
#define HAVE_LIBM 1
#define HAVE_LIBOPENAL 1
#define HAVE_LIBPLIBSG 1
#define HAVE_LIBPLIBSSG 1
#define HAVE_LIBPLIBSSGAUX 1
/* plib "sl" (software sound) is not built on the Quest: OpenAL only.
 * HAVE_LIBPLIBUL gates the plib sound backend in snddefault/grsound.cpp. */
/* #undef HAVE_LIBPLIBUL */
#define HAVE_LIBPNG 1
#define HAVE_LIBZ 1
#define HAVE_MEMORY_H 1
#define HAVE_STDINT_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRINGS_H 1
#define HAVE_STRING_H 1
#define HAVE_STRNDUP 1
#define HAVE_STRTOK_R 1
#define HAVE_ISNAN 1
#define HAVE_SYS_STAT_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_UNISTD_H 1

#define PACKAGE "speed-dreams"
#define PACKAGE_BUGREPORT ""
#define PACKAGE_NAME ""
#define PACKAGE_STRING ""
#define PACKAGE_TARNAME ""
#define PACKAGE_VERSION ""
#define STDC_HEADERS 1
#define TIME_WITH_SYS_TIME 1

#ifndef VERSION_LONG
#define VERSION_LONG "v2.4.2-quest"
#endif

#define SD_BUILD_INFO_SYSTEM "Android (Meta Quest)"
#define SD_BUILD_INFO_CMAKE_VERSION "3.22"
#define SD_BUILD_INFO_CMAKE_GENERATOR "Ninja"
#define SD_BUILD_INFO_COMPILER_VERSION "clang (NDK)"
#define SD_BUILD_INFO_CONFIGURATION "Release"
#define SD_BUILD_INFO_COMPILER_NAME "Clang"

/* Default directories: all four are passed explicitly on the (synthetic) command
 * line by sd_vr.cpp (-dd/-lc/-ld/-bd), these are only fallbacks. */
#define SD_DATADIR "/sdcard/SpeedDreamsVR/data/"
#define SD_DATADIR_ABS "/sdcard/SpeedDreamsVR/data/"
#define SD_DATADIR_INSTALL_PREFIX "/sdcard/SpeedDreamsVR/data/"
#define SD_LIBDIR "/sdcard/SpeedDreamsVR/data/"
#define SD_BINDIR "/sdcard/SpeedDreamsVR/"
#define SD_LOCALDIR "/sdcard/SpeedDreamsVR/.speed-dreams/"

#endif
