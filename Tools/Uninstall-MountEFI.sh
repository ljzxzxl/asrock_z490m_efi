#!/bin/bash

echo "正在卸载开机自动挂载 EFI 服务..."

# 1. 停止并移除服务
sudo launchctl unload -w /Library/LaunchDaemons/com.allen.mountefi.plist 2>/dev/null

# 2. 删除配置文件
sudo rm -f /Library/LaunchDaemons/com.allen.mountefi.plist

# 3. 删除挂载脚本
sudo rm -f /usr/local/bin/mount_efi.sh

echo ""
echo "🗑️ 卸载完成！系统已恢复原样。"
echo ""
