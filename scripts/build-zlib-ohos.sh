#!/usr/bin/env bash
# 构建 zlib 静态库（OHOS aarch64）。
# 源码：build/deps/src/zlib-1.2.13.dfsg（apt-get source zlib 解包）
set -euo pipefail

WS=/root/opt/dsh/workspace-aegisub
source "$WS/scripts/env.sh"

SRC="$WS/build/deps/src/zlib-1.2.13.dfsg"
PREFIX="$WS/build/deps/prefix"

[ -d "$SRC" ] || { echo "缺少 $SRC，先运行 scripts/fetch-deps-ohos.sh"; exit 1; }
mkdir -p "$PREFIX"

cd "$SRC"
make distclean >/dev/null 2>&1 || true
CC="$OHOS_CC --target=aarch64-linux-ohos --sysroot=$OHOS_SYSROOT" \
CFLAGS="-O2 -fPIC" \
./configure --static --prefix="$PREFIX"
make -j"${JOBS:-1}"
make install

ls -lh "$PREFIX/lib/libz.a"
