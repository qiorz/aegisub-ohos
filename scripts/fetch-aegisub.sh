#!/usr/bin/env bash
# 拉取 Aegisub v3.5.1 源码到 src/Aegisub。
# 上游已迁移到 TypesettingTools/Aegisub；旧 Aegisub/Aegisub 停在 3.2.2。
set -euo pipefail

WS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$WS/src/Aegisub"
TAG=v3.5.1
URL=https://github.com/TypesettingTools/Aegisub.git

mkdir -p "$WS/src"
if [ -d "$SRC/.git" ]; then
    echo "已存在 $SRC，当前版本：$(git -C "$SRC" describe --tags --always 2>/dev/null || echo unknown)"
    exit 0
fi

git clone --depth 1 --branch "$TAG" --no-recurse-submodules "$URL" "$SRC"
echo "已拉取 $(git -C "$SRC" describe --tags --always)"
