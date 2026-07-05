# ASRock Z490M-ITX/ac Hackintosh OpenCore EFI

![macOS Ventura](https://img.shields.io/badge/macOS-Ventura_13.x-blue.svg)
![OpenCore](https://img.shields.io/badge/OpenCore-1.0.0-green.svg)
![SMBIOS](https://img.shields.io/badge/SMBIOS-Macmini8,1-orange.svg)

This repository contains the OpenCore EFI configuration for the **ASRock Z490M-ITX/ac** motherboard, highly optimized for **10th Gen Intel CPUs (Comet Lake)** running strictly on Intel UHD Graphics 630 (No Discrete GPU).

## 🖥 Hardware Specifications

| Component | Model / Details |
| :--- | :--- |
| **Motherboard** | ASRock Z490M-ITX/ac |
| **CPU** | Intel Core i9-10900T ES (QTB0) |
| **IGPU** | Intel UHD Graphics 630 |
| **Audio** | Realtek ALC892 |
| **Network** | Realtek 2.5GbE (RTL8125BG) + Intel Gigabit (I219V) |
| **Wi-Fi / BT** | Intel Dual Band Wireless-AC 3168 (or compatible swapped BCM card) |
| **Storage** | Lexar / Colorful NVMe, FORESEE SATA SSD |

## ✨ What Works

- [x] **Intel UHD 630 IGPU**: Dual display output via DisplayPort and HDMI.
- [x] **Hardware Acceleration**: Full H.264 and HEVC (H.265) hardware decoding/encoding in VideoProc.
- [x] **Audio**: Front and Rear ports working perfectly (`layout-id=69`).
- [x] **USB Ports**: Custom mapped using `UTBMap.kext` under the 15-port limit.
- [x] **Sleep / Wake**: Native power management.
- [x] **Wi-Fi & Bluetooth**: Functional natively (Requires configuring Intel/BCM kexts based on your specific card).

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

---

## ⚠️ Post-Installation Steps

**Generate Your Own SMBIOS!**
This EFI comes with generated `Macmini8,1` serial numbers for testing, but they **must be changed** before logging into your Apple ID to prevent your account from being flagged.
1. Download [GenSMBIOS](https://github.com/corpnewt/GenSMBIOS).
2. Generate a valid `Macmini8,1` profile.
3. Replace the `SystemSerialNumber`, `MLB`, and `SystemUUID` inside `config.plist -> PlatformInfo -> Generic`.

*(Note: Currently, `AppleDebug` and `Target=65` are enabled in this EFI to capture boot logs (`opencore-xxxx.txt`) at the root of the EFI partition for further phase 2 system refinement. Please delete these logs periodically so your EFI partition does not run out of space, or set `Target=0` and disable `AppleDebug` when you are done troubleshooting.)*

## Credits
- [Acidanthera](https://github.com/acidanthera) for OpenCore and crucial kexts.
- [Dortania](https://dortania.github.io/OpenCore-Install-Guide/) for the OpenCore Install Guide.
- [Xmingbai](https://github.com/Xmingbai) for the baseline ASRock Z490M-ITX IGPU physical mapping logic.