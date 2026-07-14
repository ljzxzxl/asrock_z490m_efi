#!/bin/bash

# 1. 建立脚本存放目录
sudo mkdir -p /usr/local/bin

# 2. 写入智能挂载脚本
sudo bash -c 'cat > /usr/local/bin/mount_efi.sh << "SCRIPT"
#!/bin/bash
# 智能寻找当前启动盘的EFI分区并挂载
PHYSICAL_STORE=$(diskutil info / | grep "APFS Physical Store" | awk '\''{print $NF}'\'')
if [ -z "$PHYSICAL_STORE" ]; then
    PHYSICAL_STORE=$(diskutil info / | grep "Device Identifier" | awk '\''{print $NF}'\'')
fi
PHYSICAL_DISK=$(echo $PHYSICAL_STORE | grep -o '\''disk[0-9]*'\'')
EFI_NODE=$(diskutil list $PHYSICAL_DISK | grep EFI | awk '\''{print $NF}'\'' | head -n 1)

if [ -n "$EFI_NODE" ]; then
    mkdir -p /Volumes/EFI
    diskutil mount -mountPoint /Volumes/EFI /dev/$EFI_NODE
fi
SCRIPT'

# 3. 设置脚本执行权限
sudo chown root:wheel /usr/local/bin/mount_efi.sh
sudo chmod 755 /usr/local/bin/mount_efi.sh

# 4. 写入 LaunchDaemon 配置文件
sudo bash -c 'cat > /Library/LaunchDaemons/com.allen.mountefi.plist << "PLIST"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.allen.mountefi</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/mount_efi.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
PLIST'

# 5. 设置 plist 权限
sudo chown root:wheel /Library/LaunchDaemons/com.allen.mountefi.plist
sudo chmod 644 /Library/LaunchDaemons/com.allen.mountefi.plist

# 6. 注册并立即启动服务
sudo launchctl load -w /Library/LaunchDaemons/com.allen.mountefi.plist

echo ""
echo "✅ 安装完成！你的本机 EFI 分区以后将在开机时静默自动挂载！"
echo ""
