#!/usr/bin/env bash
# 构建 Aegisub 测试 HAP。
#   默认只出 unsigned 包。
#   设置 AEGISUB_SIGN_P12 / AEGISUB_SIGN_CER / AEGISUB_SIGN_PROFILE 后自动签名。
set -euo pipefail

WS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$WS/scripts/env.sh"

bash "$WS/scripts/prepare-hap-testdata.sh"

cd "$WS/app"
echo "=== hvigorw assembleHap ==="
hvigorw --mode module -p product=default -p module=entry@default assembleHap --no-daemon

VERSION=$(sed -n 's/.*"versionName"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    "$WS/app/AppScope/app.json5" | head -1)
[ -n "$VERSION" ] || VERSION=0.0.0
UNSIGNED="$WS/app/entry/build/default/outputs/default/entry-default-unsigned.hap"
[ -f "$UNSIGNED" ] || { echo "missing $UNSIGNED"; exit 1; }
OUT="$WS/Aegisub-unsigned-v${VERSION}.hap"
cp -f "$UNSIGNED" "$OUT"
rm -f "$WS/Aegisub-unsigned.hap"
for old in "$WS"/Aegisub-unsigned-v*.hap; do
    [ "$old" = "$OUT" ] || rm -f "$old"
done
echo "unsigned: $OUT"

echo "only unsigned HAP: $OUT"
echo "需要签名时请自行执行 scripts/sign-test-hap.sh（本工作区不再产出 signed HAP）"
