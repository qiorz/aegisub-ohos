# Aegisub → HarmonyOS (OHOS) 移植

把 [Aegisub](https://github.com/TypesettingTools/Aegisub)（字幕编辑/打轴工具）移植到 HarmonyOS / OpenHarmony，
产出可安装的 HAP。上游已由 `Aegisub/Aegisub` 迁移到 `TypesettingTools/Aegisub`。

## 目录

| 路径 | 用途 |
|---|---|
| `src/` | 上游源码 checkout（建议固定 tag，不入库） |
| `build/` | 出树构建目录（不入库） |
| `patches/` | 我方改动，按上游路径命名的 patch 或 overlay 文件 |
| `scripts/` | 构建、打包、真机部署脚本 |
| `out/` | 其他构建产物（HAP 统一放工作区根目录，不入库） |
| `docs/` | 方案、验证记录；环境类文档以软链引用共用版本 |

## 第一步该看什么

1. `docs/OHOS-porting-通用技巧.md` —— 已在本机验证过的通用做法（qemu 静态验证、API 26 配置、签名）。
2. `docs/HARMONYOS-环境说明.md` —— 机器与工具链现状（软链）。
3. `docs/签名与真机联调指南.md` —— 真机安装与抓日志（软链）。

## 当前状态

- **2026-10-22**：v3.5.1 核心库 `libaegisub` 交叉编译通过；
  全静态 `gtest-main` 在 qemu-aarch64 下 **371/371 测试通过**。
  详见 [进度-2026-10-22](docs/进度-2026-10-22.md)。
- **ArkUI 编辑器 MVP**：主页面 `pages/Editor` 可打开/新建 ASS、导入 SRT、
  编辑台词与起止时间、Layer/Actor/边距/Effect、搜索过滤、保存 `.bak` 备份、
  音频播放/打轴（WAV 波形）、
  时间偏移/全局偏移/设为播放点/复制行/排序、
  样式新增/删除/改名/字体/字号/颜色/粗斜体/对齐、台词样式下拉、
  撤销/重做、视频预览叠加字幕、libass 单帧/自动样式预览、导出 ASS/SRT；
  测试页 `pages/Index` 保留（沙箱内 371 项 gtest + 日志导出）。
  产物 `Aegisub-unsigned.hap`（只交付未签名包，签名由使用者完成），
  用法与签名见 [HAP测试包-2026-10-22](docs/HAP测试包-2026-10-22.md)。
- 核心库仍是 **core-only**；应用壳已有 ArkUI 编辑与纯文本视频预览，
  fontconfig 已接入（扫描 `/system/fonts`，样式页可枚举/选择系统字体，
  缺失时回退内置 DejaVuSans）；
  压缩音频暂无波形；WAV 已有 PCM 峰值柱状图。
- 测试页真机 **371/371 通过**（2026-10-22，用户导出日志，164 ms）；
  编辑器页为本轮新增，尚未真机验证。
- 下一步最大未知项仍是 **GUI 路线**（ArkUI 重写 vs wxWidgets OHOS 后端）。

### 复现入口

```bash
source scripts/env.sh
bash scripts/fetch-aegisub.sh
bash scripts/fetch-deps-ohos.sh
bash scripts/build-all-deps.sh
bash scripts/apply-patches.sh
bash scripts/build-libaegisub-ohos.sh --wipe
bash scripts/run-tests-qemu.sh
```
