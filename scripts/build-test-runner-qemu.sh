#!/usr/bin/env bash
# Build the same test_runner.cpp as a fully static AArch64 executable and run
# it under qemu. This validates the HAP's in-app test harness without a device.
set -euo pipefail

WS=/root/opt/dsh/workspace-aegisub
source "$WS/scripts/env.sh"

SRC="$WS/src/Aegisub"
PREFIX="$WS/build/deps/prefix"
BUILD="$WS/build/libaegisub"
APPCPP="$WS/app/entry/src/main/cpp"
OUT="$WS/build/test-runner-static"

TEST_SOURCES=$(find "$SRC/tests/tests" -name '*.cpp' ! -name 'language_match.cpp' | sort)
[ -n "$TEST_SOURCES" ] || { echo "no test sources"; exit 1; }

echo "=== compile static test-runner ==="
# shellcheck disable=SC2086
$OHOS_CXX --target=aarch64-linux-ohos --sysroot="$OHOS_SYSROOT" \
    -std=c++20 -O2 -fPIC -fexceptions -DNDEBUG \
    -D_FILE_OFFSET_BITS=64 -D_LARGEFILE_SOURCE \
    -I"$APPCPP" \
    -I"$SRC/libaegisub/include" \
    -I"$SRC/tests/support" \
    -I"$SRC/subprojects/iconv/include" \
    -I"$PREFIX/include" \
    -I"$PREFIX/include/luajit-2.1" \
    "$APPCPP/test_runner.cpp" \
    "$APPCPP/runner_main.cpp" \
    "$SRC/tests/support/util.cpp" \
    $TEST_SOURCES \
    -Wl,--start-group \
    "$BUILD/libaegisub/libaegisub.a" \
    "$BUILD/subprojects/luabins/libluabins.a" \
    "$BUILD/subprojects/iconv/libiconv.a" \
    "$PREFIX/lib/libgtest.a" \
    "$PREFIX/lib/libgmock.a" \
    "$PREFIX/lib/libboost_locale.a" \
    "$PREFIX/lib/libboost_regex.a" \
    "$PREFIX/lib/libboost_thread.a" \
    "$PREFIX/lib/libboost_chrono.a" \
    "$PREFIX/lib/libboost_filesystem.a" \
    "$PREFIX/lib/libboost_system.a" \
    "$PREFIX/lib/libicui18n.a" \
    "$PREFIX/lib/libicuuc.a" \
    "$PREFIX/lib/libicudata.a" \
    "$PREFIX/lib/libluajit-5.1.a" \
    "$PREFIX/lib/libz.a" \
    -Wl,--end-group \
    -static -pthread -lm -ldl \
    -o "$OUT"

echo "=== run under qemu ==="
rm -rf /tmp/aegisub-app-cache
qemu-aarch64-static "$OUT" /tmp/aegisub-app-cache "$SRC/tests" > /tmp/aegisub-runner.json
python3 - <<'EOF'
import json
with open('/tmp/aegisub-runner.json') as f:
    r = json.load(f)
print({k: r.get(k) for k in ('ok','total','passed','failed','rc','durationMs','logPath')})
log = r.get('log','')
print('log bytes:', len(log))
print('\n'.join(log.splitlines()[-6:]))
EOF
