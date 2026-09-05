# plib r2173 (vendored copy from the TORCS tree, with the two Android patches:
# ul.h does not define UL_GLX, ssg.cxx does not probe glX for a current context).
# Built: ul, sg, ssg, ssgAux. js/sl/sm are not built (joystick is virtual, sound is OpenAL).

set(PLIB_SRC ${TP_DIR}/plib/src)

# Headers are included by Speed Dreams as <plib/xxx.h>: build a flat plib/ include dir.
file(MAKE_DIRECTORY ${GEN_INC}/plib)
file(GLOB PLIB_HDRS
    ${PLIB_SRC}/util/*.h ${PLIB_SRC}/sg/*.h ${PLIB_SRC}/ssg/*.h ${PLIB_SRC}/ssgAux/*.h
    ${PLIB_SRC}/js/*.h ${PLIB_SRC}/sl/*.h)
file(COPY ${PLIB_HDRS} DESTINATION ${GEN_INC}/plib)

set(PLIB_FLAGS -fno-strict-aliasing -Wno-write-strings -Wno-narrowing -Wno-deprecated-declarations
    -Wno-register -Wno-unused-result -Wno-format-security -Wno-error=format-security)

add_library(plib_ul STATIC
    ${PLIB_SRC}/util/ul.cxx ${PLIB_SRC}/util/ulClock.cxx ${PLIB_SRC}/util/ulError.cxx
    ${PLIB_SRC}/util/ulLinkedList.cxx ${PLIB_SRC}/util/ulList.cxx ${PLIB_SRC}/util/ulRTTI.cxx)
target_include_directories(plib_ul PUBLIC ${PLIB_SRC}/util)
target_compile_options(plib_ul PRIVATE ${PLIB_FLAGS})

add_library(plib_sg STATIC
    ${PLIB_SRC}/sg/sg.cxx ${PLIB_SRC}/sg/sgIsect.cxx ${PLIB_SRC}/sg/sgPerlinNoise.cxx
    ${PLIB_SRC}/sg/sgd.cxx ${PLIB_SRC}/sg/sgdIsect.cxx)
target_include_directories(plib_sg PUBLIC ${PLIB_SRC}/sg)
target_link_libraries(plib_sg PUBLIC plib_ul)
target_compile_options(plib_sg PRIVATE ${PLIB_FLAGS})

file(GLOB PLIB_SSG_SRCS ${PLIB_SRC}/ssg/*.cxx)
add_library(plib_ssg STATIC ${PLIB_SSG_SRCS})
target_include_directories(plib_ssg PUBLIC ${PLIB_SRC}/ssg ${GL4ES_INCLUDE})
target_link_libraries(plib_ssg PUBLIC plib_sg plib_ul png)
target_compile_options(plib_ssg PRIVATE ${PLIB_FLAGS})
set_source_files_properties(${PLIB_SRC}/ssg/ssgLoadFLT.cxx PROPERTIES COMPILE_DEFINITIONS "ushort=unsigned short")

file(GLOB PLIB_SSGAUX_SRCS ${PLIB_SRC}/ssgAux/*.cxx)
add_library(plib_ssgaux STATIC ${PLIB_SSGAUX_SRCS})
target_include_directories(plib_ssgaux PUBLIC ${PLIB_SRC}/ssgAux)
target_link_libraries(plib_ssgaux PUBLIC plib_ssg)
target_compile_options(plib_ssgaux PRIVATE ${PLIB_FLAGS})
