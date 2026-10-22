cmake_minimum_required(VERSION 3.16)
project(aegisubtest C CXX)

set(AEGISUB_SRC "" CACHE PATH "Aegisub v3.5.1 source root")
set(AEGISUB_PREFIX "" CACHE PATH "OHOS static dependency prefix")
set(AEGISUB_BUILD "" CACHE PATH "Meson build dir containing libaegisub.a")

if(NOT AEGISUB_SRC OR NOT AEGISUB_PREFIX OR NOT AEGISUB_BUILD)
    message(FATAL_ERROR "Pass -DAEGISUB_SRC=... -DAEGISUB_PREFIX=... -DAEGISUB_BUILD=...")
endif()

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# All upstream core tests except language_match (it includes src/language_match.h,
# which needs wxWidgets; the GUI is not part of the core-only build).
file(GLOB TEST_SOURCES "${AEGISUB_SRC}/tests/tests/*.cpp")
list(REMOVE_ITEM TEST_SOURCES "${AEGISUB_SRC}/tests/tests/language_match.cpp")

add_library(aegisubtest SHARED
    napi_init.cpp
    test_runner.cpp
    ${AEGISUB_SRC}/tests/support/util.cpp
    ${TEST_SOURCES})

target_include_directories(aegisubtest PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${AEGISUB_SRC}/libaegisub/include
    ${AEGISUB_SRC}/tests/support
    ${AEGISUB_SRC}/subprojects/iconv/include
    ${AEGISUB_PREFIX}/include
    ${AEGISUB_PREFIX}/include/luajit-2.1)

target_compile_definitions(aegisubtest PRIVATE
    _FILE_OFFSET_BITS=64
    _LARGEFILE_SOURCE)

target_compile_options(aegisubtest PRIVATE
    -O2
    -fPIC
    -fexceptions
    -Wno-deprecated-declarations)

set(AEGISUB_STATIC_LIBS
    ${AEGISUB_BUILD}/libaegisub/libaegisub.a
    ${AEGISUB_BUILD}/subprojects/luabins/libluabins.a
    ${AEGISUB_BUILD}/subprojects/iconv/libiconv.a
    ${AEGISUB_PREFIX}/lib/libgtest.a
    ${AEGISUB_PREFIX}/lib/libgmock.a
    ${AEGISUB_PREFIX}/lib/libboost_locale.a
    ${AEGISUB_PREFIX}/lib/libboost_regex.a
    ${AEGISUB_PREFIX}/lib/libboost_thread.a
    ${AEGISUB_PREFIX}/lib/libboost_chrono.a
    ${AEGISUB_PREFIX}/lib/libboost_filesystem.a
    ${AEGISUB_PREFIX}/lib/libboost_system.a
    ${AEGISUB_PREFIX}/lib/libicui18n.a
    ${AEGISUB_PREFIX}/lib/libicuuc.a
    ${AEGISUB_PREFIX}/lib/libicudata.a
    ${AEGISUB_PREFIX}/lib/libluajit-5.1.a
    ${AEGISUB_PREFIX}/lib/libz.a)

target_link_libraries(aegisubtest PUBLIC
    libace_napi.z.so
    libhilog_ndk.z.so)

# --start-group is needed for the circular static deps (ICU / Boost / libaegisub).
target_link_libraries(aegisubtest PRIVATE
    "-Wl,--start-group"
    ${AEGISUB_STATIC_LIBS}
    "-Wl,--end-group"
    z m dl pthread)

target_link_options(aegisubtest PRIVATE
    -Wl,-Bsymbolic
    -Wl,--exclude-libs,ALL)
