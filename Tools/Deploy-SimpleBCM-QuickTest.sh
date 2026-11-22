#!/bin/bash
# SimpleBCM 快速验证部署（非最终方案）
#
# 用途：系统卷封印尚未恢复（Snapshot Sealed: Broken）时，先用一个临时 config 把
#       SimpleBCM 部署到 ESP，以便重启后立刻验证无线是否可用。
# 与正式版 config 的唯一两点差异：
#   1) csr-active-config 保留 0xA03（不启用 authenticated-root，封印破损也能启动）
#   2) AMFIPass.kext 保持启用（残留的 OCLP-Mod 用户态 framework 补丁仍依赖 AMFI 放行）
# 其余与 EFI/OC/config.plist 完全一致；仓库里的正式版 config 不会被改写。
#
# 验证通过后仍需：OCLP-Mod -> Revert Root Patches -> 封印 Yes -> Tools/Apply-SimpleBCM-EFI.sh
# 脚本幂等，可重复执行；默认复用 ESP 上最新一份 EFI-Backup-*，避免重复占用空间。

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ESP="${ESP_PATH:-/Volumes/EFI/EFI}"
CONFIG="$REPO/EFI/OC/config.plist"
QUICK="${TMPDIR:-/tmp}/simplebcm-quicktest-config.plist"
OCVALIDATE="${OCVALIDATE_PATH:-/Users/allen/Downloads/OCLP-Mod-main/payloads/OpenCore/ocvalidate}"

fail() { printf '\n[ABORT] %s\n\n' "$1" >&2; exit 1; }

printf '== SimpleBCM 快速验证部署（不动系统卷 / 不收紧 csr） ==\n'
printf '仓库: %s\n目标 ESP: %s\n\n' "$REPO" "$ESP"

# 1. 由正式版 config 派生临时 config
python3 - "$CONFIG" "$QUICK" <<'PY' || fail '临时 config 生成失败'
import plistlib, sys
src, dst = sys.argv[1], sys.argv[2]
d = plistlib.load(open(src, 'rb'))
nv = d['NVRAM']['Add']['7C436110-AB2A-4BBB-A880-FE41995C9F82']
assert nv['csr-active-config'] == bytes.fromhex('03080000'), '源 config 不是 csr=0x803 的正式版'
add = {k.get('BundlePath'): k.get('Enabled') for k in d['Kernel']['Add']}
assert add.get('SimpleBCM.kext') is True, '源 config 未启用 SimpleBCM'
assert add.get('AMFIPass.kext') is False, '源 config 仍启用 AMFIPass'
nv['csr-active-config'] = bytes.fromhex('030a0000')
for k in d['Kernel']['Add']:
    if k.get('BundlePath') == 'AMFIPass.kext':
        k['Enabled'] = True
plistlib.dump(d, open(dst, 'wb'))
print('生成临时 config: csr=0xA03 / AMFIPass 启用（其余同正式版）')
PY

plutil -lint "$QUICK" >/dev/null || fail '临时 config plutil -lint 未通过'
if [ -x "$OCVALIDATE" ]; then
  "$OCVALIDATE" "$QUICK" || fail '临时 config ocvalidate 未通过'
fi
python3 - "$QUICK" <<'PY' || fail '临时 config 结构断言未通过'
import plistlib, sys
d = plistlib.load(open(sys.argv[1], 'rb'))
add = {k.get('BundlePath'): k.get('Enabled') for k in d['Kernel']['Add']}
assert add.get('SimpleBCM.kext') is True
assert add.get('AMFIPass.kext') is True
for old in ('IOSkywalkFamily.kext', 'IO80211FamilyLegacy.kext',
            'IO80211FamilyLegacy.kext/Contents/PlugIns/AirPortBrcmNIC.kext'):
    assert add.get(old) is False, old + ' 仍启用'
for keep in ('Lilu.kext', 'AirportBrcmFixup.kext',
             'AirportBrcmFixup.kext/Contents/PlugIns/AirPortBrcmNIC_Injector.kext',
             'BlueToolFixup.kext', 'BrcmFirmwareData.kext', 'BrcmPatchRAM3.kext'):
    assert add.get(keep) is True, keep + ' 应保持启用'
for b in d['Kernel']['Block']:
    if b.get('Identifier') == 'com.apple.iokit.IOSkywalkFamily':
        assert b.get('Enabled') is False, 'Skywalk Block 仍启用'
nv = d['NVRAM']['Add']['7C436110-AB2A-4BBB-A880-FE41995C9F82']
assert nv['csr-active-config'] == bytes.fromhex('030a0000')
print('结构断言通过')
PY

# 2. ESP 前置检查
[ -f "$ESP/OC/config.plist" ] || fail 'ESP 上找不到 OC/config.plist（先挂载 EFI 分区）'
[ -w "$ESP" ] || fail 'ESP 不可写'
command -v rsync >/dev/null || fail '系统缺少 rsync'

# 3. 备份：默认复用最新一份 EFI-Backup-*（必须是旧 OCLP 配置），否则新建
BACKUP="${REUSE_BACKUP:-}"
if [ -z "$BACKUP" ]; then
  BACKUP="$(ls -1dt "$(dirname "$ESP")"/EFI-Backup-* 2>/dev/null | head -1 || true)"
  if [ -n "$BACKUP" ]; then printf '复用已有备份: %s\n' "$BACKUP"; fi
fi
NEED_BACKUP_MB=0
if [ -z "$BACKUP" ]; then
  ESP_MB="$(du -sm "$ESP" | awk '{print $1}')"
  NEED_BACKUP_MB="$ESP_MB"
  TS="$(date +%Y%m%d-%H%M%S)"
  BACKUP="$(dirname "$ESP")/EFI-Backup-$TS"
  printf '将新建备份: %s (约 %sMB)\n' "$BACKUP" "$ESP_MB"
fi

FREE_MB="$(df -m "$ESP" | tail -1 | awk '{print $4}')"
REQUIRED_MB=$((NEED_BACKUP_MB + 20))
[ "${FREE_MB:-0}" -ge "$REQUIRED_MB" ] || \
  fail "ESP 可用空间不足（当前 ${FREE_MB}MB，需要约 ${REQUIRED_MB}MB）"

if [ ! -f "$BACKUP/OC/config.plist" ]; then
  printf '备份现有 EFI -> %s\n' "$BACKUP"
  cp -R "$ESP" "$BACKUP"
fi
[ -f "$BACKUP/OC/config.plist" ] || fail '备份不完整'
[ -f "$BACKUP/BOOT/BOOTx64.efi" ] || fail '备份不完整（缺 BOOTx64.efi）'

# 4. 同步（不带 --delete，保留 ESP 上的 config 备份、日志与 .comate 文档）
find "$ESP/OC" -maxdepth 1 -name '.config.plist.*' -type f -delete 2>/dev/null || true
printf '同步 BOOT/ 与 OC/ ...\n'
rsync -a "$REPO/EFI/BOOT/" "$ESP/BOOT/"
rsync -a "$REPO/EFI/OC/"  "$ESP/OC/"
cp "$QUICK" "$ESP/OC/config.plist"

# 5. 部署后校验
cmp -s "$QUICK" "$ESP/OC/config.plist" || fail "ESP config 不一致，请回退: $BACKUP"
plutil -lint "$ESP/OC/config.plist" >/dev/null || fail 'ESP config 语法错误'
if [ -x "$OCVALIDATE" ]; then
  "$OCVALIDATE" "$ESP/OC/config.plist" || fail 'ESP config ocvalidate 未通过'
fi
python3 - "$REPO" "$ESP" <<'PY' || fail 'kext / 结构校验失败'
import hashlib, json, os, plistlib, sys
repo, esp = sys.argv[1], sys.argv[2]
d = plistlib.load(open(os.path.join(esp, 'OC/config.plist'), 'rb'))
add = {k.get('BundlePath'): k.get('Enabled') for k in d['Kernel']['Add']}
assert add.get('SimpleBCM.kext') is True
assert add.get('AMFIPass.kext') is True
assert add.get('IOSkywalkFamily.kext') is False
assert d['NVRAM']['Add']['7C436110-AB2A-4BBB-A880-FE41995C9F82']['csr-active-config'] == bytes.fromhex('030a0000')
exe = os.path.join(esp, 'OC/Kexts/SimpleBCM.kext/Contents/MacOS/SimpleBCM')
assert os.path.isfile(exe) and os.access(exe, os.X_OK), 'SimpleBCM.kext 缺失或不可执行'
m = json.load(open(os.path.join(repo, 'Docs/SimpleBCM/manifest.json')))
for f, h in m['files'].items():
    if f.startswith('EFI/'):
        p = os.path.join(esp, 'OC/Kexts', f.split('Kexts/', 1)[1])
        assert hashlib.sha256(open(p, 'rb').read()).hexdigest() == h, 'hash 不符: ' + p
print('ESP config 与 SimpleBCM.kext 校验通过')
PY

printf '\n== 部署完成（快速验证版） ==\n'
printf 'ESP config md5 : %s\n' "$(md5 -q "$ESP/OC/config.plist")"
printf '备份（回退用） : %s\n' "$BACKUP"
printf '临时 config    : %s\n' "$QUICK"
printf 'ESP 剩余空间   : %sMB\n' "$(df -m "$ESP" | tail -1 | awk '{print $4}')"
printf '\n本次不改系统卷、不启用 authenticated-root；当前 NVRAM csr=0xA03 与本 config 一致，\n'
printf '直接重启即可，无需 Reset NVRAM。\n'
printf '回退: %s/Tools/Rollback-SimpleBCM-EFI.sh %s\n' "$REPO" "$BACKUP"
