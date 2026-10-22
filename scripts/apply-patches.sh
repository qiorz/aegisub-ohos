#!/usr/bin/env bash
# 把 patches/ 下的 OHOS 改动应用到 v3.5.1 源码与 Boost 源码。
# 用法：在干净 checkout 上执行一次；重复执行会跳过已应用的补丁。
set -euo pipefail

WS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$WS/src/Aegisub"
BOOST="$WS/build/deps/src/boost"

[ -d "$S" ] || { echo "缺少 $S"; exit 1; }

for p in "$WS"/patches/0*.patch; do
    echo "=== $(basename "$p") ==="
    if git -C "$S" apply --check "$p" 2>/dev/null; then
        git -C "$S" apply "$p"
        echo "applied"
    else
        echo "skip (already applied or conflict)"
    fi
done

if [ -d "$BOOST" ]; then
    echo "=== boost-0001-ohos-pthread-cancelstate.patch ==="
    if ! grep -q '__OHOS__' "$BOOST/boost/core/detail/sp_thread_sleep.hpp"; then
        patch -p1 -d "$BOOST" < "$WS/patches/boost-0001-ohos-pthread-cancelstate.patch"
    else
        echo "skip (already applied)"
    fi
fi
