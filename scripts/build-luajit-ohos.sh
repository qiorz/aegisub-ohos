#!/usr/bin/env bash
# 手工交叉编译 LuaJIT 2.1 静态库（OHOS aarch64）。
# 不使用 Aegisub 的 luajit.wrap：wrapdb 的 Meson 构建对 host_machine.system()
# == 'ohos' 不识别，且需要在 configure 阶段运行目标二进制。
set -euo pipefail

WS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$WS/scripts/env.sh"

SRC="$WS/build/deps/src/luajit/src"
PREFIX="$WS/build/deps/prefix"

[ -d "$SRC" ] || { echo "缺少 $SRC，先运行 scripts/fetch-deps-ohos.sh"; exit 1; }
mkdir -p "$PREFIX/include/luajit-2.1" "$PREFIX/lib/pkgconfig"

cd "$SRC"
make clean >/dev/null 2>&1 || true
make -j"${JOBS:-1}" BUILDMODE=static \
    HOST_CC="gcc -m64" \
    CC="$OHOS_CC --target=aarch64-linux-ohos --sysroot=$OHOS_SYSROOT" \
    TARGET_SYS=Linux \
    TARGET_LJARCH=arm64 \
    TARGET_LD="$OHOS_CC --target=aarch64-linux-ohos --sysroot=$OHOS_SYSROOT" \
    TARGET_AR="$OHOS_AR rcus" \
    TARGET_STRIP="$OHOS_STRIP" \
    TARGET_FLAGS="-DLUAJIT_ENABLE_LUA52COMPAT" \
    TARGET_CFLAGS="-fPIC"

cp lua.h luaconf.h lualib.h lauxlib.h luajit.h "$PREFIX/include/luajit-2.1/"
cp libluajit.a "$PREFIX/lib/libluajit-5.1.a"

# LuaJIT 不提供 C++ 包装头；Aegisub 的 lua/ffi.h 会包含 <lua.hpp>。
cat > "$PREFIX/include/luajit-2.1/lua.hpp" <<'EOF'
#ifndef AEGISUB_OHOS_LUA_HPP
#define AEGISUB_OHOS_LUA_HPP
extern "C" {
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
}
#endif
EOF

cat > "$PREFIX/lib/pkgconfig/luajit.pc" <<EOF
prefix=$PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include/luajit-2.1

Name: luajit
Description: Just-in-time compiler for Lua
Version: 2.1.0
Libs: -L\${libdir} -lluajit-5.1
Libs.private: -lm -ldl
Cflags: -I\${includedir}
EOF

ls -lh "$PREFIX/lib/libluajit-5.1.a"
