# 🤖 AI Agent Onboarding & Handover Document

**目的**：本文件专为新接入的 AI Agent（如 Comate 等）设计。在开启新会话或会话意外中断后，读取此文档可瞬间恢复项目上下文，避免重复犯错或提出与当前硬件不兼容的方案。

---

## 1. 硬件配置基线
我们在为以下极其特定的硬件环境构建 macOS (Hackintosh) OpenCore EFI：

- **主板**：ASRock Z490M-ITX/ac
- **CPU**：Intel Core i9-10900T ES (QTB0) - Comet Lake 架构
- **显卡**：**仅有核显** (Intel UHD Graphics 630)，**无独立显卡**
- **显示输出**：当前主要依赖 DisplayPort (DP)
- **存储设备**：包含不受 macOS 支持的 Lexar / Colorful NVMe 硬盘，以及被选作 macOS 安装盘的 FORESEE SATA SSD。

**⚠️ 核心 Quirks 警告**：
- **NVMe 兼容性**：因为存在不受支持的 NVMe，系统非常容易触发 `AppleNVMe Assert failed` 内核恐慌。必须保留 `NVMeFix.kext` 并建议将系统安装在 SATA 盘或兼容的 NVMe 盘上。
- **USB 端口限制**：macOS 的 15 端口限制会导致在安装器加载 `BaseSystem.dmg` 时 USB U盘掉线（"Waiting for Root Device"）。我们通过精简并锁定 15 个端口的 `UTBMap.kext` 解决。

---

## 2. 历史会话技术沉淀（The "Journey"）
前三次核心会话攻克了本主板最棘手的几个问题：

1. **解决卡码 (EXITBS:START)** 
   - **问题**：引导卡在 `[EB|LOG:EXITBS:START]` 阶段，内核完全未加载。
   - **解决**：根据 Z490 主板特性，在 `config.plist -> Booter -> Quirks` 中将 `SetupVirtualMap` 修改为 `false`，成功避开内存虚拟映射崩溃。

2. **切换 SMBIOS 与修复 HEVC 核显加速**
   - **问题**：原配置 `iMac20,2` 需要独显处理 HEVC，导致纯核显环境下 HEVC 解码失败或黑屏。
   - **解决**：将 SMBIOS 全局更改为 **`Macmini8,1`**（这是 8~10 代纯核显的黄金标准），并配合注入 `2048MB` 统一内存（`framebuffer-unifiedmem`）和精准的 BusID 物理映射（DP `BusID 0x04`），完美激活了 UHD 630 的 H.264/HEVC 硬件编解码，同时双屏输出正常。

3. **文档与代码库规范化**
   - **内容**：生成了详尽的 `README.md`，记录了 BIOS 设置规范（如必须开启 Above 4G，关闭 CFG-Lock），并梳理了整个配置过程的里程碑，保持了仓库的极高规范性。

---

## 3. 当前状态与下一步待办

**当前 EFI 状态**：配置已高度成熟，可以稳定引导并提供完整的硬件加速、USB 支持和音视频功能。

**未来会话 / 用户需完成的任务（TODOs）**：
1. **SMBIOS 序列号洗白**：当前 `config.plist` 中的 `Macmini8,1` 序列号仅为占位符。若要使用 iMessage / FaceTime，需要运行 GenSMBIOS 重新生成一套完整的三码（Serial, Board Serial, UUID）。
2. **清理 DEBUG 日志**：目前 EFI 仍开启了 `AppleDebug` 并在 EFI 根目录输出 `opencore-xxxx.txt`。排错完全结束后，可以修改 `Misc -> Debug -> Target` 为 `0` 以停止日志输出，防止 EFI 分区空间被占满。
3. **Wi-Fi / 蓝牙驱动迭代**：若后续更换了无线网卡（如 BCM 拆机卡），需要根据对应的网卡型号开关对应的 AirportItlwm 或 BrcmPatchRAM kexts。

**Agent 介入指南**：
> 当你阅读到本文件时，说明你已经成功加载了上下文。在后续进行任何 `config.plist` 的修改或 Kext 升级时，**请绝对不要**破坏 `Macmini8,1` 的身份设定以及现有的 `UTBMap` 映射。保持目前的极简主义，仅做增量或必要的适配更新。
---

## 4. 人机协作调试流（Debugging Workflow）
由于当前工作的电脑（宿主机）和待安装测试的机器（目标黑苹果主机）是物理隔离的，我们之间（用户与 AI Agent）采用基于外部存储设备（U盘或移动硬盘）的闭环调试模式：

1. **修改与同步 (AI 主导)**：AI 在当前宿主机的项目中修改引导文件（如 `config.plist`、添加 Kexts 等），并将最新的 EFI 配置同步复制到已挂载的 U盘/移动硬盘的 EFI 分区中（路径通常为 `/Volumes/EFI`）。
2. **物理拔插与引导测试 (用户主导)**：用户将 U盘从宿主机拔下，插入黑苹果目标机进行开机测试。在此阶段，开启了 Debug 模式的 OpenCore 会将最新的启动日志写入 U盘的 EFI 根目录下（如 `opencore-xxxx.txt`）。
3. **回传与挂载 (用户主导)**：测试完毕（成功或遇到卡码/死机）后，用户将 U盘重新插回当前宿主机，并再次将 EFI 分区挂载为 `/Volumes/EFI`。
4. **日志读取与分析 (AI 主导)**：AI 直接读取 `/Volumes/EFI` 中新产生的日志文件，结合用户提供的错误现象反馈，定位故障点（卡在哪一行代码），随后继续回到步骤 1 进行迭代修改，如此往复。
