#!/bin/bash
#
# 更新 Xcode 项目配置
# 添加 DMSAService target，移除旧的三个服务 targets
#

set -e

PROJECT_DIR="/Users/ttttt/Documents/xcodeProjects/DMSA/DMSAApp"
PROJECT_FILE="$PROJECT_DIR/DMSAApp.xcodeproj/project.pbxproj"
BACKUP_FILE="$PROJECT_FILE.backup.$(date +%Y%m%d%H%M%S)"

echo "=== DMSA 项目更新脚本 ==="
echo ""

# 备份项目文件
echo "1. 备份项目文件..."
cp "$PROJECT_FILE" "$BACKUP_FILE"
echo "   备份已创建: $BACKUP_FILE"

# 创建临时文件
TEMP_FILE=$(mktemp)

# 读取项目文件并添加 DMSAService 配置
echo ""
echo "2. 更新项目配置..."

cat "$PROJECT_FILE" > "$TEMP_FILE"

# 检查是否已经添加过 DMSAService
if grep -q "com.ttttt.dmsa.service" "$TEMP_FILE"; then
    echo "   DMSAService 已存在于项目中"
else
    echo "   需要手动在 Xcode 中添加 DMSAService target"
    echo ""
    echo "   请按照 XCODE_PROJECT_UPDATE_GUIDE.md 中的步骤操作"
fi

# 清理
rm -f "$TEMP_FILE"

echo ""
echo "=== 脚本完成 ==="
echo ""
echo "后续步骤:"
echo "1. 打开 Xcode 项目"
echo "2. 添加 DMSAService target (如果尚未添加)"
echo "3. 参考 XCODE_PROJECT_UPDATE_GUIDE.md 完成配置"
echo ""
echo "如需恢复，使用备份文件: $BACKUP_FILE"
