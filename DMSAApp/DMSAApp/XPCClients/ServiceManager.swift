import Foundation

/// 服务状态
public struct ServiceStatus {
    public let vfs: ServiceComponentStatus
    public let sync: ServiceComponentStatus
    public let helper: ServiceComponentStatus

    public var allHealthy: Bool {
        return vfs.isHealthy && sync.isHealthy && helper.isHealthy
    }

    public var allAvailable: Bool {
        return vfs.isAvailable && sync.isAvailable && helper.isAvailable
    }
}

/// 单个服务组件状态
public struct ServiceComponentStatus {
    public let name: String
    public let isAvailable: Bool
    public let isHealthy: Bool
    public let version: String?
    public let message: String?
}

/// 服务管理器
/// 统一管理所有 XPC 服务的连接和状态
public final class ServiceManager: ObservableObject {
    public static let shared = ServiceManager()

    private let logger = Logger.shared

    @Published public var status: ServiceStatus?
    @Published public var isCheckingServices = false

    private var healthCheckTimer: Timer?

    private init() {}

    // MARK: - 服务检查

    /// 检查所有服务状态
    public func checkAllServices() async -> ServiceStatus {
        isCheckingServices = true
        defer { isCheckingServices = false }

        async let vfsStatus = checkVFSService()
        async let syncStatus = checkSyncService()
        async let helperStatus = checkHelperService()

        let status = ServiceStatus(
            vfs: await vfsStatus,
            sync: await syncStatus,
            helper: await helperStatus
        )

        await MainActor.run {
            self.status = status
        }

        return status
    }

    private func checkVFSService() async -> ServiceComponentStatus {
        let isAvailable = await VFSClient.shared.isAvailable()
        let version = await VFSClient.shared.getVersion()
        let (isHealthy, message) = await VFSClient.shared.healthCheck()

        return ServiceComponentStatus(
            name: "VFS Service",
            isAvailable: isAvailable,
            isHealthy: isHealthy,
            version: version,
            message: message
        )
    }

    private func checkSyncService() async -> ServiceComponentStatus {
        let isAvailable = await SyncClient.shared.isAvailable()
        let version = await SyncClient.shared.getVersion()
        let (isHealthy, message) = await SyncClient.shared.healthCheck()

        return ServiceComponentStatus(
            name: "Sync Service",
            isAvailable: isAvailable,
            isHealthy: isHealthy,
            version: version,
            message: message
        )
    }

    private func checkHelperService() async -> ServiceComponentStatus {
        let isAvailable = await HelperClient.shared.isAvailable()
        let version = await HelperClient.shared.getVersion()
        let (isHealthy, message) = await HelperClient.shared.healthCheck()

        return ServiceComponentStatus(
            name: "Helper Service",
            isAvailable: isAvailable,
            isHealthy: isHealthy,
            version: version,
            message: message
        )
    }

    // MARK: - 定时健康检查

    /// 启动定时健康检查
    public func startHealthCheck(interval: TimeInterval = 60) {
        stopHealthCheck()

        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task {
                _ = await self?.checkAllServices()
            }
        }

        // 立即执行一次
        Task {
            _ = await checkAllServices()
        }
    }

    /// 停止定时健康检查
    public func stopHealthCheck() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
    }

    // MARK: - 服务安装

    /// 检查服务是否已安装
    public func areServicesInstalled() -> Bool {
        return HelperClient.shared.isInstalled()
    }

    /// 安装服务
    public func installServices() async throws {
        try await HelperClient.shared.installServices()
        logger.info("所有服务安装成功")

        // 等待服务启动
        try await Task.sleep(nanoseconds: 2_000_000_000)  // 2 秒

        // 检查服务状态
        _ = await checkAllServices()
    }

    // MARK: - 服务生命周期

    /// 准备关闭所有服务
    public func prepareForShutdown() async {
        logger.info("准备关闭所有服务...")

        async let vfsResult = VFSClient.shared.prepareForShutdown()
        async let syncResult = SyncClient.shared.prepareForShutdown()

        let results = await (vfsResult, syncResult)

        logger.info("服务关闭完成: VFS=\(results.0), Sync=\(results.1)")
    }

    /// 重新加载所有服务配置
    public func reloadAllConfigs() async throws {
        try await VFSClient.shared.reloadConfig()
        try await SyncClient.shared.reloadConfig()
        logger.info("所有服务配置已重新加载")
    }

    // MARK: - 断开连接

    /// 断开所有服务连接
    public func disconnectAll() {
        VFSClient.shared.disconnect()
        SyncClient.shared.disconnect()
        HelperClient.shared.disconnect()
        logger.info("已断开所有服务连接")
    }
}
