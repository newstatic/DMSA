#!/bin/bash
# Downloads Sync App 编译脚本

set -e

echo "=== 编译 Downloads Sync App ==="
echo ""

APP_NAME="DownloadsSyncApp"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

# 清理
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR"

# 编译 Swift 文件
echo "📦 编译中..."
swiftc -o "$MACOS_DIR/$APP_NAME" \
    -target arm64-apple-macos11 \
    -sdk $(xcrun --show-sdk-path) \
    -framework Cocoa \
    -framework Foundation \
    DownloadsSyncApp/main.swift \
    DownloadsSyncApp/AppDelegate.swift

# 复制 Info.plist
cp DownloadsSyncApp/Info.plist "$CONTENTS_DIR/"

echo ""
echo "✅ 编译完成: $APP_BUNDLE"
echo ""
echo "📋 安装步骤:"
echo "   1. 复制到 Applications: cp -r $APP_BUNDLE /Applications/"
echo "   2. 启动应用: open /Applications/$APP_NAME.app"
echo "   3. 设置开机启动: 系统偏好设置 → 用户与群组 → 登录项 → 添加"
echo ""
echo "🔧 或直接运行测试:"
echo "   ./$MACOS_DIR/$APP_NAME"
