#!/usr/bin/env bash
# 构建 ICU 72.1 静态库（OHOS aarch64）。
# 交叉编译 ICU 需要一个同版本的宿主机构建树提供 genrb/genccode 等工具。
set -euo pipefail

WS=/root/opt/dsh/workspace-aegisub
source "$WS/scripts/env.sh"

SRC="$WS/build/deps/src/icu/source"
HOST="$WS/build/deps/icu-host"
CROSS="$WS/build/deps/icu-ohos"
PREFIX="$WS/build/deps/prefix"
LOG="$WS/build/logs/icu.log"

mkdir -p "$WS/build/logs" "$HOST" "$CROSS"
exec > >(tee -a "$LOG") 2>&1

echo "=== [$(date)] ICU host build ==="
if [ ! -f "$HOST/bin/genrb" ]; then
    cd "$HOST"
    "$SRC/configure" \
        --disable-extras --disable-tests --disable-samples --disable-layoutex \
        --prefix="$HOST"
    make -j1
    # 交叉编译只需要宿主构建树里的 genrb/genccode 和 icudefs.mk，
    # 不需要 make install（out-of-tree 下 install 会因同一文件而报错）。
else
    echo "host tools already present: $HOST/bin/genrb"
fi

echo "=== [$(date)] ICU cross build (OHOS arm64, static) ==="
cd "$CROSS"
CC="$OHOS_CC --target=aarch64-linux-ohos --sysroot=$OHOS_SYSROOT" \
CXX="$OHOS_CXX --target=aarch64-linux-ohos --sysroot=$OHOS_SYSROOT" \
AR="$OHOS_AR" \
RANLIB="$OHOS_LLVM/llvm-ranlib" \
CFLAGS="-O2 -fPIC" \
CXXFLAGS="-O2 -fPIC -std=c++17" \
"$SRC/configure" \
    --build=x86_64-linux-gnu \
    --host=aarch64-linux-gnu \
    --with-cross-build="$HOST" \
    --prefix="$PREFIX" \
    --enable-static --disable-shared \
    --disable-extras --disable-tests --disable-samples --disable-layoutex

make -j1
make install

echo "=== [$(date)] ICU done ==="
ls -lh "$PREFIX/lib"/libicu*.a
