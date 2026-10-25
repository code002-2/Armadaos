# 刷写 Armada 至小米 10S(thyme)— 内部存储(单系统)

这是 Armada 面向小米 10S(codename `thyme`,SM8250 / 骁龙 870)的内部存储
构建路径,与 sheng(小米平板 6S Pro)变体同构:

- 通过**原厂小米 ABL** 从 **Android 分区**启动;
- 使用专属内核 —
  [yuweiyuan8/linux-xiaomi-thyme-mainline](https://github.com/yuweiyuan8/linux-xiaomi-thyme-mainline)
  (mainline **7.2.0-rc5**,自带 DTS / CSOT 面板 / ST FTS 触摸 / WCD938x +
  CS35L41 音频 / 相机 / SDX55 基带支持);
- 根文件系统为**普通 ext4** — **无 bootc、无 OSTree、无 OTA**,升级即重新刷写;
- **仅支持单系统**:直接刷入 Android 的 `userdata` 分区,不保留 Android 数据。

镜像来自**容器导出**流水线:

```
.github/workflows/build-thyme-container.yml   # 刷新基础镜像(:thyme-latest)
.github/workflows/build-armada-export.yml     # 导出可刷镜像(device 选 thyme)
.github/scripts/armada-export-flashable.sh    # 本地(podman + mkbootimg)
```

## 与 sheng 的关键差异

| 项 | sheng(平板 6S Pro) | thyme(小米 10S) |
|---|---|---|
| SoC | SM8550 | SM8250 |
| boot.img 几何 | header-**v0**、pagesize **4096** | header-**v1**、pagesize **2048**、kernel/tags `0x10000000`(实机验证,见内核树 `thyme-camera/tools/pack-bootimg.py`) |
| ABL 取 DTB | 追加在 gzip 内核流之后 | 相同(ABL 扫描追加 blob,按 `qcom,msm-id`/`board-id` 匹配) |
| 刷写 boot 分区 | 仅 `boot_b`(+擦 `dtbo_b`) | **`boot_a` + `boot_b` 都刷**(A/B 双槽,槽位无关),不擦 dtbo |
| 触摸屏 | 用户态 `xiaomi-sheng-thp`(THP → uinput) | **内核态 ST FTS**(`st,fts`,真输入设备,无需守护进程;固件在触摸 IC flash 内,无需 .ftb 文件) |
| 音频 | 6× CS35L43 + WCD938X(sm8550 UCM2) | WCD938x + 2× CS35L41,**声卡名 `XIAOMI-UMI-WCD9380-CS35L41-VA-DMIC`**,UCM2 取自本机已验证配置(`conf.d/sm8250/`) |
| WiFi/BT | WCN7850/WCN7860(ath12k) | **QCA6390**(PCIe ath11k + uart6 `hci_qca`),固件已内置 |
| 电池/充电 | MiPPS 生态(可选 deb) | SMB2(`CONFIG_CHARGER_QCOM_SMB2`),无用户态鉴权需求 |

## 产物

| 文件 | 说明 |
|---|---|
| `boot_b.img` | Android 启动镜像(header-v1):gzip(Image) + DTB + initramfs;启动参数 `root=PARTLABEL=userdata rw rootwait` |
| `rootfs.img` | **ext4** 根文件系统(导出时缩至实际大小),单分区,`x-systemd.growfs`,`/boot` 并入根分区 |
| `flash.sh` | fastboot 包装脚本(校验 → 刷 `boot_a`+`boot_b` → 擦除+刷 `userdata` → 重启) |
| `SHA256SUMS` | 上述所有文件的校验和 |
| `MANIFEST.txt` | 构建元数据(容器引用、内核版本、bootimg 几何) |

rootfs 内已烘焙的 thyme 专属内容(均随容器构建,`52-thyme-device-fixes.sh`):

- **触摸屏**:内核态 `st,fts` 驱动(输入设备 `fts`),无额外用户态组件;
- **音频**:thyme UCM2(扬声器/听筒/内置麦克风,`XIAOMI-UMI-WCD9380-CS35L41-VA-DMIC`);
- **固件**:`qcom/sm8250/umi/`(adsp/cdsp/venus/slpi/zap)、`cirrus/` CS35L41
  thyme 调音、`ath11k/QCA6390`、`qca/` BT nv — 全部已提交进仓库
  (`system_files/usr/lib/firmware/`,从本机提取);
- **SSH / USB 网络**:`sshd.service` + `armada-usbgadget.service`
  (RNDIS,主机端 `192.168.42.1`);
- **Steam 启动器**:`steam-now`(探测 Steam CDN,不通则回退 `-offline`);
- **SELinux**:permissive(容器标签;可重新标记后开启 enforcing)。

## 前置条件

- 已**解锁 bootloader** 的小米 10S(保留原厂 ABL,不要刷入其他 ABL);
- 电脑端安装 `fastboot`;
- USB 数据线。**请先备份数据 —— 本流程会擦除 `userdata` 分区。**

## 刷写

下载 `armada-flashable-no-ota` 制品(export workflow 选
device `sm8250-xiaomi-thyme`),解压后运行:

```
cd armada-flashable-no-ota/
./flash.sh
```

等价命令:

```
fastboot flash boot_a boot_b.img
fastboot flash boot_b boot_b.img
fastboot erase userdata
fastboot flash userdata rootfs.img
fastboot reboot
```

> [!IMPORTANT]
> 必须刷**同一次构建**的 `boot_b.img` 与 `rootfs.img` —— initramfs 与
> 根文件系统通过文件系统 UUID 绑定。混用不同构建的镜像会导致启动卡住。
>
> A/B 双槽都刷 `boot_b.img` 的内容:无论当前激活槽是 a 还是 b,启动的都是
> Armada。如需确认槽位:`fastboot getvar current-slot`。

## 首次启动

- 首次启动需几分钟(ext4 扩容;Steam 引导已预制);
- 登录:用户 `armada` / `armada`(修改密码:`passwd armada`);
- 屏幕:6.67" 1080×2340 竖屏 AMOLED(CSOT MP42020B)。Steam 游戏模式 /
  KDE Plasma 桌面可在会话切换器中选择;
- 触摸:开箱即用(内核态 ST FTS,`/proc/bus/input/devices` 中为 `fts`);
- 音频:扬声器/听筒/麦克风走 UCM2;若无声先检查
  `cat /proc/asound/cards` 是否出现 `XIAOMI-UMI-WCD9380-CS35L41-VA-DMIC`。
  听筒要点:独立听筒在 WCD938x 的 EAR 输出(不是上扬声器),走
  `RX_CODEC_DMA_RX_0` 后端,UCM 里 `RX_EAR Mode Switch=1` 是出声的
  关键设置(INT0 输出切到 EAR 模拟通路);`RX HPH Mode` 保持驱动默认
  (CLS_H_LOHIFI 即原厂值在此硬件上完全无声,勿设);
- 已知问题1:听筒音质断续/失真,与 class-H 模式无关(NORMAL/LP/AB
  相近),数字链路(PCM/DSP/SWR)排查无异常,疑点在 SWR 数据打包或
  EAR 模拟路径,需内核级进一步定位;
- 已知问题2:通话无声——内核 q6voice 的校准注册被 CVD 拒绝
  (`q6voice-cal.bin`/`q6voice-vol-cal.bin` 需按 CVD 2.4 重新提取,
  未注册校准时 DSP 拒绝音量步进 0x112c2,见内核 q6voice.c 注释);
  且 CVP 会话默认落到 TERT 扬声器端口,通话路由待修。

## 设备说明

- **WiFi**(QCA6390 / ath11k):固件已内置(`ath11k/QCA6390/hw2.0/`)。
  若 `ip link` 无 wlan0,查 `dmesg | grep ath11k`。
- **蓝牙**(uart6 / hci_qca):`qca/hpnv21*` nv 已内置;配对手柄即用。
- **挂起**:SM8250 s2idle;设备配置声明 `ARMADA_SUSPEND_MODE=s2idle`
  (内核无 s2idle 时 device-env 自动回退 fake suspend)。
- **基带/蜂窝**(SDX55 over MHI):内核片段 `thyme-modem.config` 已并入
  (`CONFIG_MHI_*`/WWAN),用户态调制解调器管理(ModemManager)未预配。
- **相机**:内核驱动在树(S5KHMX/S5K3T2/OV13B10),但 Armada 会话未集成
  libcamera 管线 —— 桌面端可用性待验证(本机 chroot Ubuntu 上的
  thyme-camera 用户态在 `/mnt/ubuntu`,见内核树 `thyme-camera/README.zh-CN.md`)。

## 尚未移植 / 待验证

| 功能 | 状态 |
|---|---|
| 蜂窝数据 / 通话 | 内核 MHI/WWAN 已开;用户态未配 |
| 相机(桌面集成) | 内核驱动在树;libcamera 管线未打包 |
| NFC(IR 是 `ir-spi`,NFC 节点在树) | 用户态未配 |
| 指纹(TEE) | 不支持(专有 TEE 栈) |
| HDR / 高刷 | 面板 90Hz;当前按 60Hz 点亮,HDR 未启用 |

## 故障排查

- **刷后不开机(黑屏/回 fastboot)** — 单独重刷:
  `fastboot flash boot_b boot_b.img`(若当前槽为 a 则刷 `boot_a`)。
  本机验证过的几何是 header-v1 / pagesize 2048;若手动用其他工具打包,
  确保 DTB 追加在 gzip 流之后(ABL 按 `qcom,msm-id = <0x164 0x20001>`、
  `board-id = <0x2d 0>` 匹配)。
- **触摸无反应** — `dmesg | grep -i fts`;ST FTS 固件在 IC flash 内,
  无需 .ftb。确认 `/proc/bus/input/devices` 有 `Name="fts"`。
- **无声** — `cat /proc/asound/cards` 应出现
  `XIAOMI-UMI-WCD9380-CS35L41-VA-DMIC`;没有则说明 ADSP 未就绪
  (`dmesg | grep -E 'q6|adsp|apr'`),重启通常可恢复。
- **WiFi 不工作** — `dmesg | grep ath11k`;确认
  `/usr/lib/firmware/ath11k/QCA6390/hw2.0/` 存在。
- **Steam 提示"无法下载所需更新"** — Valve CDN 在国内直连不稳定,
  配置 HTTP 代理或用 `steam-now` 离线模式(见 sheng 文档同节)。
