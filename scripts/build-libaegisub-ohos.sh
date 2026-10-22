#!/usr/bin/env bash
# 构建 Aegisub v3.5.1 核心库（libaegisub）+ gtest，用于 OHOS aarch64。
# 前置：build/deps/prefix 内已有 zlib / ICU / LuaJIT / GoogleTest / Boost 静态库。
set -euo pipefail

WS=/root/opt/dsh/workspace-aegisub
source "$WS/scripts/env.sh"

PREFIX="$WS/build/deps/prefix"
SRC="$WS/src/Aegisub"
BUILD="$WS/build/libaegisub"
LOG="$WS/build/logs/libaegisub.log"

mkdir -p "$WS/build/logs"
exec > >(tee -a "$LOG") 2>&1

export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
export BOOST_ROOT="$PREFIX"
export BOOST_INCLUDEDIR="$PREFIX/include"
export BOOST_LIBRARYDIR="$PREFIX/lib"

if [ "${1:-}" = "--wipe" ]; then
    rm -rf "$BUILD"
fi

if [ ! -d "$BUILD" ]; then
    echo "=== [$(date)] meson setup ==="
    meson setup "$BUILD" "$SRC" \
        --cross-file "$WS/scripts/cross-ohos-aarch64.ini" \
        --buildtype=release \
        --wrap-mode=nodownload \
        -Dcore_only=true \
        -Dtests=true \
        -Dsystem_luajit=true \
        -Denable_update_checker=false \
        -Dprefer_static=true \
        -Ddefault_library=static \
        -Dforce_fallback_for=iconv
fi

echo "=== [$(date)] compile gtest-main ==="
meson compile -C "$BUILD" -j "$JOBS" gtest-main

echo "=== [$(date)] artifacts ==="
find "$BUILD" -maxdepth 3 -name 'gtest-main' -o -name 'libaegisub.a' | xargs -r ls -lh
