import Foundation

/// 差异计算引擎 - 比较两个目录快照并生成同步计划
class DiffEngine {

    // MARK: - 配置

    struct DiffOptions {
        /// 是否比较校验和
        var compareChecksums: Bool = false

        /// 是否检测文件移动
        var detectMoves: Bool = true

        /// 是否忽略权限差异
        var ignorePermissions: Bool = false

        /// 是否忽略所有者差异
        var ignoreOwnership: Bool = true

        /// 时间容差（秒）- 两个文件修改时间在此范围内视为相同
        var timeTolerance: TimeInterval = 2.0

        /// 是否启用删除
        var enableDelete: Bool = true

        /// 最大文件大小 (nil 表示无限制)
        var maxFileSize: Int64? = nil

        static var `default`: DiffOptions { DiffOptions() }
    }

    // MARK: - 结果类型

    struct DiffResult {
        /// 需要复制的文件 (源有，目标无)
        var toCopy: [String] = []

        /// 需要更新的文件 (两边都有但不同)
        var toUpdate: [String] = []

        /// 需要删除的文件 (源无，目标有)
        var toDelete: [String] = []

        /// 冲突的文件 (需要特殊处理)
        var conflicts: [String] = []

        /// 相同的文件 (无需操作)
        var identical: [String] = []

        /// 检测到的移动操作 (from -> to)
        var moves: [(from: String, to: String)] = []

        /// 需要创建的目录
        var directoriesToCreate: [String] = []

        /// 需要删除的目录
        var directoriesToDelete: [String] = []

        /// 跳过的文件及原因
        var skipped: [(path: String, reason: SkipReason)] = []

        // MARK: - 统计

        var totalChanges: Int {
            toCopy.count + toUpdate.count + toDelete.count + moves.count
        }

        var hasChanges: Bool {
            totalChanges > 0 || directoriesToCreate.count > 0
        }

        var summary: String {
            var parts: [String] = []
            if !toCopy.isEmpty { parts.append("新增 \(toCopy.count)") }
            if !toUpdate.isEmpty { parts.append("更新 \(toUpdate.count)") }
            if !toDelete.isEmpty { parts.append("删除 \(toDelete.count)") }
            if !moves.isEmpty { parts.append("移动 \(moves.count)") }
            if !conflicts.isEmpty { parts.append("冲突 \(conflicts.count)") }
            if parts.isEmpty { return "无变化" }
            return parts.joined(separator: ", ")
        }
    }

    // MARK: - 公共方法

    /// 计算两个目录快照的差异
    func calculateDiff(
        source: DirectorySnapshot,
        destination: DirectorySnapshot,
        direction: SyncDirection,
        options: DiffOptions = .default
    ) -> DiffResult {
        var result = DiffResult()

        let sourceFiles = source.files
        let destFiles = destination.files

        let sourceKeys = Set(sourceFiles.keys)
        let destKeys = Set(destFiles.keys)

        // 根据同步方向处理
        switch direction {
        case .localToExternal, .externalToLocal:
            // 单向同步
            calculateUnidirectionalDiff(
                sourceFiles: sourceFiles,
                destFiles: destFiles,
                sourceKeys: sourceKeys,
                destKeys: destKeys,
                options: options,
                result: &result
            )

        case .bidirectional:
            // 双向同步 - 需要检测冲突
            calculateBidirectionalDiff(
                sourceFiles: sourceFiles,
                destFiles: destFiles,
                sourceKeys: sourceKeys,
                destKeys: destKeys,
                options: options,
                result: &result
            )
        }

        // 检测移动操作
        if options.detectMoves {
            detectMoves(result: &result, sourceFiles: sourceFiles, destFiles: destFiles)
        }

        // 整理目录创建顺序（父目录在前）
        result.directoriesToCreate.sort()

        // 整理目录删除顺序（子目录在前）
        result.directoriesToDelete.sort(by: >)

        return result
    }

    /// 根据差异结果生成同步计划
    func createSyncPlan(
        from diffResult: DiffResult,
        source: DirectorySnapshot,
        destination: DirectorySnapshot,
        syncPairId: String,
        direction: SyncDirection
    ) -> SyncPlan {
        var plan = SyncPlan(
            syncPairId: syncPairId,
            direction: direction,
            sourcePath: source.rootPath,
            destinationPath: destination.rootPath
        )

        // 添加目录创建动作
        for dir in diffResult.directoriesToCreate {
            plan.addAction(.createDirectory(path: dir))
        }

        // 添加复制动作
        for path in diffResult.toCopy {
            if let metadata = source.metadata(for: path) {
                let sourcePath = (source.rootPath as NSString).appendingPathComponent(path)
                let destPath = (destination.rootPath as NSString).appendingPathComponent(path)
                plan.addAction(.copy(source: sourcePath, destination: destPath, metadata: metadata))
            }
        }

        // 添加更新动作
        for path in diffResult.toUpdate {
            if let metadata = source.metadata(for: path) {
                let sourcePath = (source.rootPath as NSString).appendingPathComponent(path)
                let destPath = (destination.rootPath as NSString).appendingPathComponent(path)
                plan.addAction(.update(source: sourcePath, destination: destPath, metadata: metadata))
            }
        }

        // 添加删除动作
        for path in diffResult.toDelete {
            if let metadata = destination.metadata(for: path) {
                let destPath = (destination.rootPath as NSString).appendingPathComponent(path)
                plan.addAction(.delete(path: destPath, metadata: metadata))
            }
        }

        // 添加冲突
        for path in diffResult.conflicts {
            let localMeta = source.metadata(for: path)
            let externalMeta = destination.metadata(for: path)

            let conflict = ConflictInfo(
                relativePath: path,
                localPath: (source.rootPath as NSString).appendingPathComponent(path),
                externalPath: (destination.rootPath as NSString).appendingPathComponent(path),
                localMetadata: localMeta,
                externalMetadata: externalMeta,
                conflictType: determineConflictType(local: localMeta, external: externalMeta)
            )

            plan.addConflict(conflict)
            plan.addAction(.resolveConflict(conflict: conflict))
        }

        // 添加跳过动作
        for (path, reason) in diffResult.skipped {
            plan.addAction(.skip(path: path, reason: reason))
        }

        // 保存快照供后续使用
        plan.sourceSnapshot = source
        plan.destinationSnapshot = destination

        return plan
    }

    // MARK: - 私有方法

    /// 单向同步差异计算
    private func calculateUnidirectionalDiff(
        sourceFiles: [String: FileMetadata],
        destFiles: [String: FileMetadata],
        sourceKeys: Set<String>,
        destKeys: Set<String>,
        options: DiffOptions,
        result: inout DiffResult
    ) {
        // 源有目标无 -> 复制
        let newFiles = sourceKeys.subtracting(destKeys)
        for path in newFiles {
            guard let meta = sourceFiles[path] else { continue }

            // 检查文件大小限制
            if let maxSize = options.maxFileSize, meta.size > maxSize {
                result.skipped.append((path, .tooLarge))
                continue
            }

            if meta.isDirectory {
                result.directoriesToCreate.append(path)
            } else {
                result.toCopy.append(path)
            }
        }

        // 源无目标有 -> 删除（如果启用）
        if options.enableDelete {
            let removedFiles = destKeys.subtracting(sourceKeys)
            for path in removedFiles {
                if let meta = destFiles[path] {
                    if meta.isDirectory {
                        result.directoriesToDelete.append(path)
                    } else {
                        result.toDelete.append(path)
                    }
                }
            }
        }

        // 两边都有 -> 比较是否需要更新
        let commonFiles = sourceKeys.intersection(destKeys)
        for path in commonFiles {
            guard let sourceMeta = sourceFiles[path],
                  let destMeta = destFiles[path] else { continue }

            // 跳过目录
            if sourceMeta.isDirectory && destMeta.isDirectory {
                continue
            }

            // 类型不匹配
            if sourceMeta.isDirectory != destMeta.isDirectory {
                result.conflicts.append(path)
                continue
            }

            // 比较是否相同
            if areFilesIdentical(sourceMeta, destMeta, options: options) {
                result.identical.append(path)
            } else {
                result.toUpdate.append(path)
            }
        }
    }

    /// 双向同步差异计算
    private func calculateBidirectionalDiff(
        sourceFiles: [String: FileMetadata],
        destFiles: [String: FileMetadata],
        sourceKeys: Set<String>,
        destKeys: Set<String>,
        options: DiffOptions,
        result: inout DiffResult
    ) {
        // 源有目标无 -> 复制到目标
        let newInSource = sourceKeys.subtracting(destKeys)
        for path in newInSource {
            guard let meta = sourceFiles[path] else { continue }

            if let maxSize = options.maxFileSize, meta.size > maxSize {
                result.skipped.append((path, .tooLarge))
                continue
            }

            if meta.isDirectory {
                result.directoriesToCreate.append(path)
            } else {
                result.toCopy.append(path)
            }
        }

        // 源无目标有 -> 从目标复制到源（或标记冲突）
        let newInDest = destKeys.subtracting(sourceKeys)
        for path in newInDest {
            // 双向同步中，目标新增的文件可能是用户想要保留的
            // 标记为需要从目标同步到源
            result.conflicts.append(path)
        }

        // 两边都有 -> 检测冲突
        let commonFiles = sourceKeys.intersection(destKeys)
        for path in commonFiles {
            guard let sourceMeta = sourceFiles[path],
                  let destMeta = destFiles[path] else { continue }

            if sourceMeta.isDirectory && destMeta.isDirectory {
                continue
            }

            if sourceMeta.isDirectory != destMeta.isDirectory {
                result.conflicts.append(path)
                continue
            }

            if areFilesIdentical(sourceMeta, destMeta, options: options) {
                result.identical.append(path)
            } else {
                // 双向同步中，两边都有但不同 -> 冲突
                result.conflicts.append(path)
            }
        }
    }

    /// 比较两个文件是否相同
    private func areFilesIdentical(
        _ source: FileMetadata,
        _ dest: FileMetadata,
        options: DiffOptions
    ) -> Bool {
        // 大小必须相同
        if source.size != dest.size {
            return false
        }

        // 比较修改时间（有容差）
        let timeDiff = abs(source.modifiedTime.timeIntervalSince(dest.modifiedTime))
        if timeDiff > options.timeTolerance {
            return false
        }

        // 如果启用校验和比较且都有校验和
        if options.compareChecksums,
           let sourceChecksum = source.checksum,
           let destChecksum = dest.checksum {
            return sourceChecksum.lowercased() == destChecksum.lowercased()
        }

        // 比较权限（可选）
        if !options.ignorePermissions && source.permissions != dest.permissions {
            return false
        }

        return true
    }

    /// 检测文件移动
    private func detectMoves(
        result: inout DiffResult,
        sourceFiles: [String: FileMetadata],
        destFiles: [String: FileMetadata]
    ) {
        // 构建校验和索引
        var destChecksumIndex: [String: [String]] = [:]
        for (path, meta) in destFiles {
            if let checksum = meta.checksum, !meta.isDirectory {
                destChecksumIndex[checksum, default: []].append(path)
            }
        }

        var detectedMoves: [(from: String, to: String)] = []
        var movedPaths: Set<String> = []

        // 检测从"新增"变为"移动"
        for path in result.toCopy {
            guard let meta = sourceFiles[path],
                  let checksum = meta.checksum,
                  let candidates = destChecksumIndex[checksum] else { continue }

            // 查找待删除列表中是否有相同校验和的文件
            for candidate in candidates {
                if result.toDelete.contains(candidate) && !movedPaths.contains(candidate) {
                    // 检测到移动
                    detectedMoves.append((from: candidate, to: path))
                    movedPaths.insert(candidate)
                    movedPaths.insert(path)
                    break
                }
            }
        }

        // 更新结果
        if !detectedMoves.isEmpty {
            result.moves = detectedMoves

            // 从复制和删除列表中移除已检测为移动的项
            let movedFromPaths = Set(detectedMoves.map { $0.from })
            let movedToPaths = Set(detectedMoves.map { $0.to })

            result.toCopy.removeAll { movedToPaths.contains($0) }
            result.toDelete.removeAll { movedFromPaths.contains($0) }
        }
    }

    /// 确定冲突类型
    private func determineConflictType(
        local: FileMetadata?,
        external: FileMetadata?
    ) -> ConflictType {
        switch (local, external) {
        case (nil, _):
            return .deletedOnLocal
        case (_, nil):
            return .deletedOnExternal
        case let (l?, e?) where l.isDirectory != e.isDirectory:
            return .typeChanged
        default:
            return .bothModified
        }
    }
}

// MARK: - 便捷方法

extension DiffEngine {
    /// 快速比较两个目录
    static func quickCompare(
        source: URL,
        destination: URL,
        excludePatterns: [String] = []
    ) async throws -> DiffResult {
        let scanner = FileScanner(excludePatterns: excludePatterns)

        async let sourceSnapshot = scanner.scan(directory: source)
        async let destSnapshot = scanner.scan(directory: destination)

        let engine = DiffEngine()
        return engine.calculateDiff(
            source: try await sourceSnapshot,
            destination: try await destSnapshot,
            direction: .localToExternal
        )
    }
}
