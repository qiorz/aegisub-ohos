#!/usr/bin/env bash
# Aegisub OHOS 工作区环境入口。
# 非交互 shell（bash -c）不会读 /root/.bashrc，必须显式 source 本文件：
#   source scripts/env.sh
#
# 只设置环境变量，不执行构建。

export HARMONYOS_CLT=/opt/harmony26/command-line-tools
if [ -f /etc/profile.d/harmonyos.sh ]; then
    . /etc/profile.d/harmonyos.sh
fi

export OHOS_NDK="$HARMONYOS_CLT/sdk/default/openharmony/native"
export OHOS_LLVM="$OHOS_NDK/llvm/bin"
export OHOS_SYSROOT="$OHOS_NDK/sysroot"
export OHOS_CMAKE_BIN="$OHOS_NDK/build-tools/cmake/bin"
export OHOS_TOOLCHAIN_FILE="$OHOS_NDK/build/cmake/ohos.toolchain.cmake"
export OHOS_TARGET=aarch64-linux-ohos
export OHOS_ARCH=arm64-v8a

# NDK 自带 cmake 3.28 / ninja，优先于系统命令
case ":$PATH:" in
    *":$OHOS_CMAKE_BIN:"*) ;;
    *) export PATH="$OHOS_CMAKE_BIN:$OHOS_LLVM:$PATH" ;;
esac

# 2 核 / 1.6 GiB，默认单 job，避免 OOM；需要时显式 JOBS=2 source
export JOBS="${JOBS:-1}"

# 常用短路径（供脚本引用，不改变 CC/CXX，避免影响宿主机构建）
export OHOS_CC="$OHOS_LLVM/aarch64-unknown-linux-ohos-clang"
export OHOS_CXX="$OHOS_LLVM/aarch64-unknown-linux-ohos-clang++"
export OHOS_AR="$OHOS_LLVM/llvm-ar"
export OHOS_STRIP="$OHOS_LLVM/llvm-strip"

# 复用 HandBrake 的 OHOS 预编译库（使用前先核对 ABI/版本）
# HandBrake 移植工作区（默认取同级的 workspace 目录，可用环境变量覆盖）
_HB_HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
export HB_WORKSPACE="${HB_WORKSPACE:-$_HB_HERE/../../workspace}"
export HB_PREBUILT="$HB_WORKSPACE/hb-port/src/prebuilt"
export HB_DEPS="$HB_WORKSPACE/hb-build/deps"

# qemu 验证：只支持 -static 产物
export QEMU_AARCH64=qemu-aarch64-static
