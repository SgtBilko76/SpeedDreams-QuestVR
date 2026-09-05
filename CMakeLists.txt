cmake_minimum_required(VERSION 3.22)
project(sdvr C CXX)

# Speed Dreams 2.4 on Meta Quest (standalone, OpenXR). Same structure as TorcsVR:
#   - one core shared library (libsdvr.so) = Team Beef OpenXR framework + VR glue
#     + every Speed Dreams core library (tgf, tgfclient, tgfdata, robottools, ...)
#     + all third-party deps, linked with --whole-archive so that the dlopen-ed
#     modules can resolve every symbol against it,
#   - one libsd_<name>.so per Speed Dreams module / robot, dlopen-ed by name.

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(BUILD_SHARED_LIBS OFF)

# OpenXR loader + headers via the Maven AAR (prefab).
find_package(OpenXR REQUIRED CONFIG)

# Speed Dreams source tree (git repo, branch quest-port).
set(SD_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../speed-dreams-code" CACHE PATH "Speed Dreams source tree")
get_filename_component(SD_ROOT "${SD_ROOT}" ABSOLUTE)
if(NOT EXISTS "${SD_ROOT}/src/libs/tgf/tgf.h")
    message(FATAL_ERROR "SD_ROOT=${SD_ROOT} does not look like the Speed Dreams source tree")
endif()
set(SD_SRC ${SD_ROOT}/src)

set(VR_DIR ${CMAKE_CURRENT_SOURCE_DIR}/src/vr)
set(TP_DIR ${CMAKE_CURRENT_SOURCE_DIR}/third_party)
set(GEN_INC ${CMAKE_BINARY_DIR}/gen_include)
file(MAKE_DIRECTORY ${GEN_INC})

include(cmake/deps.cmake)     # zlib, png, jpeg, freetype, SDL2(+ttf,+mixer), enet, curl, cJSON, rhash, minizip, SOLID, gl4es, openal-soft
include(cmake/plib.cmake)     # plib ul/sg/ssg/ssgAux

# ---------------------------------------------------------------------------
# Core: Team Beef OpenXR framework + VR glue + all Speed Dreams core libraries.
# ---------------------------------------------------------------------------
add_library(sdvr SHARED
    ${VR_DIR}/tbxr/TBXR_Common.c
    ${VR_DIR}/tbxr/OpenXrInput.c
    ${VR_DIR}/sd_vr.cpp
    ${VR_DIR}/vr_paths.cpp
    ${VR_DIR}/vr_events.cpp
    ${VR_DIR}/vr_input.cpp
    ${VR_DIR}/vr_audio.cpp
    ${VR_DIR}/vr_stereo.cpp
    ${VR_DIR}/vr_config.cpp
    ${VR_DIR}/vr_rtti.cpp
    ${VR_DIR}/vr_keyboard.cpp
    ${VR_DIR}/vr_perf.c
    ${VR_DIR}/glu_shim.cpp
    ${SD_SRC}/main/main.cpp
)
set_source_files_properties(${SD_SRC}/main/main.cpp PROPERTIES COMPILE_DEFINITIONS "main=SdMain")

include(cmake/sd.cmake)       # SD libs (static) + modules/robots (shared, link sdvr)

target_include_directories(sdvr PRIVATE
    ${VR_DIR}
    ${VR_DIR}/tbxr
    ${GL4ES_INCLUDE}
)
target_compile_definitions(sdvr PRIVATE ANDROID)
add_dependencies(sdvr sdl_headers_copy)
target_compile_options(sdvr PRIVATE -Wall -Wno-unused-parameter -Wno-unused-variable -Wno-unused-function)

target_link_libraries(sdvr PRIVATE
    sd_headers
    -Wl,--whole-archive
    ${SD_CORE_LIBS}
    GL
    OpenAL
    -Wl,--no-whole-archive
    OpenXR::openxr_loader
    EGL
    OpenSLES
    android
    log
)
# -z global: put this library in the linker's *global* group, so every module
# dlopen-ed later resolves against it first. Without it each module binds to its
# own weak copy of the C++ type_info for the module interfaces, and the
# dynamic_cast in GfModule::getInterface() fails (this is what -Wl,-E gives the
# desktop executable). Re-dlopen-ing with RTLD_GLOBAL does not promote a library
# on Android, so it has to be set at link time.
target_link_options(sdvr PRIVATE -Wl,-z,max-page-size=16384 -Wl,-z,global)
