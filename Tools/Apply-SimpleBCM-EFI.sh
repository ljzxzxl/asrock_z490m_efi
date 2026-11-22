#!/bin/bash
# 把 feature/simplebcm 分支的 EFI 同步到本机 ESP。
# 前置条件：已完成 OCLP-Mod 的 Revert Root Patches，系统卷封印恢复为 Yes。
# 本脚本不会修改系统卷，不会删除 ESP 上的既有文件，并会先做整份 EFI 备份。

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ESP="${ESP_PATH:-/Volumes/EFI/EFI}"
OCVALIDATE="${OCVALIDATE_PATH:-/Users/allen/Downloads/OCLP-Mod-main/payloads/OpenCore/ocvalidate}"
CONFIG="$REPO/EFI/OC/config.plist"

fail() { printf '\n[ABORT] %s\n\n' "$1" >&2; exit 1; }

printf '== SimpleBCM EFI 部署 ==\n'
printf '仓库: %s\n目标 ESP: %s\n' "$REPO" "$ESP"
printf 'git 分支: %s\n\n' "$(git -C "$REPO" branch --show-current)"

[ -f "$CONFIG" ] || fail "找不到 $CONFIG"
command -v rsync >/dev/null || fail "系统缺少 rsync"

# 1. 确认这份 config 确实是 SimpleBCM 方案，避免误同步旧配置
python3 - "$CONFIG" <<'PY' || fail "config.plist 不是 SimpleBCM 方案，拒绝同步"
import plistlib, sys
d = plistlib.load(open(sys.argv[1], 'rb'))
add = {k.get('BundlePath'): k.get('Enabled') for k in d['Kernel']['Add']}
assert add.get('SimpleBCM.kext') is True, 'SimpleBCM.kext 未启用'
for old in ('IOSkywalkFamily.kext', 'IO80211FamilyLegacy.kext',
            'IO80211FamilyLegacy.kext/Contents/PlugIns/AirPortBrcmNIC.kext',
            'AMFIPass.kext'):
    assert add.get(old) is False, old + ' 仍在启用'
for b in d['Kernel']['Block']:
    if b.get('Identifier') == 'com.apple.iokit.IOSkywalkFamily':
        assert b.get('Enabled') is False, 'IOSkywalkFamily Block 仍启用'
nv = d['NVRAM']['Add']['7C436110-AB2A-4BBB-A880-FE41995C9F82']
assert nv['csr-active-config'] == bytes.fromhex('03080000'), 'csr-active-config 不是 0x803'
print('config.plist 校验通过: SimpleBCM 已启用 / 旧 OCLP 栈已禁用 / csr=0x803')
PY

# 2. 关键前置检查：系统卷封印必须已经恢复
SEALED="$(diskutil apfs list 2>/dev/null | grep -i 'Snapshot Sealed' || true)"
printf '系统卷封印状态:\n%s\n\n' "${SEALED:-  (未读到)}"
if printf '%s' "$SEALED" | grep -qi 'Broken'; then
  fail "系统卷仍是 Snapshot Sealed: Broken。请先用 OCLP-Mod -> Post Install Root Patch -> Revert Root Patches（或原地重装 macOS 15.8.2）恢复封印并重启，再运行本脚本。直接用本 EFI 启动会导致无法进入系统。"
fi
printf '%s' "$SEALED" | grep -qi 'Yes' || fail "未能确认 Snapshot Sealed: Yes，请先完成 revert 再运行。"
printf '提示: csrutil authenticated-root status 此刻仍可能显示 disabled，属于正常现象；换用本 EFI 重启后才会变为 enabled。\n\n'

# 3. ocvalidate（存在则执行，缺失只提示）
if [ -x "$OCVALIDATE" ]; then
  "$OCVALIDATE" "$CONFIG" || fail "ocvalidate 未通过"
else
  printf '[warn] 未找到 ocvalidate，跳过 OpenCore 配置校验: %s\n' "$OCVALIDATE"
fi

# 4. ESP 检查与空间检查
[ -f "$ESP/OC/config.plist" ] || fail "ESP 上找不到 OC/config.plist。请先挂载 EFI 分区（Tools/Install-MountEFI.sh），或用 ESP_PATH 指定正确路径。"
[ -w "$ESP" ] || fail "ESP 不可写: $ESP"
FREE_MB="$(df -m "$ESP" | tail -1 | awk '{print $4}')"
[ "${FREE_MB:-0}" -ge 120 ] || fail "ESP 可用空间不足 120MB（当前 ${FREE_MB}MB），无法安全备份。"

# 5. 整份备份
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP="$(dirname "$ESP")/EFI-Backup-$TS"
printf '备份现有 EFI -> %s\n' "$BACKUP"
cp -a "$ESP" "$BACKUP"
[ -f "$BACKUP/OC/config.plist" ] || fail "备份校验失败"

# 6. 同步（不使用 --delete，保留 ESP 上的 config 备份、日志与 .comate 文档）
printf '同步 BOOT/ 与 OC/ ...\n'
rsync -a "$REPO/EFI/BOOT/" "$ESP/BOOT/"
rsync -a "$REPO/EFI/OC/" "$ESP/OC/"

cmp -s "$CONFIG" "$ESP/OC/config.plist" || fail "同步后 config.plist 校验不一致，请用备份回滚: $BACKUP"
[ -f "$ESP/OC/Kexts/SimpleBCM.kext/Contents/MacOS/SimpleBCM" ] || fail "SimpleBCM.kext 未同步成功"

printf '\n== 部署完成 ==\n'
printf '备份目录: %s\n' "$BACKUP"
printf '下一步（需人工执行）:\n'
printf '  1. 在 OpenCore 启动菜单重置一次 NVRAM（让 csr=0x803 与 boot-args 生效），然后重启进 macOS\n'
printf '  2. 验证: kmutil showloaded | grep -iE "simplebcm|skywalk|80211|brcm"\n'
printf '  3. 验证: system_profiler SPAirPortDataType / SPBluetoothDataType\n'
printf '  4. 验证: csrutil authenticated-root status -> enabled; diskutil apfs list -> Snapshot Sealed: Yes\n'
printf '  5. 实测 AirDrop/Handoff 双向、睡眠唤醒重连、RTL8125 与 I219V\n'
printf '如需回退: Tools/Rollback-SimpleBCM-EFI.sh %s\n' "$BACKUP"
