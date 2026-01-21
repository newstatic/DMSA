#!/bin/bash

# DMSA App Bundle Builder
# 将 SPM 项目打包成 macOS .app bundle

set -e

# 配置
APP_NAME="DMSA"
BUNDLE_ID="com.ttttt.dmsa"
VERSION="2.0"
BUILD_NUMBER="1"
MIN_MACOS="13.0"

# 路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/.build"
RELEASE_DIR="${BUILD_DIR}/release"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "=========================================="
echo "Building ${APP_NAME}.app"
echo "=========================================="

# 1. 编译 Release 版本
echo "Step 1: Building release binary..."
cd "${SCRIPT_DIR}"
swift build -c release

# 2. 创建 app bundle 结构
echo "Step 2: Creating app bundle structure..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# 3. 复制可执行文件
echo "Step 3: Copying executable..."
cp "${RELEASE_DIR}/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"

# 4. 复制资源文件 (lproj 本地化文件)
echo "Step 4: Copying resources..."
if [ -d "${RELEASE_DIR}/DMSA_DMSA.bundle" ]; then
    cp -R "${RELEASE_DIR}/DMSA_DMSA.bundle/"* "${RESOURCES_DIR}/"
fi

# 复制 entitlements 如果存在
if [ -f "${SCRIPT_DIR}/Sources/DMSA/Resources/DMSA.entitlements" ]; then
    cp "${SCRIPT_DIR}/Sources/DMSA/Resources/DMSA.entitlements" "${CONTENTS_DIR}/"
fi

# 5. 创建 Info.plist
echo "Step 5: Creating Info.plist..."
cat > "${CONTENTS_DIR}/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>Delt MACOS Sync App</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS}</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026. All rights reserved.</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

# 6. 创建 PkgInfo
echo "Step 6: Creating PkgInfo..."
echo -n "APPL????" > "${CONTENTS_DIR}/PkgInfo"

# 7. 设置权限
echo "Step 7: Setting permissions..."
chmod +x "${MACOS_DIR}/${APP_NAME}"

# 8. 完成
echo "=========================================="
echo "Build complete!"
echo "App bundle: ${APP_BUNDLE}"
echo "=========================================="

# 询问是否打开
echo ""
echo "Commands:"
echo "  Open app:     open \"${APP_BUNDLE}\""
echo "  Copy to Apps: cp -R \"${APP_BUNDLE}\" /Applications/"
echo ""

# 可选：直接打开
read -p "Open the app now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    open "${APP_BUNDLE}"
fi
