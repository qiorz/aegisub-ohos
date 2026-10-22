# Aegisub → HarmonyOS (OHOS) 移植

把 [Aegisub](https://github.com/Aegisub/Aegisub)（字幕编辑/打轴工具）移植到 HarmonyOS / OpenHarmony，
产出可安装的 HAP。

## 目录

| 路径 | 用途 |
|---|---|
| `src/` | 上游源码 checkout（建议固定 tag，不入库） |
| `build/` | 出树构建目录（不入库） |
| `patches/` | 我方改动，按上游路径命名的 patch 或 overlay 文件 |
| `scripts/` | 构建、打包、真机部署脚本 |
| `out/` | HAP / 静态二进制等产物（不入库） |
| `docs/` | 方案、验证记录；环境类文档以软链引用共用版本 |

## 第一步该看什么

1. `docs/OHOS-porting-通用技巧.md` —— 已在本机验证过的通用做法（qemu 静态验证、API 26 配置、签名）。
2. `docs/HARMONYOS-环境说明.md` —— 机器与工具链现状（软链）。
3. `docs/签名与真机联调指南.md` —— 真机安装与抓日志（软链）。

## 当前状态

骨架已就绪，尚未拉取源码、尚未做依赖可行性评估。
最大的未知项是 **wxWidgets 在 OHOS 上的可编译性**（Aegisub 的 GUI 层强依赖 wx），
其次是 Boost（可裁剪）、luajit（Aegisub 自动化脚本）、以及自带的 libass/ffmpeg 能否复用 HandBrake 已编好的 AArch64 版本。
