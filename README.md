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
- [x] **Audio**: Front and Rear ports working perfectly (`layout-id=69`).
- [x] **USB Ports**: Custom mapped using native `USBPorts.kext` under the 15-port limit.
- [x] **Sleep / Wake**: Native power management.
- [x] **Wi-Fi & Bluetooth**: Native AirDrop and Handoff support via DW1560 (Broadcom kexts injected). Intel cards are also supported as a fallback.

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
当前 EFI 默认配置为支持 **Dell DW1560 (Broadcom BCM94352Z)** 网卡，以实现原生的隔空投送 (AirDrop) 和接力 (Handoff) 体验。相关的 `AirportBrcmFixup.kext` 和 `BrcmPatchRAM3.kext` 均已在配置中激活。

**如果你使用的是主板自带的 Intel 网卡（如 AC3168/AX200 等）：**
请勿直接启动，否则会导致网卡无法识别或内核崩溃。请在 `config.plist` 中进行如下调整：
1. **禁用 Broadcom 驱动**：在 Kernel -> Add 中，将 `BrcmFirmwareData.kext`、`BrcmPatchRAM3.kext`、`AirportBrcmFixup.kext` 及其 Injector 插件的 `Enabled` 设为 `False`。
2. **启用 Intel 驱动**：在 Kernel -> Add 中，将 `AirportItlwm.kext`、`IntelBluetoothFirmware.kext` 和 `IntelBTPatcher.kext` 的 `Enabled` 设为 `True`。
3. **移除引导参数**：在 NVRAM 的 `boot-args` 中，删除 `brcmfx-driver=2` 和 `brcmfx-country=#a`。

#### macOS 15 Sequoia 上的额外要求（DW1560 / BCM94352Z）

macOS 15 已从系统中彻底移除博通无线驱动（`/System/Library/Extensions/AirPortBrcm*.kext` 不存在，
两个 KernelCollection 里也搜不到任何 `brcm` 条目）。此时单靠 `AirportBrcmFixup` + Injector 是**无效**的：
Injector 注入的 personality 指向 `IOClass = AirPort_BrcmNIC`，而该类已不存在，
设备会停在 `!matched, busy 1` 状态，导致 `kernelmanagerd` 连续 4 次 60 秒停摆
（现象：verbose 跑完后黑屏约 4 分半，极易被误判为卡死）。

本 EFI 已内置解决方案，由两部分组成：

**1. EFI 侧注入内核驱动**（均取自 OCLP-Mod `payloads/Kexts/Wifi/`，`MinKernel = 23.0.0`，macOS 13/14 不受影响）

| kext | Bundle ID |
| --- | --- |
| `IOSkywalkFamily.kext` | `com.apple.iokit.IOSkywalkFamily` |
| `IO80211FamilyLegacy.kext` | `com.apple.iokit.IO80211FamilyLegacy` |
| └ `PlugIns/AirPortBrcmNIC.kext` | `com.apple.driver.AirPort.BrcmNIC` |

同时 `Kernel -> Block` 中有一条 `com.apple.iokit.IOSkywalkFamily`（`Strategy = Exclude`，`MinKernel = 23.0.0`），
用于排除系统自带的 Skywalk，让上面注入的旧版生效。
`AirPortBrcmNIC.kext` 的 `IONameMatch` 不含 `14e4:43b1`，因此 `AirportBrcmFixup` +
`AirPortBrcmNIC_Injector` 仍需保持启用来补这个 device id。

**2. 系统侧 root patch（用户态）**

用 [OCLP-Mod](https://github.com/laobamac/OCLP-Mod) 打「网卡: BCM无线网卡」补丁，它只写入
`IO80211.framework`、`WiFiPeerToPeer.framework`、`/usr/libexec/wifip2pd`，不涉及任何 kext。
前置条件：`csr-active-config` 含 `CSR_ALLOW_UNAUTHENTICATED_ROOT (0x200)`，以及放开 AMFI ——
本 EFI 采用 `AMFIPass.kext`（`MinKernel = 24.0.0`）而非 `amfi_get_out_of_my_way=0x1`，
以避免全局关闭 AMFI。

> ⚠️ **每次 macOS 更新都会冲掉 root patch**，届时无线失效，且上述停摆会复现。
> 排查命令：`log show --last boot --predicate 'processID == 0' | grep 'stall\['`，
> 有 `stall[...]: 'PXSX'` 输出就重打一次补丁。


---

### 6. macOS 13 → 15 升级后的启动与耗时问题

**The Issue:** 升级到 macOS 15.7.9 后出现三个现象：升级途中反复失败（ESP 上留下 0 字节的 OpenCore 日志）、
verbose 跑完后黑屏 4 分半、verbose 末段输出极慢。

**The Fixes:**
- **APFS 驱动版本错配**：原先靠手动放置的 `apfs_aligned.efi`（APFS `2332.120.31.0.2`）加载，
  而容器已被 macOS 15 升级到 `2332.140.13.702.2`。改为 `UEFI -> APFS -> EnableJumpstart = True`
  并停用 `apfs_aligned.efi`，由容器自带的 apfs.efi 提供，版本永远匹配。
- **4 分半黑屏**：`kernelmanagerd` 在等一个永远匹配不上的 PCIe 设备（无线网卡），
  详见上面 Wi-Fi 章节。
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