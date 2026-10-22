#!/usr/bin/env bash
# 在 qemu 下运行 libaegisub 的 gtest 套件（全静态产物）。
# 注意：测试用相对路径 data/...，必须在 build/libaegisub/tests 下运行。
set -uo pipefail

WS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$WS/scripts/env.sh"

BUILD="$WS/build/libaegisub"
BIN="$BUILD/tests/gtest-main"

[ -x "$BIN" ] || { echo "缺少 $BIN，先运行 scripts/build-libaegisub-ohos.sh"; exit 1; }

cd "$BUILD/tests"
bash "$WS/src/Aegisub/tests/setup.sh"

export AEGISUB_TEST_DATA_DIR="$WS/src/Aegisub/tests"
"$QEMU_AARCH64" ./gtest-main "$@"
