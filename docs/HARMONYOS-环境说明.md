# 本机 HarmonyOS 编译环境说明（26.0.0 / API 26）

## 一、机器情况

| 项目 | 值 |
|---|---|
| 系统 | Debian GNU/Linux 12 (bookworm) x86_64 |
| 公网 IP | 47.103.26.243（阿里云） |
| CPU | 2 核 Intel Xeon Platinum |
| 内存 | 1.6 GiB + 6 GiB swap |
| 磁盘 | 40 GiB，已用约 23 GiB，**可用约 16 GiB** |
| 虚拟化 | 无 `/dev/kvm`，模拟器不可用（不需要，走真机） |

## 二、工具链（已升级到 26.0.0）

**HarmonyOS Command Line Tools 26.0.0.821 (linux-x64)**，位于 `/opt/harmony26/command-line-tools`。

| 组件 | 版本 |
|---|---|
| HarmonyOS SDK | **26.0.0 Release / API 26**（Ohos_sdk_public 26.0.0.105） |
| hvigor | 6.26.4 |
| ohpm | 26.0.0.630 |
| hstack | 6.1.0 |
| codelinter | 6.0.240 |
| hdc | 3.2.0f |
| node | 24.14.1（自带） |
| JDK | OpenJDK 17 |

环境变量：`/etc/profile.d/harmonyos.sh`（已挂到 `/root/.bashrc`），`hvigorw` / `ohpm` / `hdc` 均在 PATH。

> 旧版 5.1.0（API 18，6.5 GB）已删除以释放空间。

## 三、构建

```bash
hvigorw --mode module -p product=default -p module=entry@default assembleHap --no-daemon
```

产物：`entry/build/default/outputs/default/entry-default-unsigned.hap`（未配置签名时）

### API 26 的配置要点

- `compatibleSdkVersion` 写成 **`"26.0.0"`**（API 10–25 才是 `"5.1.0(18)"` 这种带括号的老格式，26 开始不带）。
- 示例工程 `hello-harmony` 已改成 `26.0.0`，实测 `minAPIVersion` / `targetAPIVersion` 均为 `260000026`，`compileSdkVersion` 为 `26.0.0.105`。
- 全量构建约 18–19 秒，峰值内存约 470 MB。

## 四、本次清理记录

| 项目 | 释放 |
|---|---|
| 旧 HarmonyOS SDK 5.1.0 | 6.5 GB |
| apt 缓存 + 索引 | ~490 MB |
| systemd journal（压到 30 MB） | ~70 MB |
| npm/pnpm 缓存 | ~260 MB |
| 1Panel 安装包遗留文件 | ~230 MB |

**还没动、但可释放的**：Docker 镜像约 **7.6 GB**（`astrbot` 在运行；`cloudreve`、`postgres`、`redis`、`napcat`、`subtitle-translator` 五个容器已停止 2 个月）。
已删除这五个停止服务的容器与镜像，释放约 **5 GB**（astrbot 未受影响，仍在运行）。

## 五、签名与真机

见 [签名与真机联调指南.md](签名与真机联调指南.md)。要点：

- 服务器已生成密钥库 `<signing-dir>/app.p12` 和 CSR `<signing-dir>/app.csr`。
- 你把 CSR 上传 AGC 换 `.cer`，再在 AGC 建 debug Profile 拿 `.p7b`，两个文件给我即可出签名包。
- 真机连接优先走「反向 SSH 隧道」，我可以直接 `hdc` 装包、抓日志。
