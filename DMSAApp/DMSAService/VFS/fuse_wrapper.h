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
// Debug control API
// ============================================================

/**
 * Enable/disable FUSE debug logging at runtime.
 * Off by default. Use for diagnostics only.
 *
 * @param enabled 1 to enable, 0 to disable
 */
void fuse_wrapper_set_debug(int enabled);

#ifdef __cplusplus
}
#endif

#endif /* FUSE_WRAPPER_H */
