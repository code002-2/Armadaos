# thyme 内核源码（小米 10S）

Armada 的 thyme 变体**不使用** armada-packages 的 kernel.org 构建。内核直接
从承载小米 10S（代号 `thyme`，SM8250）板级支持的社区 mainline 代码树构建：

- 仓库：<https://github.com/yuweiyuan8/linux-xiaomi-thyme-mainline>
- 分支：`master`（7.2.0-rc5 base，见 `BUILD.env`）

板级 DTS（`sm8250-xiaomi-thyme.dts`）、CSOT MP42020B DSC 面板驱动、
ST FTS 触摸控制器（内核态输入设备，无需 sheng 那样的用户态守护进程）、
WCD938x + CS35L41 音频、SMB2 电池/充电、SDX55 外置基带、
S5KHMX/S5K3T2/OV13B10 相机驱动都在该代码树内。

## 目录结构

| 文件 | 用途 |
|---|---|
| `BUILD.env` | 内核仓库 / 分支 / 配置 / 叠加片段（唯一事实来源）；`KERNEL_SRC` 可指向本地代码树 |
| `kernel-build.config` | build.yml 使用的 thyme 基座配置 —— 取自内核树 `thyme-camera/config/kernel-build.config`（实机验证过显示/启动路径的完整配置，LOCALVERSION `-sm8250-modem`） |
| `sm8250.config` | 内核树板级 fragment 副本（参考；不是构建输入） |
| `thyme-armada.config.overrides` | 叠加的 Armada 运行时片段（FEX/scx/ntsync/selinux/zram/nftables/QCA6390/USB gadget） |
| `build.sh` | 取源 → 合并配置 → `make Image dtbs modules` → 打包为 `build_files/20-install-kernel.sh` 消费的精确 tarball 布局 |

## 与 sheng 内核构建的差异

- `KERNEL_OVERRIDES` 是**空格分隔的片段列表**：第一个是 Armada 运行时片段，
  `thyme-modem.config` 则回落到内核树自带的 SDX55 基带片段。
- `KERNEL_SRC` 环境变量可指定本地代码树（移植工作站的树带有未提交修复），
  跳过 clone。
- 打包的 DTB glob 是 `sm8250-xiaomi-thyme*.dts`（含 `-logdump` 调试变体）。

## 内核如何接入 Armada

与 sheng 相同：现有 `Containerfile` 内核阶段保持不变（`KERNEL_PKG` 参数），
thyme 内核镜像形状完全一致，流水线仅覆盖 `KERNEL_PKG` 并在设备配置里设置
`ARMADA_DTB_LIST` / `ARMADA_BOOTIMG_ARGS_FILE` / `ARMADA_DEVICE`。

## 本地构建

```console
$ kernel-thyme/build.sh            # 原生 aarch64，或经 gcc-aarch64-linux-gnu 交叉编译
$ KERNEL_SRC=/home/ubuntu/os/linux-thyme-7.2 kernel-thyme/build.sh   # 本地树
$ ls kernel-thyme/out/             # armada-kernel-<KVER>.tar.zst(+sha256, Image.gz-dtb_thyme)
```

作为叠加镜像消费并构建本地 thyme Armada 镜像：

```console
$ podman build --platform linux/arm64 -f kernel-thyme/Containerfile -t localhost/armada-thyme-kernel:7.2.0-rc5 .
$ just build-thyme-flashable localhost/armada-thyme-kernel:7.2.0-rc5
```

## 更新到更新的 thyme 分支

修改 `BUILD.env` 中的 `KERNEL_BRANCH`，并从对应代码树刷新 `sm8250.config`。
`build.sh` 中的合并过滤器保证 thyme 配置删除某个符号时不会破坏 armada 片段。

## initramfs

`sm8250.config` 通过相对路径 `armada-thyme-initramfs.cpio.gz` 把 initramfs
烘进内核镜像(thyme 的 ABL 启动流程依赖它)。该文件在 `initramfs/`
下入库(真机验证过的版本,源自 sm8250-xiaomi-lmi 移植工作副本),
`build.sh` 会在构建前把它放进内核树根目录,因此 CI 与本地构建产物一致。
