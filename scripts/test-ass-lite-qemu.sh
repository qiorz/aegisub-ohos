#!/usr/bin/env bash
# 无真机回归：编译 ass_lite.cpp 的静态 AArch64 测试程序，在 qemu 下验证
# 解析、时间归一化、序列化回环（含 1000 行 / CRLF / BOM 压力用例）。
set -euo pipefail

WS=/root/opt/dsh/workspace-aegisub
source "$WS/scripts/env.sh"

SRC="$WS/src/Aegisub"
PREFIX="$WS/build/deps/prefix"
BUILD="$WS/build/libaegisub"
OUT="$WS/build/ass-lite-test"
DATA="$WS/build/ass-lite-test-data"
mkdir -p "$DATA"

cat > "$WS/build/ass-lite-test-main.cpp" <<'EOF'
#include "ass_lite.h"
#include <cstdio>
int main(int argc, char** argv) {
    if (argc < 2) return 2;
    std::string j = LoadAssJson(argv[1]);
    std::fwrite(j.data(), 1, j.size(), stdout);
    std::fputc('\n', stdout);
    std::printf("NORM:%s\n", NormalizeAssTime("1:02.5").c_str());
    std::printf("NORM_BAD:%s\n", NormalizeAssTime("abc").c_str());
    return 0;
}
EOF

echo "=== compile ass-lite-test ==="
$OHOS_CXX --target=aarch64-linux-ohos --sysroot="$OHOS_SYSROOT" \
    -std=c++20 -O2 -static -fexceptions \
    -I "$WS/app/entry/src/main/cpp" -I "$SRC/libaegisub/include" \
    "$WS/build/ass-lite-test-main.cpp" "$WS/app/entry/src/main/cpp/ass_lite.cpp" \
    -Wl,--start-group \
    "$BUILD/libaegisub/libaegisub.a" \
    "$BUILD/subprojects/luabins/libluabins.a" \
    "$BUILD/subprojects/iconv/libiconv.a" \
    "$PREFIX/lib/libboost_locale.a" "$PREFIX/lib/libboost_regex.a" \
    "$PREFIX/lib/libboost_thread.a" "$PREFIX/lib/libboost_chrono.a" \
    "$PREFIX/lib/libboost_filesystem.a" "$PREFIX/lib/libboost_system.a" \
    "$PREFIX/lib/libicui18n.a" "$PREFIX/lib/libicuuc.a" "$PREFIX/lib/libicudata.a" \
    "$PREFIX/lib/libluajit-5.1.a" "$PREFIX/lib/libz.a" \
    -Wl,--end-group -pthread -lm -ldl -o "$OUT"

python3 - "$DATA" <<'PY'
import sys, pathlib
d = pathlib.Path(sys.argv[1])
sample = '''[Script Info]
Title: Test
PlayResX: 1920
PlayResY: 1080
ScriptType: v4.00+

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Arial,48,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,2,2,10,10,10,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:01.23,0:00:03.45,Default,Alice,0,0,0,,Hello, world
Comment: 0,0:00:04.00,0:00:05.00,Default,,0,0,0,,note

[Fonts]
fontname: x
'''
(d / 'sample.ass').write_text(sample, encoding='utf-8')

lines = ['[Script Info]', 'Title: Stress', 'ScriptType: v4.00+',
         'PlayResX: 1920', 'PlayResY: 1080', '', '[V4+ Styles]',
         'Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding',
         'Style: Default,Arial,48,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,2,2,10,10,10,1',
         '', '[Events]',
         'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text']
for i in range(1000):
    m, s = divmod(i, 60)
    lines.append(f'Dialogue: 0,0:{m:02d}:{s:02d}.00,0:{m:02d}:{s:02d}.50,Default,A{i % 7},0,0,0,,Line {i}, with comma, and \\Nbreak')
lines += ['', '[Fonts]', 'fontname: stress.ttf']
(d / 'stress.ass').write_bytes(b'\xef\xbb\xbf' + ('\r\n'.join(lines) + '\r\n').encode())
PY

echo "=== sample roundtrip ==="
qemu-aarch64-static "$OUT" "$DATA/sample.ass" > "$DATA/sample1.json"
grep -q '^NORM:0:01:02.50$' "$DATA/sample1.json"
grep -q '^NORM_BAD:abc$' "$DATA/sample1.json"

python3 - "$DATA/sample1.json" "$DATA/sample_rt.ass" <<'PY'
import json, sys
raw = open(sys.argv[1], encoding='utf-8').read().splitlines()
d = json.loads(raw[0])
assert len(d['events']) == 2
assert d['events'][0]['startMs'] == 1230 and d['events'][0]['endMs'] == 3450
assert d['events'][0]['fields'][d['textIndex']] == 'Hello, world'
assert d['footer'].startswith('[Fonts]')
eol = d['eol']
out = d['header']
if out and not out.endswith(eol):
    out += eol
out += '[Events]' + eol + 'Format: ' + ', '.join(d['format']) + eol
for e in d['events']:
    out += e['kind'] + ': ' + ','.join(e['fields']) + eol
out += d['footer']
if d['bom']:
    out = '\ufeff' + out
open(sys.argv[2], 'w', encoding='utf-8', newline='').write(out)
PY

qemu-aarch64-static "$OUT" "$DATA/sample_rt.ass" > "$DATA/sample2.json"
python3 - "$DATA/sample1.json" "$DATA/sample2.json" <<'PY'
import json, sys
def doc(p):
    return json.loads(open(p, encoding='utf-8').read().splitlines()[0])
a, b = doc(sys.argv[1]), doc(sys.argv[2])
assert len(a['events']) == len(b['events']) == 2
assert all(x['fields'] == y['fields'] for x, y in zip(a['events'], b['events']))
assert a['footer'] == b['footer']
PY

echo "=== 1000-line CRLF/BOM roundtrip ==="
qemu-aarch64-static "$OUT" "$DATA/stress.ass" > "$DATA/stress1.json"
python3 - "$DATA/stress1.json" "$DATA/stress_rt.ass" <<'PY'
import json, sys
d = json.loads(open(sys.argv[1], encoding='utf-8').read().splitlines()[0])
assert d['bom'] is True and d['eol'] == '\r\n'
assert len(d['events']) == 1000
assert d['events'][-1]['endMs'] == 999500
out = d['header']
if out and not out.endswith(d['eol']):
    out += d['eol']
out += '[Events]' + d['eol'] + 'Format: ' + ', '.join(d['format']) + d['eol']
for e in d['events']:
    out += e['kind'] + ': ' + ','.join(e['fields']) + d['eol']
out += d['footer']
out = '\ufeff' + out
open(sys.argv[2], 'w', encoding='utf-8', newline='').write(out)
PY
qemu-aarch64-static "$OUT" "$DATA/stress_rt.ass" > "$DATA/stress2.json"
python3 - "$DATA/stress1.json" "$DATA/stress2.json" <<'PY'
import json, sys
def doc(p):
    return json.loads(open(p, encoding='utf-8').read().splitlines()[0])
a, b = doc(sys.argv[1]), doc(sys.argv[2])
assert len(a['events']) == len(b['events']) == 1000
assert all(x['fields'] == y['fields'] for x, y in zip(a['events'], b['events']))
assert all(x['startMs'] == y['startMs'] and x['endMs'] == y['endMs']
           for x, y in zip(a['events'], b['events']))
assert a['footer'] == b['footer']
print('PASS: 2-line + 1000-line ASS roundtrip, time normalization')
PY
