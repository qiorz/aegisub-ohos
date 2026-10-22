#!/usr/bin/env bash
# 按依赖顺序构建 OHOS 静态依赖。耗时主要在 ICU（host + cross）。
set -euo pipefail

WS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$WS"

bash scripts/build-zlib-ohos.sh
bash scripts/build-icu-ohos.sh
bash scripts/build-luajit-ohos.sh
bash scripts/build-gtest-ohos.sh
bash scripts/build-boost-ohos.sh

echo "=== 全部依赖完成 ==="
ls -lh build/deps/prefix/lib/*.a
