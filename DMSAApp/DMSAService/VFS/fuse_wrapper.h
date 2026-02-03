/*
 * fuse_wrapper.h
 * DMSA - Direct libfuse C wrapper
 *
 * Uses libfuse C API directly, avoiding GMUserFileSystem Objective-C runtime issues
 * Solves fork() crashes in multi-threaded processes
 *
 * Design principles:
 * - C code directly implements all FUSE callbacks
 * - Uses local_dir and external_dir paths for smart merging
 * - Write operations go to local_dir, reads prefer local_dir then external_dir
 */

#ifndef FUSE_WRAPPER_H
#define FUSE_WRAPPER_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <sys/stat.h>

#ifdef __cplusplus
extern "C" {
#endif

// ============================================================
// Error code definitions
// ============================================================
typedef enum {
    FUSE_WRAPPER_OK = 0,
    FUSE_WRAPPER_ERR_INVALID_ARG = -1,
    FUSE_WRAPPER_ERR_ALREADY_MOUNTED = -2,
    FUSE_WRAPPER_ERR_NOT_MOUNTED = -3,
    FUSE_WRAPPER_ERR_MOUNT_FAILED = -4,
    FUSE_WRAPPER_ERR_FUSE_NEW_FAILED = -6,
    FUSE_WRAPPER_ERR_FUSE_MOUNT_FAILED = -7,
} FuseWrapperError;

// ============================================================
// Public API - simplified
// ============================================================

/**
 * Mount FUSE filesystem
 *
 * This function blocks until the filesystem is unmounted.
 * Should be called from a background thread.
 *
 * @param mount_path Mount point path (e.g. /Users/xxx/Downloads)
 * @param local_dir Local directory path (e.g. /Users/xxx/Downloads_Local)
 * @param external_dir External directory path (can be NULL for offline)
 * @return FUSE_WRAPPER_OK on success, other values indicate error
 */
int fuse_wrapper_mount(
    const char *mount_path,
    const char *local_dir,
    const char *external_dir
);

/**
 * Unmount FUSE filesystem
 *
 * @return FUSE_WRAPPER_OK on success
 */
int fuse_wrapper_unmount(void);

/**
 * Check if mounted
 *
 * @return 1 if mounted, 0 if not
 */
int fuse_wrapper_is_mounted(void);

/**
 * Update external directory path
 * Can be called at runtime when external storage comes online/offline
 *
 * @param external_dir New external directory path, NULL means offline
 */
void fuse_wrapper_update_external_dir(const char *external_dir);

/**
 * Set external storage offline state
 *
 * @param offline true for offline, false for online
 */
void fuse_wrapper_set_external_offline(bool offline);

/**
 * Set read-only mode
 *
 * @param readonly true for read-only, false for read-write
 */
void fuse_wrapper_set_readonly(bool readonly);

/**
 * Set index ready state
 * When index is not ready, all file operations return EBUSY
 *
 * @param ready true for index ready, false for index not ready
 */
void fuse_wrapper_set_index_ready(bool ready);

/**
 * Get index ready state
 *
 * @return 1 if ready, 0 if not ready
 */
int fuse_wrapper_is_index_ready(void);

/**
 * Get error description
 *
 * @param error Error code
 * @return Error description string
 */
const char* fuse_wrapper_error_string(int error);

// ============================================================
// Eviction exclude list API
// ============================================================

/**
 * Mark a virtual path as being evicted.
 * While marked, FUSE resolve skips LOCAL and goes directly to EXTERNAL.
 * Call this BEFORE deleting the local file.
 *
 * @param virtual_path Virtual path (e.g. "/folder/file.txt")
 */
void fuse_wrapper_mark_evicting(const char *virtual_path);

/**
 * Unmark a virtual path from eviction.
 * Call this AFTER deleting the local file.
 *
 * @param virtual_path Virtual path (e.g. "/folder/file.txt")
 */
void fuse_wrapper_unmark_evicting(const char *virtual_path);

/**
 * Clear all eviction marks.
 */
void fuse_wrapper_clear_evicting(void);

// ============================================================
// Logging control API
// ============================================================

/**
 * Set log file path.
 * If set, logs will be written to this file instead of stderr.
 * Call this before fuse_wrapper_mount() for complete log capture.
 *
 * @param path Log file path (e.g. "/Users/xxx/Library/Logs/DMSA/fuse.log")
 *             Pass NULL to revert to stderr
 */
void fuse_wrapper_set_log_path(const char *path);

/**
 * Enable/disable FUSE debug logging at runtime.
 * Off by default. Use for diagnostics only.
 *
 * @param enabled 1 to enable, 0 to disable
 */
void fuse_wrapper_set_debug(int enabled);

/**
 * Flush buffered logs to file immediately.
 * Call before unmount or when logs need to be visible.
 */
void fuse_wrapper_flush_logs(void);

// ============================================================
// Diagnostics API
// ============================================================

/**
 * FUSE diagnostic information structure
 */
typedef struct {
    int is_mounted;           // Is FUSE mounted
    int is_loop_running;      // Is fuse_loop currently running
    int channel_fd;           // FUSE channel file descriptor (-1 if invalid)
    int macfuse_dev_count;    // Number of macfuse devices in /dev
    uint64_t total_ops;       // Total operations since mount
    uint64_t last_op_time;    // Timestamp of last operation (Unix time)
    int last_signal;          // Last signal received (0 if none)
    // Callback queue statistics
    uint64_t cb_queued;       // Total callbacks queued
    uint64_t cb_processed;    // Total callbacks processed
    uint64_t cb_dropped;      // Total callbacks dropped (queue overflow)
    int cb_pending;           // Current pending callbacks in queue
} FuseDiagnostics;

/**
 * Get current FUSE diagnostics
 * Can be called from any thread.
 *
 * @param diag Pointer to diagnostics structure to fill
 */
void fuse_wrapper_get_diagnostics(FuseDiagnostics *diag);

/**
 * Check if FUSE loop is currently running
 *
 * @return 1 if running, 0 if not
 */
int fuse_wrapper_is_loop_running(void);

// ============================================================
// Callbacks for Swift layer - DB tree updates
// ============================================================

/**
 * Callback function types for notifying Swift layer of filesystem changes
 * These callbacks update the database tree in real-time
 */
typedef void (*fuse_callback_file_created)(const char *virtual_path, const char *local_path, int is_directory);
typedef void (*fuse_callback_file_deleted)(const char *virtual_path, int is_directory);
typedef void (*fuse_callback_file_written)(const char *virtual_path);
typedef void (*fuse_callback_file_read)(const char *virtual_path);
typedef void (*fuse_callback_file_renamed)(const char *from_path, const char *to_path, int is_directory);

/**
 * Callback structure
 */
typedef struct {
    fuse_callback_file_created on_file_created;
    fuse_callback_file_deleted on_file_deleted;
    fuse_callback_file_written on_file_written;
    fuse_callback_file_read    on_file_read;
    fuse_callback_file_renamed on_file_renamed;
} FuseCallbacks;

/**
 * Set callbacks for filesystem events
 * Must be called before fuse_wrapper_mount()
 *
 * @param callbacks Pointer to callback structure (copied internally)
 */
void fuse_wrapper_set_callbacks(const FuseCallbacks *callbacks);

#ifdef __cplusplus
}
#endif

#endif /* FUSE_WRAPPER_H */
