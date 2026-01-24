import Foundation

/// 文件树版本管理器 (App 端)
/// v4.3: 仅作为 XPC 客户端，实际逻辑在 DMSAService 中
actor TreeVersionManager {

    // MARK: - 单例

    static let shared = TreeVersionManager()

    // MARK: - 常量

    static let versionFileName = ".FUSE/db.json"

    // MARK: - 类型定义

    /// 版本检查结果
    struct VersionCheckResult: Sendable {
        var externalConnected: Bool = false
        var needRebuildLocal: Bool = false
        var needRebuildExternal: Bool = false

        var needsAnyRebuild: Bool {
            return needRebuildLocal || needRebuildExternal
        }
    }

    // MARK: - 依赖

    private let serviceClient: ServiceClient

    // MARK: - 初始化

    private init(serviceClient: ServiceClient = .shared) {
        self.serviceClient = serviceClient
    }

    // MARK: - 公开接口

    /// 启动时版本检查 (通过 XPC 调用 Service)
    func checkVersionsOnStartup(for syncPair: SyncPairConfig) async -> VersionCheckResult {
        do {
            let result = try await serviceClient.checkTreeVersions(
                localDir: syncPair.localDir,
                externalDir: syncPair.externalDir,
                syncPairId: syncPair.id
            )
            return result
        } catch {
            Logger.shared.error("TreeVersionManager: 版本检查失败: \(error)")
            // 返回需要重建的结果
            return VersionCheckResult(
                externalConnected: false,
                needRebuildLocal: true,
                needRebuildExternal: false
            )
        }
    }

    /// 执行文件树重建 (通过 XPC 调用 Service)
    func rebuildTree(for syncPair: SyncPairConfig, source: TreeSource) async throws {
        Logger.shared.info("TreeVersionManager: 开始重建文件树 - \(source)")

        let rootPath: String
        let sourceString: String

        switch source {
        case .local:
            rootPath = syncPair.localDir
            sourceString = "local"
        case .external:
            rootPath = syncPair.externalDir
            sourceString = "external"
        }

        try await serviceClient.rebuildTree(
            rootPath: rootPath,
            syncPairId: syncPair.id,
            source: sourceString
        )

        Logger.shared.info("TreeVersionManager: 文件树重建完成 - \(source)")
    }

    /// 获取当前版本
    func getCurrentVersion(for syncPair: SyncPairConfig, source: TreeSource) async -> String? {
        let sourceString = source == .local ? "local" : "external"
        return try? await serviceClient.getTreeVersion(syncPairId: syncPair.id, source: sourceString)
    }

    /// 更新单个文件的版本信息 (使版本失效)
    func updateFileVersion(_ virtualPath: String, in syncPair: SyncPairConfig) async {
        _ = try? await serviceClient.invalidateTreeVersion(syncPairId: syncPair.id, source: "local")
        Logger.shared.debug("TreeVersionManager: 版本失效 - \(virtualPath)")
    }
}

// MARK: - 树数据源

enum TreeSource: Sendable {
    case local
    case external
}

// MARK: - 错误类型

enum TreeVersionError: Error, LocalizedError {
    case scanFailed(String)
    case writeFailed(String)
    case invalidFormat(String)
    case versionMismatch(expected: String, actual: String)
    case serviceFailed(String)

    var errorDescription: String? {
        switch self {
        case .scanFailed(let path):
            return "目录扫描失败: \(path)"
        case .writeFailed(let path):
            return "版本文件写入失败: \(path)"
        case .invalidFormat(let path):
            return "版本文件格式无效: \(path)"
        case .versionMismatch(let expected, let actual):
            return "版本不匹配: 期望 \(expected), 实际 \(actual)"
        case .serviceFailed(let message):
            return "服务调用失败: \(message)"
        }
    }
}
