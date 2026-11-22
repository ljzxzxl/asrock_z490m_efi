#!/bin/bash
# 从 Apply-SimpleBCM-EFI.sh 生成的备份恢复到 OCLP-Mod 方案的 EFI。
# 注意：恢复 EFI 之后，系统侧还需要重新打 OCLP-Mod 网卡 root patch，WiFi 才会工作。

set -euo pipefail

ESP="${ESP_PATH:-/Volumes/EFI/EFI}"
BACKUP="${1:-}"

fail() { printf '\n[ABORT] %s\n\n' "$1" >&2; exit 1; }

if [ -z "$BACKUP" ]; then
  BACKUP="$(ls -1dt "$(dirname "$ESP")"/EFI-Backup-* 2>/dev/null | head -1 || true)"
  [ -n "$BACKUP" ] || fail "未指定备份目录，且在 ESP 上找不到 EFI-Backup-*。用法: $0 /Volumes/EFI/EFI-Backup-<时间戳>"
  printf '未指定备份，自动选用最新一份: %s\n' "$BACKUP"
fi

[ -f "$BACKUP/OC/config.plist" ] || fail "备份不完整: $BACKUP/OC/config.plist 不存在"
[ -d "$BACKUP/BOOT" ] || fail "备份不完整: $BACKUP/BOOT 不存在"
[ -w "$ESP" ] || fail "ESP 不可写: $ESP"
command -v rsync >/dev/null || fail "系统缺少 rsync"

# 确认备份确实是旧的 OCLP-Mod 配置
python3 - "$BACKUP/OC/config.plist" <<'PY' || fail "该备份不是 OCLP-Mod 方案配置，拒绝恢复"
import plistlib, sys
d = plistlib.load(open(sys.argv[1], 'rb'))
add = {k.get('BundlePath'): k.get('Enabled') for k in d['Kernel']['Add']}
assert add.get('IOSkywalkFamily.kext') is True, '备份中 IOSkywalkFamily.kext 未启用'
assert not add.get('SimpleBCM.kext'), '备份里已有 SimpleBCM 条目，可能选错备份'
print('备份校验通过: OCLP-Mod 旧方案配置')
PY

printf '恢复 BOOT/ 与 OC/ <- %s\n' "$BACKUP"
rsync -a "$BACKUP/BOOT/" "$ESP/BOOT/"
rsync -a "$BACKUP/OC/" "$ESP/OC/"

cmp -s "$BACKUP/OC/config.plist" "$ESP/OC/config.plist" || fail "恢复后 config.plist 校验不一致"

printf '\n== EFI 已回退 ==\n'
printf '  1. SimpleBCM.kext 文件可能仍留在 ESP/OC/Kexts 下，但旧 config 不会加载它，可稍后手动清理\n'
printf '  2. 重置 NVRAM 后重启；此时 csr-active-config 回到 0xA03\n'
printf '  3. 重要: 若系统卷曾做过 revert，需重新用 OCLP-Mod 打「网卡: BCM无线网卡」root patch，\n'
printf '     否则无线不可用并会复现 4 分半 PXSX 黑屏停摆\n'
printf '  4. 或停留在 feature/simplebcm 分支，重新运行 Apply-SimpleBCM-EFI.sh 回到新方案\n'
