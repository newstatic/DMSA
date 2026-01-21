import Foundation

/// rsync 同步结果
struct RsyncResult {
    let success: Bool
    let output: String
    let exitCode: Int32
    let filesTransferred: Int
    let bytesTransferred: Int64
    let errorMessage: String?
    let startTime: Date
    let endTime: Date

    var duration: TimeInterval {
        return endTime.timeIntervalSince(startTime)
    }
}

/// rsync 同步选项
struct RsyncOptions {
    var archive: Bool = true           // -a (归档模式)
    var verbose: Bool = true           // -v (详细输出)
    var delete: Bool = true            // --delete (删除目标端多余文件)
    var checksum: Bool = false         // --checksum (使用校验和比较)
    var dryRun: Bool = false           // -n (模拟运行)
    var progress: Bool = true          // --progress (显示进度)
    var partial: Bool = true           // --partial (保留部分传输的文件)
    var partialDir: String? = nil      // --partial-dir (部分文件存储目录)
    var compress: Bool = false         // -z (压缩传输)
    var humanReadable: Bool = true     // -h (人类可读格式)
    var stats: Bool = true             // --stats (显示统计信息)
    var excludePatterns: [String] = []
    var includePatterns: [String] = []
    var timeout: Int = 300             // 超时时间(秒)

    /// 转换为命令行参数
    func toArguments() -> [String] {
        var args: [String] = []

        if archive { args.append("-a") }
        if verbose { args.append("-v") }
        if delete { args.append("--delete") }
        if checksum { args.append("--checksum") }
        if dryRun { args.append("-n") }
        if progress { args.append("--progress") }
        if partial { args.append("--partial") }
        if let partialDir = partialDir { args.append("--partial-dir=\(partialDir)") }
        if compress { args.append("-z") }
        if humanReadable { args.append("-h") }
        if stats { args.append("--stats") }

        args.append("--timeout=\(timeout)")

        for pattern in excludePatterns {
            args.append("--exclude=\(pattern)")
        }

        for pattern in includePatterns {
            args.append("--include=\(pattern)")
        }

        return args
    }
}

/// rsync 封装器
final class RsyncWrapper {

    static let shared = RsyncWrapper()

    private let rsyncPath = "/usr/bin/rsync"
    private var currentProcess: Process?

    private init() {}

    /// 执行同步 (异步)
    func sync(
        source: String,
        destination: String,
        options: RsyncOptions = RsyncOptions(),
        progressHandler: ((String, Double?) -> Void)? = nil
    ) async throws -> RsyncResult {

        // 检查 rsync 是否存在
        guard FileManager.default.fileExists(atPath: rsyncPath) else {
            throw SyncError.rsyncNotFound
        }

        var arguments = options.toArguments()

        // 确保路径以 / 结尾 (目录同步)
        let sourcePath = source.hasSuffix("/") ? source : source + "/"
        let destPath = destination.hasSuffix("/") ? destination : destination + "/"

        arguments.append(sourcePath)
        arguments.append(destPath)

        Logger.shared.info("rsync 命令: rsync \(arguments.joined(separator: " "))")

        let startTime = Date()

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: rsyncPath)
            process.arguments = arguments

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            var outputData = Data()
            var errorData = Data()
            var lastProgressValue: Double = 0

            // 读取标准输出
            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }

                outputData.append(data)

                if let str = String(data: data, encoding: .utf8) {
                    // 解析进度
                    if let progress = self.parseProgress(str) {
                        lastProgressValue = progress
                        DispatchQueue.main.async {
                            progressHandler?(str, progress)
                        }
                    } else {
                        DispatchQueue.main.async {
                            progressHandler?(str, nil)
                        }
                    }
                }
            }

            // 读取标准错误
            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                errorData.append(data)
            }

            process.terminationHandler = { proc in
                // 清理 handlers
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil

                let endTime = Date()
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

                let success = proc.terminationStatus == 0

                let result = RsyncResult(
                    success: success,
                    output: output,
                    exitCode: proc.terminationStatus,
                    filesTransferred: self.parseFilesCount(output),
                    bytesTransferred: self.parseBytesTransferred(output),
                    errorMessage: success ? nil : (errorOutput.isEmpty ? "Exit code: \(proc.terminationStatus)" : errorOutput),
                    startTime: startTime,
                    endTime: endTime
                )

                if success {
                    Logger.shared.info("rsync 完成: \(result.filesTransferred) 文件, \(self.formatBytes(result.bytesTransferred)), 耗时 \(String(format: "%.1f", result.duration))秒")
                } else {
                    Logger.shared.error("rsync 失败: \(result.errorMessage ?? "未知错误")")
                }

                self.currentProcess = nil
                continuation.resume(returning: result)
            }

            do {
                currentProcess = process
                try process.run()
            } catch {
                currentProcess = nil
                continuation.resume(throwing: error)
            }
        }
    }

    /// 取消当前同步
    func cancel() {
        if let process = currentProcess, process.isRunning {
            process.terminate()
            Logger.shared.info("rsync 已取消")
        }
    }

    /// 检查是否正在同步
    var isSyncing: Bool {
        return currentProcess?.isRunning ?? false
    }

    // MARK: - 解析方法

    private func parseProgress(_ output: String) -> Double? {
        // 解析类似 "  1,234,567 100%   12.34MB/s    0:00:01" 的进度行
        let pattern = #"(\d+)%"#

        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
           let range = Range(match.range(at: 1), in: output) {
            if let percent = Double(output[range]) {
                return percent / 100.0
            }
        }
        return nil
    }

    private func parseFilesCount(_ output: String) -> Int {
        // 解析 "Number of files transferred: X" 或 "Number of regular files transferred: X"
        let patterns = [
            #"Number of regular files transferred:\s*(\d+)"#,
            #"Number of files transferred:\s*(\d+)"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
               let range = Range(match.range(at: 1), in: output) {
                return Int(output[range]) ?? 0
            }
        }
        return 0
    }

    private func parseBytesTransferred(_ output: String) -> Int64 {
        // 解析 "Total transferred file size: X bytes" 或 "Total transferred file size: X,XXX bytes"
        let pattern = #"Total transferred file size:\s*([\d,]+)"#

        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
           let range = Range(match.range(at: 1), in: output) {
            let numStr = String(output[range]).replacingOccurrences(of: ",", with: "")
            return Int64(numStr) ?? 0
        }
        return 0
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
