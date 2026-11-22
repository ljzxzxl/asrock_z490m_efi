# ASRock Z490M-ITX/ac Hackintosh OpenCore EFI

![macOS Ventura](https://img.shields.io/badge/macOS-Ventura_13.x-blue.svg)
![OpenCore](https://img.shields.io/badge/OpenCore-1.0.0-green.svg)
![SMBIOS](https://img.shields.io/badge/SMBIOS-Macmini8,1-orange.svg)

> **⚠️ 重要声明：纯核显环境专用 (iGPU-Only)**
> 本 EFI 配置专为 **无独立显卡（仅使用 Intel UHD 630 核显）** 的环境打造。
> SMBIOS 已配置为 `Macmini8,1` 以实现完美的 H.264/HEVC 硬件解码和多屏输出。如果你有独立显卡（如 RX 580），请不要直接使用本配置，否则可能会遇到黑屏或解码异常！

This repository contains the OpenCore EFI configuration for the **ASRock Z490M-ITX/ac** motherboard, highly optimized for **10th Gen Intel CPUs (Comet Lake)** running strictly on Intel UHD Graphics 630 (No Discrete GPU).

## 🖥 Hardware Specifications

| Component | Model / Details |
| :
### 4. 🔌 USB 映射方案切换指南 (备选方案)
当前 EFI 默认启用了精确适配 15 端口限制的原生无代码驱动 `USBPorts.kext`（已洗白匹配 `Macmini8,1` 机型），带来纯净的原生映射体验。

**备用方案（推荐在遇到特定设备兼容性问题时启用）：**
我们在 EFI 中保留了 `USBToolBox.kext` + `UTBMap.kext` 的组合方案，但默认处于禁用状态。若使用原生驱动遇到异常需要切换：
1. 打开 OpenCore Configurator。
2. 在 Kernel (内核) 设置中，**取消勾选** `USBPorts.kext` 以禁用它。
3. **勾选启用** `USBToolBox.kext` 和 `UTBMap.kext`。
4. 保存重启，并建议在启动菜单重置一次 NVRAM。

--- | :--- |
| **Motherboard** | ASRock Z490M-ITX/ac |
| **CPU** | Intel Core i9-10900T ES (QTB0) |
| **IGPU** | Intel UHD Graphics 630 |
| **Audio** | Realtek ALC892 |
| **Network** | Realtek 2.5GbE (RTL8125BG) + Intel Gigabit (I219V) |
| **Wi-Fi / BT** | Dell DW1560 (Broadcom BCM94352Z) |
| **Storage** | Lexar / Colorful NVMe, FORESEE SATA SSD |

## ✨ What Works

- [x] **Intel UHD 630 IGPU**: Dual display output via DisplayPort and HDMI.
- [x] **Hardware Acceleration**: Full H.264 and HEVC (H.265) hardware decoding/encoding in VideoProc.
- [x] **Audio**: Realtek ALCS1200A with `layout-id=49`. Rear line-out, rear microphone (pink jack) and line-in verified. (`layout-id=69` routes the rear mic and the front-panel jack through the same ADC, so macOS only offers "Line In" and the microphone is unusable.)
- [x] **USB Ports**: Custom mapped using native `USBPorts.kext` under the 15-port limit.
- [x] **Sleep / Wake**: Native power management.
- [x] **Wi-Fi & Bluetooth**: Native AirDrop / Handoff / Sidecar via DW1560 on **SimpleBCM 1.2.0** (no root patch, no `IOSkywalkFamily` downgrade). Intel cards remain available as a disabled fallback.

---

## 🛠 BIOS Settings (Recommended)

Before booting with this EFI, please ensure your BIOS is configured correctly:

**Disable:**
- Fast Boot
- Secure Boot
- CFG Lock (Very important! If no option is available, ensure `AppleXcpmCfgLock` is enabled in `config.plist` Quirks)
- VT-d
- CSM

**Enable:**
- VT-x
- Above 4G Decoding
- Hyper-Threading
- Execute Disable Bit
- EHCI/XHCI Hand-off
- OS type: Windows 8.1/10 UEFI Mode
- DVMT Pre-Allocated: **64MB** or higher

---

## 🚀 The Configuration Journey & Key Fixes

This EFI was painstakingly built and refined through multiple debugging sessions. If you are building a similar machine, here are the specific hurdles we overcame:

### 1. NVMe Kernel Panic (`AppleNVMe Assert failed`)
**The Issue:** Lexar and Colorful NVMe drives are notoriously hostile to macOS, causing the installer to hang instantly with an `AppleNVMe` kernel panic.
**The Fix:** We injected `NVMeFix.kext` and strongly recommend installing macOS onto a standard SATA SSD (like the FORESEE SSD used here) or a known compatible NVMe (like Western Digital or Samsung) to bypass the panic.

### 2. USB Installer Disconnect (`Waiting for Root Device`)
**The Issue:** The installer would boot, but the USB drive would disconnect right when mounting `BaseSystem.dmg` due to macOS 15-port limits enforcing an XHCI reset.
**The Fix:** Created a custom `UTBMap.kext`. During installation, we forcefully mapped `HS01` to `HS14` (ensuring every single USB 2.0 interface, including fallbacks, was kept alive) to ensure the installer flash drive survived the boot transition.

### 3. The "Black Screen" & HEVC Decoding Nightmare
**The Issue:** Running as `iMac20,2` required a headless IGPU profile for HEVC, which broke display output. Switching to `Macmini8,1` (which macOS expects to have a native IGPU with display) led to black screens or broken HEVC decoding due to framebuffers overflowing or misaligned BusIDs.
**The Fix (The "Excalibur" Patch):** 
We adopted the highly optimized ASRock Z490M-ITX IGPU configuration from the community (credit to Xmingbai) with specific modifications:
- **Platform-ID**: `07009B3E` (Native Mac mini Desktop)
- **Device-ID**: `3E9B0000` (Native Coffee Lake disguise)
- **Unified Memory Injection**: `framebuffer-unifiedmem` set to `AAAAgA==` (**2048MB**). Without this, initializing the HEVC engine causes an instant VRAM overflow and black screen.
- **Precise BusID Mapping**: Mapped exact physical motherboard routing (`alldata`) for DP (`BusID 0x04`) and HDMI (`BusID 0x02`), ensuring both ports light up flawlessly.
- **GuC Firmware**: `igfxfw=2` injected to force load Apple's graphics micro-controller firmware to enable the media engine.

### 5. 📶 Wi-Fi & Bluetooth 方案切换 (Broadcom vs Intel)
当前 EFI 默认配置为支持 **Dell DW1560 (Broadcom BCM94352Z, `14e4:43b1`)** 网卡，以实现原生的隔空投送 (AirDrop)、接力 (Handoff) 与随航 (Sidecar)。WiFi 由 `SimpleBCM.kext` 驱动；蓝牙仍由 `BrcmPatchRAM3` / `BrcmFirmwareData` / `BlueToolFixup` 三件套驱动，与 WiFi 方案互相独立。

**如果你使用的是主板自带的 Intel 网卡（如 AC3168/AX200 等）：**
请勿直接启动，否则会导致网卡无法识别或内核崩溃。请在 `config.plist` 中进行如下调整：
1. **禁用 Broadcom 驱动**：在 Kernel -> Add 中，将 `SimpleBCM.kext`、`BrcmFirmwareData.kext`、`BrcmPatchRAM3.kext`、`BlueToolFixup.kext`、`AirportBrcmFixup.kext` 及其 Injector 插件的 `Enabled` 设为 `False`。
2. **启用 Intel 驱动**：在 Kernel -> Add 中，将 `AirportItlwm.kext`、`IntelBluetoothFirmware.kext` 和 `IntelBTPatcher.kext` 的 `Enabled` 设为 `True`。
3. **移除引导参数**：在 NVRAM 的 `boot-args` 中，删除 `brcmfx-driver=2` 和 `brcmfx-country=#a`。

#### macOS 14/15/26 上的无线方案：SimpleBCM 1.2.0（本分支）

macOS 14 起 Apple 移除了旧博通驱动，本仓库 `imac` 分支原先采用 OCLP-Mod 方案：
EFI 注入 `IOSkywalkFamily.kext` (1.0) + `IO80211FamilyLegacy.kext` + `AirPortBrcmNIC.kext`、
`Kernel → Block` 排除系统原生 Skywalk，配合 `AMFIPass.kext` 与用户态 root patch
（`IO80211.framework`、`WiFiPeerToPeer.framework`、`/usr/libexec/wifip2pd`）。
该方案每次系统更新都会被冲掉，无线失效并复现约 4 分半的 PXSX 黑屏停摆，
且系统卷封印被破坏（`Snapshot Sealed: Broken`），只能下载完整安装器做更新。

本分支改用 [SimpleBCM](https://github.com/laobamac/SimpleBCM) **v1.2.0 正式版**（RELEASE 包，
非 1.2.1-alpha）：单个 Lilu 插件内嵌 Legacy / AirPort 载荷，直接适配各系统**原生**
`IOSkywalkFamily`，不改系统卷、不需要 root patch。同款 DW1560 (`14e4:43b1`) 已在
Sequoia / Tahoe 上有实机成功案例。

**config.plist 净变化**

| 项 | 状态 |
| --- | --- |
| `SimpleBCM.kext` | 新增并启用，`MinKernel=23.0.0` / `MaxKernel=25.99.99` |
| `AirportBrcmFixup.kext` + `AirPortBrcmNIC_Injector.kext` | 保留（43b1 需要注入 personality） |
| 加载顺序 | `Lilu → AirportBrcmFixup → SimpleBCM → AirPortBrcmNIC_Injector`（官方 `Extra/config.AirportBrcmFixup.fragment.plist` 指定） |
| `IOSkywalkFamily.kext` / `IO80211FamilyLegacy.kext` / 其 `AirPortBrcmNIC.kext` 插件 | `Enabled=false`；文件保留作回退，**必须禁用，否则 Panic** |
| `Kernel → Block` 的 `com.apple.iokit.IOSkywalkFamily` (Exclude) | `Enabled=false`，原生 Skywalk 必须加载 |
| `AMFIPass.kext` | `Enabled=false`，不再需要 |
| `csr-active-config` | `0xA03 → 0x803`（去掉 `CSR_ALLOW_UNAUTHENTICATED_ROOT`） |
| `boot-args` | 不变，`brcmfx-driver=2 brcmfx-country=#a` 继续供 Fixup 使用 |
| `DisableIoMapper` | 保持 `true`（BIOS 中 VT-d 为 Disable，见 BIOS 章节） |
| 蓝牙三件套 + NVRAM 蓝牙变量 | 完全不变 |

> 收益：系统更新不再冲掉无线；封印恢复后可增量 OTA；原生 Skywalk 正常工作，
> RTL8125BG 2.5G 与 I219V 不再受降级影响；随航 / 隔空等功能可用（OCLP 方案随航会黑屏）。

**⚠️ 迁移前置：必须先恢复系统卷封印**

`config.plist` 里的 `csr=0x803` 会重新启用 authenticated-root。若系统卷仍是
`Snapshot Sealed: Broken`（当前 `imac` 分支打过 root patch），**直接换本 EFI 会无法启动**。
请先用**旧 EFI** 启动一次并完成：

1. 装回 [OCLP-Mod](https://github.com/laobamac/OCLP-Mod) → `Post Install Root Patch`
   → `Revert Root Patches`（中文界面为「删除已安装的补丁」），回退到最近一次封印快照；
   或直接原地重装 macOS 15.8.2（保留数据）。
2. 重启，确认 `diskutil apfs list` 中 `Snapshot Sealed: Yes`。
3. 再执行 `Tools/Apply-SimpleBCM-EFI.sh`（脚本会强制检查封印状态，未恢复则拒绝同步）。

脚本会先整份备份 ESP 上的 EFI，再同步 `BOOT/` 与 `OC/`（不删除 ESP 上已有的 config
备份、日志与 `.comate` 文档），最后校验 `config.plist` 与 kext 完整性。
重置 NVRAM 后重启即可让 `csr=0x803` 生效。

**验证清单**

```sh
kmutil showloaded | grep -iE "simplebcm|skywalk|80211|brcm|amfipass"
system_profiler SPAirPortDataType      # WiFi 已连接、AirDrop / Auto Unlock Supported
system_profiler SPBluetoothDataType   # State: On
csrutil authenticated-root status     # enabled
diskutil apfs list | grep "Snapshot Sealed"   # Yes
```

另外实测 AirDrop 双向、Handoff、睡眠唤醒后自动重连、RTL8125 / I219V 有线网络。

**回退**：`Tools/Rollback-SimpleBCM-EFI.sh /Volumes/EFI/EFI-Backup-<时间戳>`。
注意回退到 OCLP 方案后，若系统卷已 revert，需重新用 OCLP-Mod 打网卡 root patch，
否则无线不可用并会复现 4 分半停摆。

**已知限制**

- v1.2.0 存在「互联网共享 / 把有线共享成 WiFi 热点」导致黑屏重启的 bug，作者确认将在
  v1.2.1 正式版修复（[远景反馈帖](https://bbs.pcbeta.com/viewthread-2084816-1-1.html)）。
  OCLP 方案下该功能可用 —— 如果依赖热点，请暂缓迁移。
- 不要使用 `v1.2.1-alpha`；作者已宣布 1.2.1 正式版会改回双 kext 架构。
- 可选启动参数：`sbcmdelay=<毫秒>` 延迟加载内嵌驱动、`-simplebcmoff` 整体禁用；
  `-sbcmawdlcc` / `-sbcmdma` 仅对 Tahoe 生效且默认关闭。

官方配置片段、第三方许可与 kext 校验清单见 `Docs/SimpleBCM/`。


---

### 6. macOS 13 → 15 升级后的启动与耗时问题

**The Issue:** 升级到 macOS 15.7.9 后出现三个现象：升级途中反复失败（ESP 上留下 0 字节的 OpenCore 日志）、
verbose 跑完后黑屏 4 分半、verbose 末段输出极慢。

**The Fixes:**
- **APFS 驱动版本错配**：原先靠手动放置的 `apfs_aligned.efi`（APFS `2332.120.31.0.2`）加载，
  而容器已被 macOS 15 升级到 `2332.140.13.702.2`。改为 `UEFI -> APFS -> EnableJumpstart = True`
  并停用 `apfs_aligned.efi`，由容器自带的 apfs.efi 提供，版本永远匹配。
- **4 分半黑屏**：`kernelmanagerd` 在等一个永远匹配不上的 PCIe 设备（无线网卡），
  由 OCLP-Mod 方案下 root patch 被系统更新冲掉、驱动缺失引起；本分支改用 SimpleBCM 后
  不再依赖 root patch，详见上面 Wi-Fi 章节。
- **verbose 输出慢**：`UEFI -> Output -> Resolution` 原为 `Max`，在 4K 显示器上使 EFI framebuffer
  工作在 3840×2160，内核文字靠软件滚动。改为 `1920x1080@32`。历史日志中唯一的 OpenCore 报错
  `Changed resolution to 0x0@0 ... from Max - Unsupported` 也来自这里。
- **清理无效项**：停用 `XHCI-unsupported.kext`（Z490 原生支持 XHCI）与 `USBWakeFixup.kext`（2018 年遗留），
  移除 `igfxonln=1`（它使集显加速器每次启动多 5 秒 `waitForStamp` 超时），
  `PanicNoKextDump` 改为 `False` 以便 panic 时能看到 kext 列表。

---

## ⚠️ Post-Installation Steps

**Generate Your Own SMBIOS!**
This EFI comes with generated `Macmini8,1` serial numbers for testing, but they **must be changed** before logging into your Apple ID to prevent your account from being flagged.
1. Download [GenSMBIOS](https://github.com/corpnewt/GenSMBIOS).
2. Generate a valid `Macmini8,1` profile.
3. Replace the `SystemSerialNumber`, `MLB`, and `SystemUUID` inside `config.plist -> PlatformInfo -> Generic`.

*(Note: Currently, `AppleDebug` and `Target=67` are enabled in this EFI to capture boot logs (`opencore-xxxx.txt`) at the root of the EFI partition for further phase 2 system refinement. Please delete these logs periodically so your EFI partition does not run out of space, or set `Target=0` and disable `AppleDebug` when you are done troubleshooting. Note that the log filename uses the firmware RTC, i.e. **UTC**, so it is 8 hours behind CST.)*

## Credits
- [Acidanthera](https://github.com/acidanthera) for OpenCore and crucial kexts.
- [Dortania](https://dortania.github.io/OpenCore-Install-Guide/) for the OpenCore Install Guide.
- [Xmingbai](https://github.com/Xmingbai) for the baseline ASRock Z490M-ITX IGPU physical mapping logic.