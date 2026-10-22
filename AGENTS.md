# AGENTS.md — Aegisub OHOS 移植工作区

本文件面向在本工作区工作的 agent。请先读完再动手。

## 目标

把 Aegisub 移植到 HarmonyOS（API 26 / arm64），产出可安装的 HAP，并尽量保持上游功能。

## 硬环境约束（务必先读）

- 主机：Debian 12，**2 核 / 1.6 GiB 内存 + 6 GiB swap**，磁盘剩余约 13G。
  → 编译必须 `-j2`（或 `-j1`），不要开并行 job server 以外的重活；OOM 很常见。
- 工具链：HarmonyOS Command Line Tools 26.0.0，`/opt/harmony26/command-line-tools`，
  `hvigorw` / `ohpm` / `hdc` 已在 PATH。详见 `docs/HARMONYOS-环境说明.md`。
- API 26 的 `compatibleSdkVersion` 写 `"26.0.0"`（不带括号形式）。
- 无 `/dev/kvm`，模拟器不可用，验证走真机 hdc 或 qemu（见下）。

## 通用验证技巧（已在 HandBrake 上验证有效）

1. **qemu 验证通道**：`--target=aarch64-linux-ohos -static` 的产物可直接用
   `qemu-aarch64-static` 执行；**动态链接会因缺 `ld-musl-aarch64.so.1` 段错误**。
   适合跑纯逻辑单测（ass 解析、时间轴运算），不需要真机。
2. **真机**：优先「反向 SSH 隧道 + hdc」，可直接装包抓 hilog。见 `docs/签名与真机联调指南.md`。
3. **签名**：`/opt/harmony-signing/app.p12` 与 CSR 已就绪，需 AGC 换回 `.cer` / `.p7b`。

## 工作约定

- 出树构建：源码在 `src/`，构建目录一律放 `build/<component>/`，不要污染源码树。
- 我方改动优先做成 `patches/` 下的 patch 或 `overlay/` 文件，便于上游升级时重放；
  确实必须直接改源码的，在 `docs/decisions.md` 记录原因与文件名。
- `src/`、`build/`、`out/` 不入库（见 `.gitignore`）。
- 每次跑通一个阶段（依赖编过 / 引擎单测过 / 真机启动过），在 `docs/进度-YYYY-MM-DD.md` 追加一节，
  写清命令、产物路径、失败现象。不要只写结论。
- 报告结论时必须标明验证层级：**编译通过 / qemu 跑通 / 真机跑通**，三者不可混为一谈。

## 与 HandBrake 工作区的关系

`/root/opt/dsh/workspace` 是 HandBrake 移植，两者独立。但以下可复用：

- `docs/HARMONYOS-环境说明.md`、`docs/签名与真机联调指南.md`（软链到那边，改一处即生效）
- HandBrake 已构建的 AArch64 依赖（libass / fribidi / freetype / harfbuzz / ffmpeg 各库）：
  `/root/opt/dsh/workspace/hb-build/deps/` 与 `hb-port/src/prebuilt/`。**引用前先确认 ABI 与版本**。
- HandBrake 的 OHOS 构建参数范例：`hb-port/src/tools/build-linux.sh`、`hb-port/port-ohos/CMakeLists.txt`。

不要修改 HandBrake 工作区的文件；需要改共用文档时先说明。

## 未知项（动手前先评估）

- wxWidgets 3.x 在 OHOS 上的编译/运行（最大风险，GUI 全靠它）
- Boost 组件裁剪范围
- LuaJIT 的 AArch64/OHOS 支持（Aegisub 自动化）
- 字体枚举与渲染路径（OHOS 与 fontconfig 的差异）
