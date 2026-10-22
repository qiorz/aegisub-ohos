#!/usr/bin/env bash
# 构建 Aegisub 测试 HAP。
#   默认只出 unsigned 包。
#   设置 AEGISUB_SIGN_P12 / AEGISUB_SIGN_CER / AEGISUB_SIGN_PROFILE 后自动签名。
set -euo pipefail

WS=/root/opt/dsh/workspace-aegisub
source "$WS/scripts/env.sh"

bash "$WS/scripts/prepare-hap-testdata.sh"

cd "$WS/app"
echo "=== hvigorw assembleHap ==="
hvigorw --mode module -p product=default -p module=entry@default assembleHap --no-daemon

UNSIGNED="$WS/app/entry/build/default/outputs/default/entry-default-unsigned.hap"
[ -f "$UNSIGNED" ] || { echo "missing $UNSIGNED"; exit 1; }
cp -f "$UNSIGNED" "$WS/AegisubTest-unsigned.hap"
echo "unsigned: $WS/AegisubTest-unsigned.hap"

if [ -n "${AEGISUB_SIGN_P12:-}" ] && [ -n "${AEGISUB_SIGN_CER:-}" ] && [ -n "${AEGISUB_SIGN_PROFILE:-}" ]; then
    bash "$WS/scripts/sign-test-hap.sh" \
        "$WS/AegisubTest-unsigned.hap" \
        "$AEGISUB_SIGN_P12" "$AEGISUB_SIGN_CER" "$AEGISUB_SIGN_PROFILE" \
        "${AEGISUB_KEY_ALIAS:-app-key}" "${AEGISUB_KEY_PWD:-123456}" \
        "$WS/AegisubTest-signed.hap"
else
    echo "跳过签名（设置 AEGISUB_SIGN_P12 / AEGISUB_SIGN_CER / AEGISUB_SIGN_PROFILE 可自动签）"
fi
