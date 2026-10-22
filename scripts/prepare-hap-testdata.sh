#!/usr/bin/env bash
# 把 Aegisub 测试 fixture 打进 HAP 的 rawfile，并生成文件清单。
# fixtures 很小（keyframe ~2.1M、vfr ~404K、charset/options/lua 各几十 K）。
set -euo pipefail

WS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$WS/src/Aegisub"
DEST="$WS/app/entry/src/main/resources/rawfile/testdata"

rm -rf "$DEST"
mkdir -p "$DEST/tests" "$DEST/automation"

for d in keyframe vfr charset options lua; do
    cp -a "$SRC/tests/$d" "$DEST/tests/"
done
cp -a "$SRC/automation/include" "$DEST/automation/"

python3 - "$DEST" <<'PY'
import json, os, sys
root = sys.argv[1]
files = []
for dirpath, _, names in os.walk(root):
    for name in names:
        rel = os.path.relpath(os.path.join(dirpath, name), root)
        if rel == 'manifest.json':
            continue
        files.append(rel.replace(os.sep, '/'))
files.sort()
with open(os.path.join(root, 'manifest.json'), 'w', encoding='utf-8') as f:
    json.dump(files, f, ensure_ascii=False, indent=1)
print('fixture files:', len(files))
PY

# Preview fonts: DejaVuSans is the fallback; DroidSansFallback covers CJK.
FONT_SRC=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf
CJK_SRC=/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf
FONT_DEST="$WS/app/entry/src/main/resources/rawfile/fonts"
mkdir -p "$FONT_DEST"
if [ -f "$FONT_SRC" ]; then
    cp -f "$FONT_SRC" "$FONT_DEST/DejaVuSans.ttf"
    echo "font: $FONT_DEST/DejaVuSans.ttf"
else
    echo "WARN: $FONT_SRC not found; styled preview will be unavailable"
fi
if [ -f "$CJK_SRC" ]; then
    cp -f "$CJK_SRC" "$FONT_DEST/DroidSansFallbackFull.ttf"
    echo "font: $FONT_DEST/DroidSansFallbackFull.ttf"
else
    echo "WARN: $CJK_SRC not found; Chinese glyphs may show as boxes"
fi

du -sh "$DEST"
