#!/usr/bin/env bash

clear
echo "=========================================================="
echo "      Pulsar - macOS 安全隔离属性自动修复工具"
echo "=========================================================="
echo ""
echo "正在检测「应用程序」目录中的 Pulsar.app..."

TARGET="/Applications/Pulsar.app"

if [ ! -d "$TARGET" ]; then
    echo "⚠️  未在 /Applications 目录下找到 Pulsar.app！"
    echo "💡 请先将本安装窗口中的 Pulsar.app 拖入 Applications 快捷方式中完成安装。"
    echo ""
    read -p "按回车键退出..."
    exit 0
fi

echo "🔍 找到 $TARGET，正在移除 Gatekeeper 下载隔离属性..."

# 兼容各种版本的 xattr 命令格式 (不依赖 -r 选项)
xattr -d com.apple.quarantine "$TARGET" 2>/dev/null || true
xattr -c "$TARGET" 2>/dev/null || true
find "$TARGET" -exec xattr -c {} + 2>/dev/null || true

echo "✅ 安全隔离属性已清除！"
echo "🚀 正在启动 Pulsar..."
open "$TARGET"

echo ""
echo "----------------------------------------------------------"
echo "💡 温馨提示："
echo "若系统仍弹出拦截，可前往 macOS「系统设置」->「隐私与安全性」，"
echo "在页面最下方点击「仍要打开」即可正常使用。"
echo "----------------------------------------------------------"
echo ""
sleep 2
