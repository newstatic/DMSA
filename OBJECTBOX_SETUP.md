# ObjectBox Swift 集成说明

本文档说明如何为 DMSA 项目添加 ObjectBox 数据库支持。

## 步骤 1: 在 Xcode 中添加 Swift Package 依赖

1. 打开 Xcode 项目 `DMSAApp.xcodeproj`
2. 选择项目 (Project Navigator 顶部的蓝色图标)
3. 选择 `Package Dependencies` 标签页
4. 点击 `+` 按钮添加包
5. 在搜索框输入: `https://github.com/objectbox/objectbox-swift-spm`
6. 选择版本规则: `Up to Next Major Version` 从 `5.1.0` 开始
7. 点击 `Add Package`
8. 在目标选择中，为 `com.ttttt.dmsa.service` 添加 `ObjectBox.xcframework`

## 步骤 2: 运行 ObjectBox 代码生成器

ObjectBox 需要运行代码生成器来创建模型绑定代码。

### 方法 A: 通过 Xcode (推荐)

1. 在 Project Navigator 中右键点击项目
2. 选择 `ObjectBoxGeneratorCommand`
3. 选择 target: `com.ttttt.dmsa.service`
4. 运行生成器

### 方法 B: 通过命令行

```bash
cd /Users/ttttt/Documents/xcodeProjects/DMSA/DMSAApp
swift package plugin --allow-writing-to-package-directory --allow-network-connections all objectbox-generator --target com.ttttt.dmsa.service
```

## 步骤 3: 添加生成的文件到项目

代码生成器会创建以下文件:
- `EntityInfo.generated.swift` - 实体元数据
- `ObjectBox.generated.swift` - Store 初始化代码

确保这些文件被添加到 `com.ttttt.dmsa.service` target 的编译源文件中。

## 实体定义说明

实体类已在 `ServiceDatabaseManager.swift` 中定义，使用 `// objectbox: entity` 注释标记:

```swift
// objectbox: entity
public class ServiceFileEntry: Entity, Identifiable {
    public var id: Id = 0
    // objectbox: index
    public var syncPairId: String = ""
    // ... 其他属性
}
```

### 重要注释:
- `// objectbox: entity` - 标记类为 ObjectBox 实体
- `// objectbox: index` - 为属性创建索引 (加速查询)
- `public var id: Id = 0` - 必需的 ID 属性

## 数据库位置

ObjectBox 数据库存储在:
```
/Library/Application Support/DMSA/ServiceData/objectbox/
```

## 数据迁移

首次运行时，如果检测到旧的 JSON 文件 (`file_entries.json`, `sync_history.json`, `sync_statistics.json`)，
系统会自动将数据迁移到 ObjectBox，并将旧文件重命名为 `.json.bak`。

## 故障排除

### 编译错误: "No such module 'ObjectBox'"
- 确保已正确添加 SPM 包依赖
- 尝试: Product → Clean Build Folder (Shift+Cmd+K)
- 重新打开 Xcode 项目

### 运行时错误: "Store initialization failed"
- 检查数据目录权限
- 确保 Service 以 root 权限运行

### 查询错误: "Property not found"
- 重新运行 ObjectBox 代码生成器
- 确保生成的文件在编译目标中

## 参考文档

- [ObjectBox Swift 官方文档](https://swift.objectbox.io/)
- [ObjectBox Swift GitHub](https://github.com/objectbox/objectbox-swift)
