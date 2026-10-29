<p align="center">
  <a href="https://armadaos.dev/">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset=".github/assets/armada-mark-white.svg">
      <img src=".github/assets/armada-mark-black.svg" alt="Armada" width="112">
    </picture>
  </a>
</p>

</p>

<p align="center">
  <a href="https://github.com/armada-os/armada/actions/workflows/build.yml"><img alt="Build status" src="https://github.com/armada-os/armada/actions/workflows/build.yml/badge.svg?branch=main"></a>
  <a href="https://armadaos.dev/"><img alt="Documentation" src="https://img.shields.io/badge/docs-armadaos.dev-18181a?style=flat"></a>
  <a href="LICENSE.md"><img alt="GPL-2.0-or-later license" src="https://img.shields.io/badge/license-GPL--2.0--or--later-18181a?style=flat"></a>
</p>

> [!WARNING]
> 本项目为开发中的原型软件。安装需要**已解锁的 bootloader**,并会刷写 Android 分区——
> 可能导致设备变砖、分区损坏或数据丢失。**请先备份数据。**操作前请阅读
> [刷写至小米平板 6S Pro](docs/flashing-xiaomi-sheng.md) /
> [刷写至小米 10S](docs/flashing-xiaomi-thyme.md)。

## 关于本构建


 **无 bootc / OSTree / OTA。** 移除了上游基于镜像的系统更新链路。根文件系统是
   **普通 ext4 分区**,通过 `fastboot` 刷写——升级方式为**重新刷写**,而非原地更新。


**thyme(小米 10S)** — 首版移植,组件状态:

| 组件 | 状态 |
|---|---|
| 启动(原厂 ABL、`boot_a/b.img`、**header-v1**/pagesize 2048、kernel/tags `0x10000000`) | 🔶 几何来自本机已验证的测试镜像,待整机验证 |
| 触摸屏(ST FTS,内核态输入设备,固件在 IC flash) | ✅ 本机 Ubuntu chroot 已验证 |
| 音频(WCD938x + 2× CS35L41,声卡 `XIAOMI-UMI-WCD9380-CS35L41-VA-DMIC`) | ✅ UCM2 取自本机已验证配置 |
| WiFi/BT(QCA6390:PCIe ath11k + uart6 hci_qca,固件已内置) | 🔶 待整机验证 |
| USB gadget RNDIS 网络(sshd)/ steam-now / SELinux permissive | ✅ 与 sheng 同链路 |
| 蜂窝(SDX55/MHI,内核已开)/ 相机(驱动在树)/ 指纹 | ❌ 用户态未集成 |

已知限制:Steam 客户端更新与游戏下载需要可用的代理/网络访问 Valve CDN
(开发中使用的代理配置见 [故障排查](docs/flashing-xiaomi-sheng.md))。

## 构建可刷镜像

**先刷新基础镜像**(设备容器),再导出。每设备两条流水线:

| 设备 | 1. 刷新基础镜像 | 2. 导出可刷镜像 |
|---|---|---|
| sheng | [`build-sheng-container.yml`](.github/workflows/build-sheng-container.yml) → `:sheng-latest` | [`build-armada-export.yml`](.github/workflows/build-armada-export.yml)(device 选 sheng) |
| thyme | [`build-thyme-container.yml`](.github/workflows/build-thyme-container.yml) → `:thyme-latest` | [`build-armada-export.yml`](.github/workflows/build-armada-export.yml)(device 选 **thyme**) |

<details>
<summary>更新链路(为什么要先刷容器)</summary>

```
设备内核树更新(sheng: ianchb/sm8550-mainline / thyme: linux-xiaomi-thyme-mainline)
        ↓
build-*-container.yml: 内核镜像 → Armada 容器 (ghcr :sheng-latest / :thyme-latest)
        ↓
build-armada-export.yml: 导出容器 → rootfs.img + boot_b.img → 制品 / Release
```

导出流程不重新构建系统,只导出当前 `:*-latest`——
**想更新系统内容(Steam/软件包/上游 armada 修复),必须先跑容器 workflow。**
</details>

**本地:** `.github/scripts/armada-export-flashable.sh`(需要
`podman`、配套 `mkbootimg.py` 与 `e2fsprogs`;第 5 个参数选设备)。

产物(位于制品目录 / `output/`):

```
boot_b.img     内核 + initramfs + DTB(Android boot image;sheng=header-v0/4096,thyme=header-v1/2048)
rootfs.img     ext4 根文件系统(导出时缩至实际大小,单分区、growfs、/boot 并入根分区)
flash.sh       fastboot 包装脚本(校验 → 按设备刷 boot 分区 → 刷写 → 重启)
SHA256SUMS     上述所有文件的校验和
MANIFEST.txt   构建元数据
```

### 各设备烘焙内容

**sheng**(容器构建 `50/52-sheng-*` + 导出脚本注入):

- `xiaomi-sheng-thp` 0.3.9 + `libssc` 0.4.2(用户态触摸 → uinput)及其
  Fedora 运行时库、`modules-load.d/uinput.conf`、启用 `xiaomi-sheng-thp.service`
- MiPPS 快充 / 充电显示 / 触控笔状态 / 键盘助手(可选 deb,失败仅告警)
- sheng 的 ALSA UCM2(`/usr/share/alsa/ucm2/Xiaomi/sheng/`)
- sheng 设备固件(导出时来自 `ianchb/sheng-firmware`)+ `novatek/nt36532e.bin` 别名

**thyme**(容器构建 `52-thyme-device-fixes.sh`;固件/UCM 已提交进仓库):

- 触摸为内核态 ST FTS(无用户态组件;无需 .ftb,固件在 IC flash 内)
- thyme ALSA UCM2(`ucm2/conf.d/sm8250/`,声卡
  `XIAOMI-UMI-WCD9380-CS35L41-VA-DMIC`,扬声器/听筒/内置麦克风)
- thyme 固件(`system_files/usr/lib/firmware/`):`qcom/sm8250/umi/`(adsp/cdsp/
  venus/slpi/a650_zap)、`cirrus/` CS35L41 thyme 调音、`ath11k/QCA6390`、
  `qca/` BT nv —— 全部从本机提取
- USB gadget RNDIS 网络 + sshd、`steam-now` 离线回退、SELinux permissive
  (与 sheng 相同)

两设备共同:`steamos-update` / `steamos-select-branch` 替换为提示(本构建无 OTA)。

## 刷写

**单系统模式**(占用/擦除 Android 的 `userdata` 分区,不支持双系统)。

sheng:

```console
$ fastboot erase dtbo_b
$ fastboot flash boot_b boot_b.img
$ fastboot erase userdata
$ fastboot flash userdata rootfs.img
$ fastboot reboot
```

thyme(A/B 双槽都刷,槽位无关):

```console
$ fastboot flash boot_a boot_b.img
$ fastboot flash boot_b boot_b.img
$ fastboot erase userdata
$ fastboot flash userdata rootfs.img
$ fastboot reboot
```

也可以直接运行自带的 `flash.sh`(按设备自动选择分区,固定刷 `userdata`)。
完整流程与故障排查见
[docs/flashing-xiaomi-sheng.md](docs/flashing-xiaomi-sheng.md) /
[docs/flashing-xiaomi-thyme.md](docs/flashing-xiaomi-thyme.md)。

## 开发

开发配方需要 [just](https://just.systems/) 与
[Podman](https://podman.io/):

```console
$ just --list                       # 查看镜像与 sheng/thyme 配方
$ just build-sheng-kernel           # ianchb/sm8550-mainline @ sheng-7.2.2 → 内核镜像
$ just build-sheng-image <kernel>   # sheng 内核 → Armada 容器
$ just build-thyme-kernel           # linux-xiaomi-thyme-mainline → 内核镜像
$ just build-thyme-image <kernel>   # thyme 内核 → Armada 容器(ARMADA_DEVICE=thyme)
$ just build-thyme-flashable <kernel>  # 容器 → BIB raw → fastboot 镜像
```

路径说明:

- 内核镜像(`.github/workflows/build-sheng-disk.yml` 仍保留旧版 BIB 步骤;
  **当前有效**的可刷写路径是上面的容器导出流水线)。
- `kernel-sheng/BUILD.env`、`kernel-thyme/BUILD.env` 分别固定
  `KERNEL_REPO`/`KERNEL_BRANCH`/`KERNEL_CONFIG`;thyme 支持
  `KERNEL_SRC=<本地树>` 直接构建(移植工作站的树带未提交修复)。
- 设备在容器构建时由 `ARMADA_DEVICE` 选择(`build_files/build.sh` 运行
  对应的 `52-*-device-fixes.sh`);导出时由 `--device` / 第 5 参数选择
  bootimg 几何与 flash 脚本。

通用包构建(上游链路,慢):

```console
$ just check     # 运行测试套件并检查配方格式
$ just packages  # 构建镜像消费的包(冷启动很慢)
$ just build     # 构建本地 bootc 容器镜像
```

欢迎提交 Issue 与 PR。

## 致谢

claude codex deepseek harness

项目上游见[项目致谢页](https://armadaos.dev/project/credits/)。`sheng` 的
内核、固件与 ALSA UCM 配置源自 [ianchb](https://github.com/ianchb)
(sm8550-mainline / sheng-firmware / xiaomi-sheng-thp);`thyme` 的内核来自
[yuweiyuan8](https://github.com/yuweiyuan8/linux-xiaomi-thyme-mainline),
固件与 UCM2 提取自本机(声卡 UCM 捕获链源自
royka1/Xiaomi-Apollo-pmOS-packages)。

## 许可

Armada 自有代码采用 **GPL-2.0-or-later** 许可。捆绑组件保留其上游许可。
详见 [LICENSE.md](LICENSE.md)。
