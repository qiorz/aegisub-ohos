#!/usr/bin/env bash
# qemu 回归：WAV PCM 峰值解析（与 HAP 同一份 waveform.cpp）。
set -euo pipefail

WS=/root/opt/dsh/workspace-aegisub
source "$WS/scripts/env.sh"
OUT="$WS/build/waveform-test"
DATA="$WS/build/waveform-test-data"
mkdir -p "$DATA"

cat > "$WS/build/waveform-test-main.cpp" <<'CPP'
#include "waveform.h"
#include <cstdio>
#include <cstdlib>
int main(int argc, char** argv) {
    if (argc < 2) return 2;
    std::printf("%s\n", WaveformJson(argv[1], argc > 2 ? std::atoi(argv[2]) : 200).c_str());
    return 0;
}
CPP

$OHOS_CXX --target=aarch64-linux-ohos --sysroot="$OHOS_SYSROOT" \
    -std=c++17 -O2 -static \
    -I "$WS/app/entry/src/main/cpp" \
    "$WS/build/waveform-test-main.cpp" \
    "$WS/app/entry/src/main/cpp/waveform.cpp" \
    -o "$OUT"

python3 - "$DATA" <<'PY'
import math, struct, sys, wave
from pathlib import Path
d = Path(sys.argv[1])
with wave.open(str(d / 'tone.wav'), 'wb') as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(8000)
    frames = bytearray()
    for i in range(8000):
        v = int(0.5 * 32767 * math.sin(2 * math.pi * 440 * i / 8000))
        frames += struct.pack('<h', v)
    w.writeframes(frames)
with wave.open(str(d / 'silence.wav'), 'wb') as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(8000)
    w.writeframes(b'\x00\x00' * 8000)
PY

echo "=== tone ==="
qemu-aarch64-static "$OUT" "$DATA/tone.wav" 100 > "$DATA/tone.json"
python3 - "$DATA/tone.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
assert d['ok'] is True, d
assert len(d['peaks']) == 100
assert 0.4 < max(d['peaks']) < 0.6, max(d['peaks'])
assert d['sampleRate'] == 8000 and d['channels'] == 1
print('PASS: 440Hz WAV waveform, max peak', max(d['peaks']))
PY

echo "=== silence ==="
qemu-aarch64-static "$OUT" "$DATA/silence.wav" 100 > "$DATA/silence.json"
python3 - "$DATA/silence.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
assert d['ok'] is True, d
assert max(d['peaks']) < 0.01, max(d['peaks'])
print('PASS: silence WAV near zero')
PY
