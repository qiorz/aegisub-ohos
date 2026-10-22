#!/usr/bin/env bash
# qemu 回归：MP4 mdhd/stts FPS 探测（与 HAP 同一份 video_probe.cpp）。
set -euo pipefail

WS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$WS/scripts/env.sh"

# 测试素材目录：默认找 <repo>/testdata 或同级 HandBrake 工作区，找不到就要求显式指定
SAMPLE_DIR="${SAMPLE_DIR:-}"
if [ -z "$SAMPLE_DIR" ]; then
  for d in "$WS/testdata" "$WS/../workspace/hb-build/cli"; do
    [ -d "$d" ] && SAMPLE_DIR="$d" && break
  done
fi
[ -n "$SAMPLE_DIR" ] || { echo "set SAMPLE_DIR to a dir with sintel.mp4 / sample.mp4 / noaudio.mkv / sub-zh.mkv"; exit 1; }
OUT="$WS/build/video-probe-test"
DATA="$WS/build/video-probe-test-data"
mkdir -p "$DATA"

cat > "$WS/build/video-probe-main.cpp" <<'CPP'
#include "video_probe.h"
#include <cstdio>
int main(int argc, char** argv) {
    if (argc < 2) return 2;
    std::printf("%s\n", VideoProbeJson(argv[1]).c_str());
    return 0;
}
CPP

$OHOS_CXX --target=aarch64-linux-ohos --sysroot="$OHOS_SYSROOT" \
    -std=c++17 -O2 -static -I "$WS/app/entry/src/main/cpp" \
    "$WS/build/video-probe-main.cpp" \
    "$WS/app/entry/src/main/cpp/video_probe.cpp" \
    -o "$OUT"

check() {
    local src="$1" expected="$2"
    [ -f "$src" ] || { echo "missing sample $src"; exit 1; }
    qemu-aarch64-static "$OUT" "$src" > "$DATA/out.json"
    python3 - "$DATA/out.json" "$expected" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
want = float(sys.argv[2])
assert d['ok'] is True, d
assert abs(d['fps'] - want) < 0.05, (d['fps'], want)
print(f"PASS: {d['fps']:.3f} fps")
PY
}

echo "=== sintel.mp4 ==="
check "$SAMPLE_DIR"/sintel.mp4 24
echo "=== sample.mp4 ==="
check "$SAMPLE_DIR"/sample.mp4 30
echo "=== noaudio.mkv ==="
check "$SAMPLE_DIR"/noaudio.mkv 24
echo "=== sub-zh.mkv ==="
check "$SAMPLE_DIR"/sub-zh.mkv 30
