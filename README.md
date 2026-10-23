# Aegisub → HarmonyOS (OHOS) 移植

> [!IMPORTANT]
> **状态说明（置顶）**
>
> - **目前能用的功能很少**：只覆盖「台词编辑 / 打轴 / 样式 / 导出」这条主链路。
>   字幕特效（`\pos`、`\move`、`\t` 等）、卡拉OK 模板、自动化脚本（Lua）、
>   压缩音频波形、完整视频解码都还没有，离上游 Aegisub 差得很远；GUI 路线
>   （ArkUI 重写 vs wxWidgets 后端）也尚未定案。
> - **未做 UI 美化**：界面只做到“能操作”，没有视觉设计、没有动效，控件与布局都很朴素。
> - **更新随缘**：个人业余项目，更新节奏不固定，issue / PR 可能长期不处理，不承诺任何时间点。
> - **相关项目**：[HandBrake → HarmonyOS 移植](https://github.com/qiorz/handbrake-ohos)

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
| `docs/` | 方案、验证记录、环境与签名说明 |

## 第一步该看什么

1. `docs/OHOS-porting-通用技巧.md` —— 已在本机验证过的通用做法（qemu 静态验证、API 26 配置、签名）。
2. `docs/HARMONYOS-环境说明.md` —— 机器与工具链现状（软链）。
3. `docs/签名与真机联调指南.md` —— 真机安装与抓日志（软链）。

## 当前状态

- **核心库**：Aegisub v3.5.1 的 `libaegisub` 交叉编译通过；全静态 `gtest-main` 在
  qemu-aarch64 下 **371/371 通过**。详见 [进度-2026-10-22](docs/进度-2026-10-22.md)。
- **应用壳（ArkUI 编辑器，当前 v0.2.5）**：
  - 字幕：打开 / 新建 ASS、导入 SRT、导出 ASS / SRT，`.bak` 备份与页面隐藏自动保存；
  - 台词：起止时间（归一化、`\N` 换行）、Layer / Actor / 边距 / Effect、搜索过滤、
    复制 / 排序、撤销重做、文本标签工具栏；
  - 打轴：WAV/MP3/M4A/AAC/FLAC/OGG 波形、视频音轨波形、时间偏移、设为播放点、
    逐帧与 ±100 ms 微调，**自动读取 MP4 / MKV 帧率**；
  - 视频：预览叠加字幕；样式：新增 / 删除 / 改名、字体枚举、字号 / 颜色 / 粗斜体 / 对齐、
    libass 单帧与自动样式预览；
  - 其它：沙箱缓存统计与清理（v0.2.1）；
  - 产物 `Aegisub-unsigned-v0.2.9.hap`（仅交付未签名包，签名由使用者完成）。
- 局限：满帧率 libass、完整样式表、自动化（Lua）尚未实现；编辑器主流程已真机验证，
  新功能按各版本说明测试；GUI 路线（ArkUI 重写 vs wxWidgets 后端）已选 ArkUI。

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

## 构建前置

- HarmonyOS Command Line Tools 26.0.0（或 DevEco Studio 同版本 SDK），提供 `hvigorw` / `ohpm` / `hdc`；
- meson + ninja（构建 libaegisub）、CMake 3.28+（NDK 自带即可）；
- `qemu-aarch64-static`（可选，仅用于跑静态链接的单测）；
- 脚本会自动把 `WS` 推导为仓库根目录，不再依赖写死的绝对路径；需要换 SDK 位置时改
  `scripts/env.sh` 里的 `HARMONYOS_CLT`。

依赖与上游源码不入库，按上面的“复现入口”脚本自动拉取/编译。

## 本仓库不包含

- 上游源码 checkout（`src/`）、构建目录（`build/`）、构建产物（`out/`、`*.hap`）；
- 签名材料（`.p12` / `.cer` / `.p7b`）与设备日志。

可安装的 HAP 放在 **Releases**。本项目只交付**未签名**包，签名证书需使用者自行申请
（华为 AGC 签发，profile 需绑定你的设备 UDID）。

## 相关项目

- [HandBrake → HarmonyOS 移植](https://github.com/qiorz/handbrake-ohos) —— 视频转码引擎的 OHOS 移植，
  与本项目同源思路（OHOS NDK 交叉编译 + ArkTS 外壳）。

## 许可

- 上游 Aegisub 采用 **BSD-3-Clause**，全文见 [LICENSE](LICENSE)。本移植项目同样以 BSD-3-Clause 发布。
- 本项目是修改版：改动集中在 `patches/`、`app/entry/src/main/cpp/` 与 `app/entry/src/main/ets/`。
- 静态链接的第三方库（ICU、LuaJIT、Boost、libass、fontconfig、freetype、fribidi、
  harfbuzz、expat、zlib、GoogleTest）各自遵循其原始许可（多为 MIT / BSD / ISC / ICU 许可），
  分发二进制时需保留各自的版权声明。
- “Aegisub” 名称与图标归上游项目所有，本项目与上游无隶属关系。
