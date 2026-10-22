#!/usr/bin/env bash
# qemu 回归：用与 HAP 相同的 ass_render.cpp 渲染一帧 libass 字幕，
# 断言至少产生一个非透明像素。
set -euo pipefail

WS=/root/opt/dsh/workspace-aegisub
source "$WS/scripts/env.sh"

PREFIX="$WS/build/deps/prefix"
OUT="$WS/build/ass-render-test"
DATA="$WS/build/ass-render-test-data"
mkdir -p "$DATA"

FONT=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf
[ -f "$FONT" ] || { echo "missing $FONT"; exit 1; }

cat > "$WS/build/ass-render-test-main.cpp" <<'EOF'
#include "ass_render.h"
#include <cstdio>
#include <cstdlib>
int main(int argc, char** argv) {
    if (argc < 4) return 2;
    RenderedFrame f = RenderAssFrame(argv[1], std::atoi(argv[2]), 640, 360,
                                     argv[3], argc > 4 ? argv[4] : "");
    if (!f.ok) {
        std::fprintf(stderr, "render failed: %s\n", f.error.c_str());
        return 1;
    }
    int alpha = 0;
    for (size_t i = 3; i < f.pixels.size(); i += 4)
        if (f.pixels[i]) ++alpha;
    std::printf("ok=%d width=%d height=%d alpha_pixels=%d\n",
                f.ok, f.width, f.height, alpha);
    return alpha > 0 ? 0 : 1;
}
EOF

echo "=== compile ass-render-test ==="
$OHOS_CXX --target=aarch64-linux-ohos --sysroot="$OHOS_SYSROOT" \
    -std=c++17 -O2 -static -fexceptions \
    -I "$WS/app/entry/src/main/cpp" -I "$PREFIX/include" \
    "$WS/build/ass-render-test-main.cpp" \
    "$WS/app/entry/src/main/cpp/ass_render.cpp" \
    -Wl,--start-group \
    "$PREFIX/lib/libass.a" "$PREFIX/lib/libfontconfig.a" \
    "$PREFIX/lib/libexpat.a" "$PREFIX/lib/libharfbuzz.a" \
    "$PREFIX/lib/libfribidi.a" "$PREFIX/lib/libfreetype.a" \
    "$PREFIX/lib/libz.a" \
    -Wl,--end-group -pthread -lm -o "$OUT"

cat > "$DATA/sample.ass" <<'EOF'
[Script Info]
ScriptType: v4.00+
PlayResX: 640
PlayResY: 360

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,DejaVu Sans,40,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,1,2,10,10,10,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:00.00,0:00:05.00,Default,,0,0,0,,libass render ok
EOF

echo "=== render at 2s (bundled-font fallback) ==="
qemu-aarch64-static "$OUT" "$DATA/sample.ass" 2000 "$FONT"

cat > "$DATA/fonts.conf" <<'FONTCONF'
<?xml version="1.0"?>
<fontconfig>
  <dir>/usr/share/fonts</dir>
  <cachedir>/tmp/fc-cache</cachedir>
</fontconfig>
FONTCONF
echo "=== render at 2s (fontconfig) ==="
qemu-aarch64-static "$OUT" "$DATA/sample.ass" 2000 "$FONT" "$DATA/fonts.conf"
