#!/usr/bin/env bash
# 取依赖源码（Debian/Ubuntu 环境，使用 apt 源，比 GitHub 稳定）。
# 产物解包到 build/deps/src/：
#   boost/  icu/  zlib-1.2.13.dfsg/  googletest-release-1.12.1/  luajit/
set -euo pipefail

WS=/root/opt/dsh/workspace-aegisub
SRC="$WS/build/deps/src"
mkdir -p "$SRC"
cd "$SRC"

export DEBIAN_FRONTEND=noninteractive

fetch() {
    local dir="$1"; shift
    if [ -d "$dir" ]; then
        echo "已存在 $dir，跳过"
        return
    fi
    echo "=== apt-get source $* ==="
    apt-get source "$@"
}

fetch boost        -t bookworm-backports boost1.83
fetch icu          icu
fetch zlib-1.2.13.dfsg zlib
fetch googletest-release-1.12.1 googletest

if [ ! -d luajit ]; then
    echo "=== apt-get source luajit ==="
    apt-get source luajit
    # LuaJIT 的 orig tarball 顶层是 src/ dynasm/ etc/，统一收进 luajit/
    if [ -f src/Makefile ] && [ -d dynasm ]; then
        mkdir -p luajit
        mv src dynasm etc luajit/
    fi
fi

echo "=== 源码目录 ==="
ls -d boost icu zlib-* googletest-* luajit 2>/dev/null
