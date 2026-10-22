#!/usr/bin/env bash
# 用 hap-sign-tool 给 unsigned HAP 签名。
# 用法：
#   sign-test-hap.sh <unsigned.hap> <app.p12> <app.cer> <profile.p7b> [keyAlias] [pwd] [out.hap]
# 华为调试证书请使用 AGC 签发的 .cer / .p7b（profile 的 bundle-name 必须等于
# com.example.aegisubtest，且包含设备 UDID）。
set -euo pipefail

WS=/root/opt/dsh/workspace-aegisub
source "$WS/scripts/env.sh" 2>/dev/null || true

if [ $# -lt 4 ]; then
    echo "usage: $0 <unsigned.hap> <app.p12> <app.cer> <profile.p7b> [keyAlias] [pwd] [out.hap]" >&2
    exit 2
fi

HAP="$1"
P12="$2"
CER="$3"
P7B="$4"
ALIAS="${5:-app-key}"
PWD="${6:-123456}"
OUT="${7:-${HAP%.hap}-signed.hap}"

TOOL="$HARMONYOS_CLT/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar"
[ -f "$TOOL" ] || TOOL=/opt/harmony26/command-line-tools/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar

echo "=== sign-app ==="
java -jar "$TOOL" sign-app -mode localSign \
    -keyAlias "$ALIAS" -keyPwd "$PWD" \
    -appCertFile "$CER" \
    -profileFile "$P7B" \
    -inFile "$HAP" \
    -signAlg "${AEGISUB_SIGN_ALG:-SHA256withECDSA}" \
    -keystoreFile "$P12" -keystorePwd "$PWD" \
    -outFile "$OUT" \
    -compatibleVersion "${AEGISUB_COMPATIBLE_VERSION:-26}" \
    -signCode "${AEGISUB_SIGN_CODE:-1}"

echo "=== verify-app ==="
java -jar "$TOOL" verify-app \
    -inFile "$OUT" \
    -outCertChain /tmp/aegisub-sign-chain.cer \
    -outProfile /tmp/aegisub-sign-profile.p7b | tail -5

ls -lh "$OUT"
