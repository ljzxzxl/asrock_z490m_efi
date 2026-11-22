#!/bin/bash
# 把仓库里的 EFI 同步到本机 ESP（部署工具）。
#
# ⚠️ 日常不需要运行：ESP 当前使用的就是本仓库的 config.plist，两边已一致。
# 只有以下情况才需要跑：
#   - 修改了 EFI/OC/config.plist 或 Kexts/ 之后，想把改动刷到 ESP；
#   - 走「可选进阶」恢复系统卷封印并把 csr 收紧为 0x803 之后。
# 本脚本不修改系统卷、不删除 ESP 上的既有文件，并会复用/新建整份 EFI 备份。

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
#    csr 允许 0xA03（未恢复封印的默认方案）或 0x803（恢复封印后的可选收紧）。
CSR="$(python3 - "$CONFIG" <<'PY'
import plistlib, sys
d = plistlib.load(open(sys.argv[1], 'rb'))
add = {k.get('BundlePath'): k.get('Enabled') for k in d['Kernel']['Add']}
assert add.get('SimpleBCM.kext') is True, 'SimpleBCM.kext 未启用'
for old in ('IOSkywalkFamily.kext', 'IO80211FamilyLegacy.kext',
            'IO80211FamilyLegacy.kext/Contents/PlugIns/AirPortBrcmNIC.kext'):
    assert add.get(old) is False, old + ' 仍在启用'
for b in d['Kernel']['Block']:
    if b.get('Identifier') == 'com.apple.iokit.IOSkywalkFamily':
        assert b.get('Enabled') is False, 'IOSkywalkFamily Block 仍启用'
nv = d['NVRAM']['Add']['7C436110-AB2A-4BBB-A880-FE41995C9F82']
csr = nv['csr-active-config'].hex()
assert csr in ('030a0000', '03080000'), 'csr-active-config 不是 0xA03 / 0x803: ' + csr
print(csr)
PY
)" || fail "config.plist 不是有效的 SimpleBCM 方案，拒绝同步"

case "$CSR" in
  030a0000) CSR_LABEL='0xA03（默认：不启用 authenticated-root，无需恢复封印）' ;;
  03080000) CSR_LABEL='0x803（可选进阶：启用 authenticated-root，要求封印已恢复）' ;;
esac
printf 'config.plist 校验通过: SimpleBCM 已启用 / 旧 OCLP 栈已禁用 / csr=%s\n\n' "$CSR_LABEL"

# 2. 只有 csr=0x803 才会启用 authenticated-root，此时才强制检查系统卷封印
SEALED="$(diskutil apfs list 2>/dev/null | grep -i 'Snapshot Sealed' || true)"
printf '系统卷封印状态:\n%s\n\n' "${SEALED:-  (未读到)}"
if [ "$CSR" = "03080000" ]; then
  if printf '%s' "$SEALED" | grep -qi 'Broken'; then
    fail "config 使用 csr=0x803（会启用 authenticated-root），但系统卷仍是 Snapshot Sealed: Broken，直接启动会进不了系统。请先恢复封印，或把 csr 改回 0xA03。"
  fi
  printf '%s' "$SEALED" | grep -qi 'Yes' || fail "未能确认 Snapshot Sealed: Yes，csr=0x803 需要封印已恢复。"
else
  printf '当前 csr=0xA03，不启用 authenticated-root；系统卷封印状态不影响启动，跳过强制检查。\n'
  printf '（系统里残留的 OCLP-Mod 用户态补丁由 AMFIPass 放行，本方案无需恢复封印。）\n\n'
fi

# 3. ocvalidate（存在则执行，缺失只提示）
if [ -x "$OCVALIDATE" ]; then
  "$OCVALIDATE" "$CONFIG" || fail "ocvalidate 未通过"
else
  printf '[warn] 未找到 ocvalidate，跳过 OpenCore 配置校验: %s\n' "$OCVALIDATE"
fi

# 4. ESP 检查与空间检查
[ -f "$ESP/OC/config.plist" ] || fail "ESP 上找不到 OC/config.plist。请先挂载 EFI 分区（Tools/Install-MountEFI.sh），或用 ESP_PATH 指定正确路径。"
[ -w "$ESP" ] || fail "ESP 不可写: $ESP"

# 优先复用 ESP 上已有的完整 EFI 备份，避免 ESP（通常仅 200MB）被多份备份占满。
# 需要为当前状态单独留快照时，设置 NEW_BACKUP=1；也可用 REUSE_BACKUP 指定某一份。
BACKUP="${REUSE_BACKUP:-}"
if [ -z "$BACKUP" ] && [ "${NEW_BACKUP:-0}" != "1" ]; then
  for candidate in $(ls -1dt "$(dirname "$ESP")"/EFI-Backup-* 2>/dev/null); do
    if [ -f "$candidate/OC/config.plist" ] && [ -f "$candidate/BOOT/BOOTx64.efi" ]; then
      BACKUP="$candidate"
      break
    fi
  done
fi
NEED_MB=0
if [ -n "$BACKUP" ]; then
  printf '复用已有 ESP 备份（不再新建）: %s\n' "$BACKUP"
else
  NEED_MB="$(du -sm "$ESP" | awk '{print $1}')"
  TS="$(date +%Y%m%d-%H%M%S)"
  BACKUP="$(dirname "$ESP")/EFI-Backup-$TS"
  printf '将新建备份: %s (约 %sMB)\n' "$BACKUP" "$NEED_MB"
fi

FREE_MB="$(df -m "$ESP" | tail -1 | awk '{print $4}')"
REQUIRED_MB=$((NEED_MB + 20))
[ "${FREE_MB:-0}" -ge "$REQUIRED_MB" ] || \
  fail "ESP 可用空间不足（当前 ${FREE_MB}MB，需要约 ${REQUIRED_MB}MB）。可清理 ESP 上的旧 opencore-*.txt 日志或旧 EFI-Backup 目录，或设置 REUSE_BACKUP=<已有备份目录>。"

# 5. 整份备份（cp -R 适配 FAT32；不新建时跳过）
if [ ! -f "$BACKUP/OC/config.plist" ]; then
  printf '备份现有 EFI -> %s\n' "$BACKUP"
  cp -R "$ESP" "$BACKUP"
fi
[ -f "$BACKUP/OC/config.plist" ] || fail "备份校验失败"

# 6. 同步（不使用 --delete，保留 ESP 上的 config 备份、日志与 .comate 文档）
printf '同步 BOOT/ 与 OC/ ...\n'
rsync -a "$REPO/EFI/BOOT/" "$ESP/BOOT/"
rsync -a "$REPO/EFI/OC/" "$ESP/OC/"

cmp -s "$CONFIG" "$ESP/OC/config.plist" || fail "同步后 config.plist 校验不一致，请用备份回滚: $BACKUP"
[ -f "$ESP/OC/Kexts/SimpleBCM.kext/Contents/MacOS/SimpleBCM" ] || fail "SimpleBCM.kext 未同步成功"

printf '\n== 部署完成 ==\n'
printf '备份目录: %s\n' "$BACKUP"
printf '下一步:\n'
if [ "$CSR" = "03080000" ]; then
  printf '  1. 在 OpenCore 启动菜单重置一次 NVRAM（让 csr=0x803 生效），然后重启\n'
  printf '  2. csrutil authenticated-root status -> enabled; diskutil apfs list -> Snapshot Sealed: Yes\n'
else
  printf '  1. csr=0xA03 与当前 NVRAM 一致，无需 Reset NVRAM；若改了其它配置，重启即生效\n'
  printf '  2. authenticated-root 仍为 disabled、封印仍为 Broken，属本方案预期状态\n'
fi
printf '  3. 验证: kmutil showloaded | grep -iE "simplebcm|skywalk|80211|brcm"\n'
printf '  4. 验证: system_profiler SPAirPortDataType / SPBluetoothDataType\n'
printf '  5. 实测 AirDrop/Handoff 双向、睡眠唤醒重连、RTL8125 与 I219V\n'
printf '如需回退: Tools/Rollback-SimpleBCM-EFI.sh %s\n' "$BACKUP"
