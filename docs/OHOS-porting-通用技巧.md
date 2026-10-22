# OHOS 移植通用技巧（本机已验证）

来源：HandBrake 移植过程中验证过的做法，摘出不依赖具体项目的部分。
项目细节见 `/root/opt/dsh/workspace/hb-port/移植进度-2026-10-21.md`。

## 1. 不依赖真机的验证：qemu-aarch64-static

- 用 `--target=aarch64-linux-ohos` 且 **`-static`** 链接，产物可直接被
  `qemu-aarch64-static ./prog` 执行。
- 动态链接的产物会因找不到 OHOS 的 `ld-musl-aarch64.so.1` 直接段错误。
- 用途：纯逻辑单测、CLI 冒烟、编码/解析回环验证。
- 局限：无法复现 SELinux 沙箱、线程亲和性、binder/ability 行为，真机问题仍需真机。

## 2. CMake 交叉编译入口

```cmake
-DCMAKE_TOOLCHAIN_FILE=$NDK/build/cmake/ohos.toolchain.cmake
-DOHOS_ARCH=arm64-v8a
-DCMAKE_BUILD_TYPE=Release
```
NDK 位于 `$DEVECO_SDK_HOME/default/openharmony/native`（默认
`/opt/harmony26/command-line-tools/sdk/default/openharmony/native`），自带 cmake/ninja。

## 3. DevEco/hvigor 工程要点（API 26）

- `compatibleSdkVersion` / `targetSdkVersion` 写字符串 `"26.0.0"`，不带 `(N)` 形式。
- Native 库通过 `build-profile.json5` 的 `externalNativeOptions` 的 `arguments` 传
  `-DXXX_PREFIX=...` 这类路径参数，避免硬编码绝对路径进 CMakeLists。
- 全量 `hvigorw assembleHap` 在 2 核机器上约 20–35 秒，峰值内存约 470 MB。

## 4. 真机

- `hdc list targets` 确认在线；装包 `hdc install -r xxx.hap`。
- 抓日志：`hdc hilog`，崩溃看 `hdc shell` 下的 faultlogger 目录。
- 签名：需要 AGC 签发的 `.cer` 与 debug `.p7b` 配合本机 `<signing-dir>/app.p12`。

## 5. 依赖复用注意

HandBrake 侧已有的 AArch64 静态库（libass、fribidi、freetype、harfbuzz、lame 等）位于
`/root/opt/dsh/workspace/hb-port/src/prebuilt/` 与 `hb-build/deps/`。
复用前必须核对：架构一致、**libc/ABI 一致（musl 静态）**、C++ ABI 与编译器版本一致，
否则会出现诡异链接错误。能用则省 1–2 天，不能用就自己编。
