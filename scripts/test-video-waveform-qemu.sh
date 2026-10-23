#!/usr/bin/env bash
# qemu 回归：从视频/音频容器解码音轨并生成峰值（与 HAP 同一份 ffmpeg_waveform.cpp）。
set -euo pipefail

WS=/root/opt/dsh/workspace-aegisub
source "$WS/scripts/env.sh"
FF="$WS/build/deps/ffmpeg-min/install"
OUT="$WS/build/ffmpeg-wave-test"
DATA="$WS/build/ffmpeg-wave-test-data"
mkdir -p "$DATA"

cat > "$WS/build/ffmpeg-wave-main.cpp" <<'CPP'
#include "ffmpeg_waveform.h"
#include <cstdio>
#include <cstdlib>
int main(int argc, char** argv) {
    if (argc < 2) return 2;
    std::printf("%s\n", VideoWaveformJson(argv[1], argc > 2 ? std::atoi(argv[2]) : 200).c_str());
    return 0;
}
CPP

$OHOS_CXX --target=aarch64-linux-ohos --sysroot="$OHOS_SYSROOT" \
    -std=c++17 -O2 -static \
    -I "$WS/app/entry/src/main/cpp" -I "$FF/include" \
    "$WS/build/ffmpeg-wave-main.cpp" \
    "$WS/app/entry/src/main/cpp/ffmpeg_waveform.cpp" \
    -Wl,--start-group \
    "$FF/lib/libavformat.a" "$FF/lib/libavcodec.a" \
    "$FF/lib/libswresample.a" "$FF/lib/libavutil.a" \
    -Wl,--end-group -lpthread -lm -o "$OUT"

echo "=== Sintel MP4 audio ==="
qemu-aarch64-static "$OUT" /root/opt/dsh/workspace/hb-build/cli/sintel.mp4 100 > "$DATA/sintel.json"
python3 - "$DATA/sintel.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
assert d['ok'] is True, d
assert len(d['peaks']) == 100
assert max(d['peaks']) > 0.1, max(d['peaks'])
print('PASS: video audio waveform, max peak', max(d['peaks']))
PY

echo "=== MP3 audio ==="
qemu-aarch64-static "$OUT" /root/opt/dsh/workspace/hb-build/deps/lame-3.100/testcase.mp3 100 > "$DATA/mp3.json"
python3 - "$DATA/mp3.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
assert d['ok'] is True, d
assert len(d['peaks']) == 100
assert max(d['peaks']) > 0.1, max(d['peaks'])
print('PASS: MP3 audio waveform, max peak', max(d['peaks']))
PY

echo "=== noaudio MKV ==="
qemu-aarch64-static "$OUT" /root/opt/dsh/workspace/hb-build/cli/noaudio.mkv 100 > "$DATA/noaudio.json"
python3 - "$DATA/noaudio.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
assert d['ok'] is False and d.get('error') == 'no audio stream', d
print('PASS: no-audio container reports no audio stream')
PY
