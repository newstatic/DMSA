import Foundation

/// VFS 文件系统实现
/// 实现 FUSEFileSystemOperations 协议，桥接 FUSE 回调和 VFSCore
///
/// ⚠️ DEPRECATED: 此类不再使用，FUSE 操作已迁移至 DMSAService/VFS/FUSEFileSystem.swift
/// 保留此文件是为了向后兼容，将在未来版本中删除。
@available(*, deprecated, message: "Use DMSAService FUSEFileSystem instead")
class VFSFileSystem: FUSEFileSystemOperations {

    // MARK: - 属性

    private let syncPairId: UUID
    private let syncPair: SyncPairConfig
    private let vfsCore: VFSCore
    private let mergeEngine: MergeEngine
    private let databaseManager: DatabaseManager

    /// 打开的文件句柄
    private var openFiles: [UInt64: OpenFileInfo] = [:]
    private var nextFileHandle: UInt64 = 1
    private let fileHandleLock = NSLock()

    struct OpenFileInfo {
        let path: String
        let localPath: String?
        let externalPath: String?
        let flags: Int32
        let fd: Int32?  // 系统文件描述符
    }

    // MARK: - 初始化

    init(syncPairId: UUID, syncPair: SyncPairConfig) {
        self.syncPairId = syncPairId
        self.syncPair = syncPair
        self.vfsCore = VFSCore.shared
        self.mergeEngine = MergeEngine.shared
        self.databaseManager = DatabaseManager.shared
    }

    // MARK: - 元数据操作

    func getattr(_ path: String) async -> FUSEStatResult {
        do {
            let attrs = try await mergeEngine.getAttributes(path, syncPairId: syncPairId)

            var st = stat()
            st.st_size = off_t(attrs.size)
            st.st_mode = attrs.isDirectory
                ? mode_t(S_IFDIR) | mode_t(attrs.permissions)
                : mode_t(S_IFREG) | mode_t(attrs.permissions)
            st.st_nlink = attrs.isDirectory ? 2 : 1
            st.st_mtimespec.tv_sec = time_t(attrs.modifiedAt.timeIntervalSince1970)
            st.st_atimespec.tv_sec = time_t(attrs.accessedAt.timeIntervalSince1970)
            st.st_ctimespec.tv_sec = time_t(attrs.createdAt.timeIntervalSince1970)
            st.st_uid = getuid()
            st.st_gid = getgid()

            return .success(st)
        } catch {
            Logger.shared.debug("VFSFileSystem getattr error: \(path) - \(error)")
            return .error(ENOENT)
        }
    }

    func readlink(_ path: String) async -> FUSEDataResult {
        // DMSA 不支持符号链接
        return .error(EINVAL)
    }

    // MARK: - 目录操作

    func mkdir(_ path: String, mode: mode_t) async -> FUSEResult {
        let errno = await vfsCore.fuseMkdir(path, mode: mode, syncPairId: syncPairId)
        return errno == 0 ? .success : .error(errno)
    }

    func rmdir(_ path: String) async -> FUSEResult {
        let errno = await vfsCore.fuseRmdir(path, syncPairId: syncPairId)
        return errno == 0 ? .success : .error(errno)
    }

    func readdir(_ path: String) async -> FUSEReaddirResult {
        let (entries, errno) = await vfsCore.fuseReaddir(path, syncPairId: syncPairId)
        if errno == 0, let entries = entries {
            return .success(entries)
        }
        return .error(errno)
    }

    // MARK: - 文件操作

    func create(_ path: String, mode: mode_t, flags: Int32) async -> FUSEOpenResult {
        let errno = await vfsCore.fuseCreate(path, mode: mode, syncPairId: syncPairId)
        if errno != 0 {
            return .error(errno)
        }

        // 分配文件句柄
        let fh = allocateFileHandle(path: path, flags: flags)
        return .success(fh)
    }

    func open(_ path: String, flags: Int32) async -> FUSEOpenResult {
        let (fd, errno) = await vfsCore.fuseOpen(path, flags: flags, syncPairId: syncPairId)
        if errno != 0 {
            return .error(errno)
        }

        // 分配文件句柄并保存 fd
        let fh = allocateFileHandle(path: path, flags: flags, fd: fd)
        return .success(fh)
    }

    func read(_ path: String, size: Int, offset: off_t, fh: UInt64) async -> FUSEDataResult {
        // 获取文件信息
        guard let fileInfo = getFileInfo(fh) else {
            return .error(EBADF)
        }

        // 如果有系统 fd，直接读取
        if let fd = fileInfo.fd {
            var buffer = [UInt8](repeating: 0, count: size)
            let bytesRead = pread(fd, &buffer, size, offset)
            if bytesRead < 0 {
                return .error(errno)
            }
            return .success(Data(buffer[0..<bytesRead]))
        }

        // 否则通过路径读取
        let actualPath: String
        if let localPath = fileInfo.localPath,
           FileManager.default.fileExists(atPath: localPath) {
            actualPath = localPath
        } else if let externalPath = fileInfo.externalPath,
                  FileManager.default.fileExists(atPath: externalPath) {
            actualPath = externalPath
        } else {
            return .error(ENOENT)
        }

        do {
            let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: actualPath))
            try handle.seek(toOffset: UInt64(offset))
            let data = handle.readData(ofLength: size)
            try handle.close()
            return .success(data)
        } catch {
            return .error(EIO)
        }
    }

    func write(_ path: String, data: Data, offset: off_t, fh: UInt64) async -> FUSESizeResult {
        let bytesWritten = await vfsCore.fuseWrite(
            path,
            buffer: data.withUnsafeBytes { $0.baseAddress!.assumingMemoryBound(to: UInt8.self) },
            size: data.count,
            offset: offset,
            syncPairId: syncPairId
        )

        if bytesWritten < 0 {
            return .error(-bytesWritten)
        }
        return .success(Int(bytesWritten))
    }

    func release(_ path: String, fh: UInt64) async -> FUSEResult {
        releaseFileHandle(fh)
        return .success
    }

    func unlink(_ path: String) async -> FUSEResult {
        let errno = await vfsCore.fuseUnlink(path, syncPairId: syncPairId)
        return errno == 0 ? .success : .error(errno)
    }

    func rename(_ from: String, to: String) async -> FUSEResult {
        let errno = await vfsCore.fuseRename(from, to: to, syncPairId: syncPairId)
        return errno == 0 ? .success : .error(errno)
    }

    func truncate(_ path: String, size: off_t) async -> FUSEResult {
        guard let localPath = PathValidator.localPath(for: path, in: syncPair) else {
            return .error(EINVAL)
        }

        do {
            let url = URL(fileURLWithPath: localPath)
            let handle = try FileHandle(forWritingTo: url)
            try handle.truncate(atOffset: UInt64(size))
            try handle.close()

            // 更新数据库
            if var entry = databaseManager.getFileEntry(virtualPath: path) {
                entry.size = Int64(size)
                entry.modifiedAt = Date()
                entry.isDirty = true
                databaseManager.saveFileEntry(entry)
            }

            return .success
        } catch {
            return .error(EIO)
        }
    }

    // MARK: - 扩展属性

    func getxattr(_ path: String, name: String) async -> FUSEDataResult {
        // 获取实际路径
        let actualPath: String
        if let localPath = PathValidator.localPath(for: path, in: syncPair),
           FileManager.default.fileExists(atPath: localPath) {
            actualPath = localPath
        } else if let externalPath = PathValidator.externalPath(for: path, in: syncPair),
                  FileManager.default.fileExists(atPath: externalPath) {
            actualPath = externalPath
        } else {
            return .error(ENOENT)
        }

        // 使用 Darwin.getxattr 系统调用
        let nameC = name.cString(using: .utf8)!
        var size = Darwin.getxattr(actualPath, nameC, nil, 0, 0, 0)
        if size < 0 {
            return .error(errno)
        }

        var buffer = [UInt8](repeating: 0, count: size)
        size = Darwin.getxattr(actualPath, nameC, &buffer, size, 0, 0)
        if size < 0 {
            return .error(errno)
        }

        return .success(Data(buffer[0..<size]))
    }

    func setxattr(_ path: String, name: String, data: Data, flags: Int32) async -> FUSEResult {
        guard let localPath = PathValidator.localPath(for: path, in: syncPair) else {
            return .error(EINVAL)
        }

        let nameC = name.cString(using: .utf8)!
        let result = data.withUnsafeBytes { buffer in
            Darwin.setxattr(localPath, nameC, buffer.baseAddress, data.count, 0, flags)
        }

        return result == 0 ? .success : .error(errno)
    }

    func listxattr(_ path: String) async -> FUSEDataResult {
        let actualPath: String
        if let localPath = PathValidator.localPath(for: path, in: syncPair),
           FileManager.default.fileExists(atPath: localPath) {
            actualPath = localPath
        } else if let externalPath = PathValidator.externalPath(for: path, in: syncPair),
                  FileManager.default.fileExists(atPath: externalPath) {
            actualPath = externalPath
        } else {
            return .error(ENOENT)
        }

        var size = Darwin.listxattr(actualPath, nil, 0, 0)
        if size < 0 {
            return .error(errno)
        }

        if size == 0 {
            return .success(Data())
        }

        var buffer = [Int8](repeating: 0, count: size)
        size = Darwin.listxattr(actualPath, &buffer, size, 0)
        if size < 0 {
            return .error(errno)
        }

        return .success(Data(bytes: buffer, count: size))
    }

    func removexattr(_ path: String, name: String) async -> FUSEResult {
        guard let localPath = PathValidator.localPath(for: path, in: syncPair) else {
            return .error(EINVAL)
        }

        let nameC = name.cString(using: .utf8)!
        let result = Darwin.removexattr(localPath, nameC, 0)

        return result == 0 ? .success : .error(errno)
    }

    // MARK: - 可选操作

    func statfs(_ path: String) async -> FUSEStatfsResult {
        // 使用 FileManager 获取文件系统统计
        let localDir = syncPair.localDir
        let fm = FileManager.default

        do {
            let attrs = try fm.attributesOfFileSystem(forPath: localDir)

            var st = Darwin.statfs()
            st.f_bsize = UInt32((attrs[.systemSize] as? Int64) ?? 4096)

            let totalSize = (attrs[.systemSize] as? Int64) ?? 0
            let freeSize = (attrs[.systemFreeSize] as? Int64) ?? 0
            let blockSize: Int64 = 4096

            st.f_blocks = UInt64(totalSize / blockSize)
            st.f_bfree = UInt64(freeSize / blockSize)
            st.f_bavail = UInt64(freeSize / blockSize)
            st.f_files = (attrs[.systemNodes] as? UInt64) ?? 1_000_000
            st.f_ffree = (attrs[.systemFreeNodes] as? UInt64) ?? 500_000
            st.f_bsize = UInt32(blockSize)

            return .success(st)
        } catch {
            // 返回默认值
            return .success(Darwin.statfs.defaultStats())
        }
    }

    func flush(_ path: String, fh: UInt64) async -> FUSEResult {
        // 同步文件缓冲区
        if let fileInfo = getFileInfo(fh), let fd = fileInfo.fd {
            if Darwin.fsync(fd) != 0 {
                return .error(errno)
            }
        }
        return .success
    }

    func fsync(_ path: String, datasync: Bool, fh: UInt64) async -> FUSEResult {
        if let fileInfo = getFileInfo(fh), let fd = fileInfo.fd {
            let result = datasync ? fdatasync(fd) : Darwin.fsync(fd)
            if result != 0 {
                return .error(errno)
            }
        }
        return .success
    }

    func access(_ path: String, mask: Int32) async -> FUSEResult {
        // 检查文件是否存在
        let exists = await mergeEngine.exists(path, syncPairId: syncPairId)
        return exists ? .success : .error(ENOENT)
    }

    func utimens(_ path: String, atime: timespec, mtime: timespec) async -> FUSEResult {
        guard let localPath = PathValidator.localPath(for: path, in: syncPair) else {
            return .error(EINVAL)
        }

        // 使用 utimensat 更新时间戳
        var times = [atime, mtime]
        let result = utimensat(AT_FDCWD, localPath, &times, 0)

        if result == 0 {
            // 更新数据库
            if var entry = databaseManager.getFileEntry(virtualPath: path) {
                entry.accessedAt = Date(timeIntervalSince1970: Double(atime.tv_sec))
                entry.modifiedAt = Date(timeIntervalSince1970: Double(mtime.tv_sec))
                databaseManager.saveFileEntry(entry)
            }
            return .success
        }

        return .error(errno)
    }

    // MARK: - 文件句柄管理

    private func allocateFileHandle(path: String, flags: Int32, fd: Int32? = nil) -> UInt64 {
        fileHandleLock.lock()
        defer { fileHandleLock.unlock() }

        let fh = nextFileHandle
        nextFileHandle += 1

        let fileInfo = OpenFileInfo(
            path: path,
            localPath: PathValidator.localPath(for: path, in: syncPair),
            externalPath: PathValidator.externalPath(for: path, in: syncPair),
            flags: flags,
            fd: fd
        )
        openFiles[fh] = fileInfo

        return fh
    }

    private func getFileInfo(_ fh: UInt64) -> OpenFileInfo? {
        fileHandleLock.lock()
        defer { fileHandleLock.unlock() }
        return openFiles[fh]
    }

    private func releaseFileHandle(_ fh: UInt64) {
        fileHandleLock.lock()
        defer { fileHandleLock.unlock() }

        if let fileInfo = openFiles[fh], let fd = fileInfo.fd {
            close(fd)
        }
        openFiles.removeValue(forKey: fh)
    }
}

// MARK: - fdatasync 兼容

/// macOS 没有 fdatasync，使用 fcntl 替代
private func fdatasync(_ fd: Int32) -> Int32 {
    return fcntl(fd, F_FULLFSYNC)
}
