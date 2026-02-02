import Foundation

/// DMSA unified service XPC protocol
/// Combines VFS + Sync + Helper functionality
@objc public protocol DMSAServiceProtocol {

    // MARK: - ========== VFS Operations ==========

    // MARK: Mount Management

    /// Mount VFS
    /// - Parameters:
    ///   - syncPairId: Sync pair ID
    ///   - localDir: Local directory path (LOCAL_DIR)
    ///   - externalDir: External directory path (EXTERNAL_DIR), empty string means offline
    ///   - targetDir: Mount point path (TARGET_DIR)
    func vfsMount(syncPairId: String,
                  localDir: String,
                  externalDir: String?,
                  targetDir: String,
                  withReply reply: @escaping (Bool, String?) -> Void)

    /// Unmount VFS
    func vfsUnmount(syncPairId: String,
                    withReply reply: @escaping (Bool, String?) -> Void)

    /// Unmount all VFS
    func vfsUnmountAll(withReply reply: @escaping (Bool, String?) -> Void)

    /// Get mount status
    func vfsGetMountStatus(syncPairId: String,
                           withReply reply: @escaping (Bool, String?) -> Void)

    /// Get all mount point status
    func vfsGetAllMounts(withReply reply: @escaping (Data) -> Void)

    // MARK: File Status

    /// Get file status
    func vfsGetFileStatus(virtualPath: String,
                          syncPairId: String,
                          withReply reply: @escaping (Data?) -> Void)

    /// Get file location
    func vfsGetFileLocation(virtualPath: String,
                            syncPairId: String,
                            withReply reply: @escaping (String) -> Void)

    // MARK: VFS Config

    /// Update EXTERNAL path (when disk reconnects)
    func vfsUpdateExternalPath(syncPairId: String,
                               newPath: String,
                               withReply reply: @escaping (Bool, String?) -> Void)

    /// Set EXTERNAL offline status
    func vfsSetExternalOffline(syncPairId: String,
                               offline: Bool,
                               withReply reply: @escaping (Bool, String?) -> Void)

    /// Set read-only mode
    func vfsSetReadOnly(syncPairId: String,
                        readOnly: Bool,
                        withReply reply: @escaping (Bool, String?) -> Void)

    // MARK: Index Management

    /// Rebuild file index
    func vfsRebuildIndex(syncPairId: String,
                         withReply reply: @escaping (Bool, String?) -> Void)

    /// Get index statistics
    func vfsGetIndexStats(syncPairId: String,
                          withReply reply: @escaping (Data?) -> Void)

    // MARK: - ========== Sync Operations ==========

    // MARK: Sync Control

    /// Sync specified sync pair immediately
    func syncNow(syncPairId: String,
                 withReply reply: @escaping (Bool, String?) -> Void)

    /// Sync all sync pairs
    func syncAll(withReply reply: @escaping (Bool, String?) -> Void)

    /// Sync single file
    func syncFile(virtualPath: String,
                  syncPairId: String,
                  withReply reply: @escaping (Bool, String?) -> Void)

    /// Pause sync
    func syncPause(syncPairId: String,
                   withReply reply: @escaping (Bool, String?) -> Void)

    /// Resume sync
    func syncResume(syncPairId: String,
                    withReply reply: @escaping (Bool, String?) -> Void)

    /// Cancel in-progress sync
    func syncCancel(syncPairId: String,
                    withReply reply: @escaping (Bool, String?) -> Void)

    // MARK: Status Query

    /// Get sync status
    func syncGetStatus(syncPairId: String,
                       withReply reply: @escaping (Data) -> Void)

    /// Get all sync pair status
    func syncGetAllStatus(withReply reply: @escaping (Data) -> Void)

    /// Get pending sync queue
    func syncGetPendingQueue(syncPairId: String,
                             withReply reply: @escaping (Data) -> Void)

    /// Get sync progress
    func syncGetProgress(syncPairId: String,
                         withReply reply: @escaping (Data?) -> Void)

    /// Get sync history
    func syncGetHistory(syncPairId: String,
                        limit: Int,
                        withReply reply: @escaping (Data) -> Void)

    /// Get sync statistics
    func syncGetStatistics(syncPairId: String,
                           withReply reply: @escaping (Data?) -> Void)

    // MARK: Dirty File Management

    /// Get dirty file list
    func syncGetDirtyFiles(syncPairId: String,
                           withReply reply: @escaping (Data) -> Void)

    /// Mark file as dirty
    func syncMarkFileDirty(virtualPath: String,
                           syncPairId: String,
                           withReply reply: @escaping (Bool) -> Void)

    /// Clear file dirty flag
    func syncClearFileDirty(virtualPath: String,
                            syncPairId: String,
                            withReply reply: @escaping (Bool) -> Void)

    // MARK: Sync Config

    /// Update sync config
    func syncUpdateConfig(syncPairId: String,
                          configData: Data,
                          withReply reply: @escaping (Bool, String?) -> Void)

    // MARK: Disk Events

    /// Notify disk connected
    func diskConnected(diskName: String,
                       mountPoint: String,
                       withReply reply: @escaping (Bool) -> Void)

    /// Notify disk disconnected
    func diskDisconnected(diskName: String,
                          withReply reply: @escaping (Bool) -> Void)

    // MARK: - ========== Privileged Operations ==========

    // MARK: Directory Lock

    /// Lock directory (set uchg flag)
    func privilegedLockDirectory(_ path: String,
                                 withReply reply: @escaping (Bool, String?) -> Void)

    /// Unlock directory
    func privilegedUnlockDirectory(_ path: String,
                                   withReply reply: @escaping (Bool, String?) -> Void)

    // MARK: ACL Management

    /// Set ACL
    func privilegedSetACL(_ path: String,
                          deny: Bool,
                          permissions: [String],
                          user: String,
                          withReply reply: @escaping (Bool, String?) -> Void)

    /// Remove ACL
    func privilegedRemoveACL(_ path: String,
                             withReply reply: @escaping (Bool, String?) -> Void)

    // MARK: Directory Visibility

    /// Hide directory
    func privilegedHideDirectory(_ path: String,
                                 withReply reply: @escaping (Bool, String?) -> Void)

    /// Unhide directory
    func privilegedUnhideDirectory(_ path: String,
                                   withReply reply: @escaping (Bool, String?) -> Void)

    // MARK: Compound Operations

    /// Protect directory (uchg + ACL + hidden)
    func privilegedProtectDirectory(_ path: String,
                                    withReply reply: @escaping (Bool, String?) -> Void)

    /// Unprotect directory
    func privilegedUnprotectDirectory(_ path: String,
                                      withReply reply: @escaping (Bool, String?) -> Void)

    // MARK: File System Operations

    /// Create directory (requires privilege)
    func privilegedCreateDirectory(_ path: String,
                                   withReply reply: @escaping (Bool, String?) -> Void)

    /// Move file/directory (requires privilege)
    func privilegedMoveItem(from source: String,
                            to destination: String,
                            withReply reply: @escaping (Bool, String?) -> Void)

    /// Delete file/directory (requires privilege)
    func privilegedRemoveItem(_ path: String,
                              withReply reply: @escaping (Bool, String?) -> Void)

    // MARK: - ========== Eviction Operations ==========

    /// Trigger LRU eviction
    /// - Parameters:
    ///   - syncPairId: Sync pair ID
    ///   - targetFreeSpace: Target free space (bytes)
    ///   - reply: Callback (success, freed space, error message)
    func evictionTrigger(syncPairId: String,
                         targetFreeSpace: Int64,
                         withReply reply: @escaping (Bool, Int64, String?) -> Void)

    /// Evict single file
    func evictionEvictFile(virtualPath: String,
                           syncPairId: String,
                           withReply reply: @escaping (Bool, String?) -> Void)

    /// Prefetch file (copy from EXTERNAL to LOCAL)
    func evictionPrefetchFile(virtualPath: String,
                              syncPairId: String,
                              withReply reply: @escaping (Bool, String?) -> Void)

    /// Get eviction statistics
    func evictionGetStats(withReply reply: @escaping (Data) -> Void)

    /// Update eviction config
    func evictionUpdateConfig(triggerThreshold: Int64,
                              targetFreeSpace: Int64,
                              autoEnabled: Bool,
                              withReply reply: @escaping (Bool) -> Void)

    // MARK: - ========== Data Query Operations ==========

    /// Get file entry
    func dataGetFileEntry(virtualPath: String,
                          syncPairId: String,
                          withReply reply: @escaping (Data?) -> Void)

    /// Get all file entries
    func dataGetAllFileEntries(syncPairId: String,
                               withReply reply: @escaping (Data) -> Void)

    /// Get all sync history
    func dataGetSyncHistory(limit: Int,
                            withReply reply: @escaping (Data) -> Void)

    /// Get file sync records (each synced/evicted file)
    func dataGetSyncFileRecords(syncPairId: String,
                                limit: Int,
                                withReply reply: @escaping (Data) -> Void)

    /// Get all file sync records (with pagination)
    func dataGetAllSyncFileRecords(limit: Int,
                                   offset: Int,
                                   withReply reply: @escaping (Data) -> Void)

    /// Get tree version info
    func dataGetTreeVersion(syncPairId: String,
                            source: String,
                            withReply reply: @escaping (String?) -> Void)

    /// Check tree versions (at startup)
    func dataCheckTreeVersions(localDir: String,
                               externalDir: String?,
                               syncPairId: String,
                               withReply reply: @escaping (Data) -> Void)

    /// Rebuild file tree
    func dataRebuildTree(rootPath: String,
                         syncPairId: String,
                         source: String,
                         withReply reply: @escaping (Bool, String?, String?) -> Void)

    /// Invalidate tree version
    func dataInvalidateTreeVersion(syncPairId: String,
                                   source: String,
                                   withReply reply: @escaping (Bool) -> Void)

    // MARK: - ========== Config Operations ==========

    /// Get full config
    func configGetAll(withReply reply: @escaping (Data) -> Void)

    /// Update full config
    func configUpdate(configData: Data,
                      withReply reply: @escaping (Bool, String?) -> Void)

    /// Get disk config list
    func configGetDisks(withReply reply: @escaping (Data) -> Void)

    /// Add disk config
    func configAddDisk(diskData: Data,
                       withReply reply: @escaping (Bool, String?) -> Void)

    /// Remove disk config
    func configRemoveDisk(diskId: String,
                          withReply reply: @escaping (Bool, String?) -> Void)

    /// Get sync pair config list
    func configGetSyncPairs(withReply reply: @escaping (Data) -> Void)

    /// Add sync pair config
    func configAddSyncPair(pairData: Data,
                           withReply reply: @escaping (Bool, String?) -> Void)

    /// Remove sync pair config
    func configRemoveSyncPair(pairId: String,
                              withReply reply: @escaping (Bool, String?) -> Void)

    /// Get notification config
    func configGetNotifications(withReply reply: @escaping (Data) -> Void)

    /// Update notification config
    func configUpdateNotifications(configData: Data,
                                   withReply reply: @escaping (Bool, String?) -> Void)

    // MARK: - ========== Notification Operations ==========

    /// Save notification record
    func notificationSave(recordData: Data,
                          withReply reply: @escaping (Bool) -> Void)

    /// Get notification records
    func notificationGetAll(limit: Int,
                            withReply reply: @escaping (Data) -> Void)

    /// Get unread notification count
    func notificationGetUnreadCount(withReply reply: @escaping (Int) -> Void)

    /// Mark notification as read
    func notificationMarkAsRead(recordId: UInt64,
                                withReply reply: @escaping (Bool) -> Void)

    /// Mark all notifications as read
    func notificationMarkAllAsRead(withReply reply: @escaping (Bool) -> Void)

    /// Clear all notifications
    func notificationClearAll(withReply reply: @escaping (Bool) -> Void)

    // MARK: - ========== General Operations ==========

    /// Set user home directory (called at App startup, for root service to resolve ~ paths correctly)
    func setUserHome(_ path: String,
                     withReply reply: @escaping (Bool) -> Void)

    /// Reload config
    func reloadConfig(withReply reply: @escaping (Bool, String?) -> Void)

    /// Prepare for shutdown (wait for all operations to complete)
    func prepareForShutdown(withReply reply: @escaping (Bool) -> Void)

    /// Get version
    func getVersion(withReply reply: @escaping (String) -> Void)

    /// Get detailed version info
    /// - Returns: Data (ServiceVersionInfo JSON)
    func getVersionInfo(withReply reply: @escaping (Data) -> Void)

    /// Check version compatibility
    /// - Parameter appVersion: Client App version
    /// - Returns: (compatible, error message, whether service update needed)
    func checkCompatibility(appVersion: String,
                            withReply reply: @escaping (Bool, String?, Bool) -> Void)

    /// Health check
    func healthCheck(withReply reply: @escaping (Bool, String?) -> Void)

    // MARK: - ========== State Management Operations ==========

    /// Get service full state
    /// - Returns: Data (ServiceFullState JSON)
    func getFullState(withReply reply: @escaping (Data) -> Void)

    /// Get current global state
    func getGlobalState(withReply reply: @escaping (Int, String) -> Void)

    /// Check if specified operation can be performed
    func canPerformOperation(_ operation: String,
                             withReply reply: @escaping (Bool) -> Void)

    // MARK: - ========== Activity Records ==========

    /// Get recent activity records
    func getRecentActivities(withReply reply: @escaping (Data) -> Void)
}

// MARK: - XPC Interface Config

public extension DMSAServiceProtocol {
    static var interfaceName: String { "com.ttttt.dmsa.service" }

    static func createInterface() -> NSXPCInterface {
        return NSXPCInterface(with: DMSAServiceProtocol.self)
    }
}
