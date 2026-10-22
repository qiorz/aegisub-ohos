#!/usr/bin/env bash
# 构建 Boost 1.83 静态库（OHOS aarch64），供 libaegisub 使用。
# 前置：build/deps/src/boost（Boost 1.83 源码）、build/deps/prefix（ICU/zlib 已装）
set -euo pipefail

WS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$WS/scripts/env.sh"

BOOST="$WS/build/deps/src/boost"
PREFIX="$WS/build/deps/prefix"
TOOL="$WS/build/deps/toolchain"
LOG="$WS/build/logs/boost.log"

mkdir -p "$WS/build/logs" "$TOOL"
exec > >(tee -a "$LOG") 2>&1

# b2 会追加 --target=arm64-pc-linux；把 OHOS target 放到参数最后，后者生效。
cat > "$TOOL/ohos-clang" <<EOF
#!/bin/sh
exec $OHOS_CC --sysroot=$OHOS_SYSROOT "\$@" --target=aarch64-linux-ohos
EOF
cat > "$TOOL/ohos-clang++" <<EOF
#!/bin/sh
exec $OHOS_CXX --sysroot=$OHOS_SYSROOT "\$@" --target=aarch64-linux-ohos
EOF
chmod +x "$TOOL/ohos-clang" "$TOOL/ohos-clang++"
cat > "$TOOL/user-config.jam" <<EOF
using clang : ohos : $TOOL/ohos-clang++ : $TOOL/ohos-clang ;
EOF

# OHOS musl 没有 pthread_setcancelstate；打补丁跳过。
if ! grep -q '__OHOS__' "$BOOST/boost/core/detail/sp_thread_sleep.hpp"; then
    patch -p1 -d "$BOOST" < "$WS/patches/boost-0001-ohos-pthread-cancelstate.patch"
fi

COMMON=(
    -j1
    --user-config="$TOOL/user-config.jam"
    toolset=clang-ohos
    link=static
    runtime-link=static
    threading=multi
    target-os=linux
    address-model=64
    --prefix="$PREFIX"
    --build-dir="$WS/build/deps/boost-build"
)

cd "$BOOST"

echo "=== [$(date)] Boost core libs ==="
b2 "${COMMON[@]}" \
    --with-chrono --with-thread --with-filesystem --with-system --with-regex \
    install

echo "=== [$(date)] Boost.Locale (ICU static) ==="
b2 "${COMMON[@]}" \
    --with-locale \
    -sICU_PATH="$PREFIX" \
    -sICU_ICUUC_NAME=icuuc \
    -sICU_ICUDT_NAME=icudata \
    -sICU_ICUIN_NAME=icui18n \
    boost.locale.icu=on \
    boost.locale.posix=off \
    boost.locale.winapi=off \
    cxxflags="-DBOOST_LOCALE_NO_POSIX_BACKEND -DBOOST_LOCALE_NO_WINAPI_BACKEND" \
    install

echo "=== [$(date)] Boost done ==="
ls -lh "$PREFIX/lib"/libboost_*.a
