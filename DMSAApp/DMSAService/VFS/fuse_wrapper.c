/*
 * fuse_wrapper.c
 * DMSA - Direct libfuse C wrapper implementation
 *
 * Direct FUSE filesystem callback implementation without GMUserFileSystem
 * Solves fork() crash issues in multi-threaded processes
 */

// macOS specific definitions
#define _DARWIN_USE_64_BIT_INODE 1

// FUSE API version (macFUSE uses FUSE 2.x API)
#define FUSE_USE_VERSION 26

#include <fuse/fuse.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <dirent.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/xattr.h>
#include <sys/time.h>
#include <pthread.h>
#include <libgen.h>
#include <signal.h>
#include <sys/mount.h>

#include "fuse_wrapper.h"

// ============================================================
// Logging macros with file output support - optimized for performance
// ============================================================
#define LOG_PREFIX "[FUSE-C] "

// Runtime debug toggle - off by default even in DEBUG builds
// Enable via fuse_wrapper_set_debug(1) from Swift when needed
static volatile int g_fuse_debug = 0;

// Log file support with buffered I/O for performance
static FILE *g_log_file = NULL;
static pthread_mutex_t g_log_mutex = PTHREAD_MUTEX_INITIALIZER;

// Log buffer for batched writes (reduces syscall overhead)
#define LOG_BUFFER_SIZE 8192
static char g_log_buffer[LOG_BUFFER_SIZE];
static size_t g_log_buffer_pos = 0;
static time_t g_last_flush_time = 0;
#define LOG_FLUSH_INTERVAL 2  // Flush every 2 seconds max

// Get current log output destination
static inline FILE* get_log_file(void) {
    return g_log_file ? g_log_file : stderr;
}

// Flush log buffer to file
static void flush_log_buffer_locked(void) {
    if (g_log_buffer_pos > 0 && g_log_file) {
        fwrite(g_log_buffer, 1, g_log_buffer_pos, g_log_file);
        fflush(g_log_file);
        g_log_buffer_pos = 0;
        g_last_flush_time = time(NULL);
    }
}

// Write to log buffer (called with mutex held)
static void log_write_buffered(const char *msg, size_t len) {
    FILE *f = get_log_file();

    // If no log file or stderr, write directly
    if (!g_log_file || f == stderr) {
        fwrite(msg, 1, len, f);
        return;
    }

    // Check if we need to flush (buffer full or time elapsed)
    time_t now = time(NULL);
    if (g_log_buffer_pos + len > LOG_BUFFER_SIZE - 1 ||
        (g_log_buffer_pos > 0 && now - g_last_flush_time >= LOG_FLUSH_INTERVAL)) {
        flush_log_buffer_locked();
    }

    // Add to buffer
    if (len < LOG_BUFFER_SIZE - 1) {
        memcpy(g_log_buffer + g_log_buffer_pos, msg, len);
        g_log_buffer_pos += len;
    } else {
        // Message too large, write directly
        flush_log_buffer_locked();
        fwrite(msg, 1, len, g_log_file);
        fflush(g_log_file);
    }
}

// Set log file path (call before mount)
void fuse_wrapper_set_log_path(const char *path) {
    pthread_mutex_lock(&g_log_mutex);

    // Flush existing buffer before closing
    flush_log_buffer_locked();

    if (g_log_file && g_log_file != stderr) {
        fclose(g_log_file);
        g_log_file = NULL;
    }
    if (path) {
        g_log_file = fopen(path, "a");
        if (g_log_file) {
            // Use line buffering for reasonable performance with some immediacy
            setvbuf(g_log_file, NULL, _IOLBF, 0);
            fprintf(g_log_file, LOG_PREFIX "INFO: Log file opened: %s\n", path);
            fflush(g_log_file);
            g_last_flush_time = time(NULL);
        } else {
            fprintf(stderr, LOG_PREFIX "WARN: Failed to open log file: %s (errno=%d)\n", path, errno);
        }
    }
    pthread_mutex_unlock(&g_log_mutex);
}

void fuse_wrapper_set_debug(int enabled) {
    g_fuse_debug = enabled;
    pthread_mutex_lock(&g_log_mutex);
    FILE *f = get_log_file();
    fprintf(f, LOG_PREFIX "INFO: Debug logging %s\n", enabled ? "ENABLED" : "DISABLED");
    if (g_log_file) fflush(g_log_file);
    pthread_mutex_unlock(&g_log_mutex);
}

// Flush logs explicitly (call before unmount or on important events)
void fuse_wrapper_flush_logs(void) {
    pthread_mutex_lock(&g_log_mutex);
    flush_log_buffer_locked();
    pthread_mutex_unlock(&g_log_mutex);
}

// Optimized LOG_DEBUG - early exit if debug disabled (no lock overhead)
#define LOG_DEBUG(fmt, ...) do { \
    if (g_fuse_debug) { \
        char _log_buf[512]; \
        int _log_len = snprintf(_log_buf, sizeof(_log_buf), \
            LOG_PREFIX "DEBUG: " fmt "\n", ##__VA_ARGS__); \
        if (_log_len > 0) { \
            pthread_mutex_lock(&g_log_mutex); \
            log_write_buffered(_log_buf, (size_t)_log_len); \
            pthread_mutex_unlock(&g_log_mutex); \
        } \
    } \
} while(0)

// LOG_INFO - buffered write
#define LOG_INFO(fmt, ...) do { \
    char _log_buf[512]; \
    int _log_len = snprintf(_log_buf, sizeof(_log_buf), \
        LOG_PREFIX "INFO: " fmt "\n", ##__VA_ARGS__); \
    if (_log_len > 0) { \
        pthread_mutex_lock(&g_log_mutex); \
        log_write_buffered(_log_buf, (size_t)_log_len); \
        pthread_mutex_unlock(&g_log_mutex); \
    } \
} while(0)

// LOG_WARN - immediate flush for warnings
#define LOG_WARN(fmt, ...) do { \
    pthread_mutex_lock(&g_log_mutex); \
    flush_log_buffer_locked(); \
    FILE *_f = get_log_file(); \
    fprintf(_f, LOG_PREFIX "WARN: " fmt "\n", ##__VA_ARGS__); \
    if (g_log_file) fflush(g_log_file); \
    pthread_mutex_unlock(&g_log_mutex); \
} while(0)

// LOG_ERROR - immediate flush for errors
#define LOG_ERROR(fmt, ...) do { \
    pthread_mutex_lock(&g_log_mutex); \
    flush_log_buffer_locked(); \
    FILE *_f = get_log_file(); \
    fprintf(_f, LOG_PREFIX "ERROR: " fmt "\n", ##__VA_ARGS__); \
    if (g_log_file) fflush(g_log_file); \
    pthread_mutex_unlock(&g_log_mutex); \
} while(0)

// ============================================================
// Signal tracking for exit diagnostics
// ============================================================
static volatile sig_atomic_t g_last_signal = 0;
static volatile int g_fuse_loop_running = 0;
static volatile uint64_t g_total_ops = 0;  // Total operations counter
static volatile uint64_t g_last_op_time = 0;  // Last operation timestamp

static void fuse_signal_handler(int sig) {
    g_last_signal = sig;
    LOG_WARN("Received signal %d (%s)", sig, strsignal(sig));
}

static void install_signal_handlers(void) {
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = fuse_signal_handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = SA_RESTART;

    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGHUP, &sa, NULL);
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGUSR1, &sa, NULL);
    sigaction(SIGUSR2, &sa, NULL);
    LOG_INFO("Signal handlers installed (SIGTERM/SIGHUP/SIGINT/SIGUSR1/SIGUSR2)");
}

// Check macFUSE device availability
static int check_macfuse_device(void) {
    // Check if /dev/macfuse* exists
    DIR *dev = opendir("/dev");
    if (!dev) {
        LOG_ERROR("Cannot open /dev: errno=%d (%s)", errno, strerror(errno));
        return -1;
    }

    int found = 0;
    struct dirent *entry;
    while ((entry = readdir(dev)) != NULL) {
        if (strncmp(entry->d_name, "macfuse", 7) == 0) {
            found++;
        }
    }
    closedir(dev);
    return found;
}

// Track operation for diagnostics
static inline void track_operation(void) {
    __sync_fetch_and_add(&g_total_ops, 1);
    g_last_op_time = time(NULL);
}

// Forward declaration for collect_exit_diagnostics (defined after g_state)
static void collect_exit_diagnostics(const char *mount_path, int fuse_result, int saved_errno);

// ============================================================
// Eviction exclude list - paths being evicted skip LOCAL, go to EXTERNAL
// ============================================================
#define MAX_EVICTING 256
static struct {
    char *paths[MAX_EVICTING];
    int count;
    pthread_mutex_t lock;
} g_evicting = {
    .paths = {NULL},
    .count = 0,
    .lock = PTHREAD_MUTEX_INITIALIZER
};

static int is_evicting(const char *virtual_path) {
    pthread_mutex_lock(&g_evicting.lock);
    for (int i = 0; i < g_evicting.count; i++) {
        if (g_evicting.paths[i] && strcmp(g_evicting.paths[i], virtual_path) == 0) {
            pthread_mutex_unlock(&g_evicting.lock);
            return 1;
        }
    }
    pthread_mutex_unlock(&g_evicting.lock);
    return 0;
}

void fuse_wrapper_mark_evicting(const char *virtual_path) {
    if (!virtual_path) return;
    pthread_mutex_lock(&g_evicting.lock);
    if (g_evicting.count < MAX_EVICTING) {
        g_evicting.paths[g_evicting.count++] = strdup(virtual_path);
        LOG_DEBUG("Mark evicting: %s (count=%d)", virtual_path, g_evicting.count);
    } else {
        LOG_WARN("Eviction exclude list full (%d), cannot add: %s", MAX_EVICTING, virtual_path);
    }
    pthread_mutex_unlock(&g_evicting.lock);
}

void fuse_wrapper_unmark_evicting(const char *virtual_path) {
    if (!virtual_path) return;
    pthread_mutex_lock(&g_evicting.lock);
    for (int i = 0; i < g_evicting.count; i++) {
        if (g_evicting.paths[i] && strcmp(g_evicting.paths[i], virtual_path) == 0) {
            free(g_evicting.paths[i]);
            // Swap with last element
            g_evicting.paths[i] = g_evicting.paths[g_evicting.count - 1];
            g_evicting.paths[g_evicting.count - 1] = NULL;
            g_evicting.count--;
            LOG_DEBUG("Unmark evicting: %s (count=%d)", virtual_path, g_evicting.count);
            break;
        }
    }
    pthread_mutex_unlock(&g_evicting.lock);
}

void fuse_wrapper_clear_evicting(void) {
    pthread_mutex_lock(&g_evicting.lock);
    for (int i = 0; i < g_evicting.count; i++) {
        free(g_evicting.paths[i]);
        g_evicting.paths[i] = NULL;
    }
    g_evicting.count = 0;
    LOG_INFO("Eviction exclude list cleared");
    pthread_mutex_unlock(&g_evicting.lock);
}

// ============================================================
// Concurrent open file limiter - prevents FUSE resource exhaustion
// ============================================================
#define MAX_CONCURRENT_OPENS 256
static volatile int g_open_count = 0;
static pthread_mutex_t g_open_mutex = PTHREAD_MUTEX_INITIALIZER;

static int acquire_open_slot(void) {
    pthread_mutex_lock(&g_open_mutex);
    if (g_open_count >= MAX_CONCURRENT_OPENS) {
        pthread_mutex_unlock(&g_open_mutex);
        LOG_WARN("Max concurrent opens reached (%d), returning EMFILE", MAX_CONCURRENT_OPENS);
        return -1;
    }
    g_open_count++;
    pthread_mutex_unlock(&g_open_mutex);
    return 0;
}

static void release_open_slot(void) {
    pthread_mutex_lock(&g_open_mutex);
    if (g_open_count > 0) {
        g_open_count--;
    }
    pthread_mutex_unlock(&g_open_mutex);
}

// ============================================================
// Path depth check - POSIX ELOOP protection
// ============================================================
#define MAX_PATH_DEPTH 40  // macOS MAXSYMLINKS=32, allow some headroom

static int path_depth(const char *path) {
    if (!path || path[0] == '\0') return 0;
    int depth = 0;
    for (const char *p = path; *p; p++) {
        if (*p == '/') depth++;
    }
    // "/a/b/c" has 3 slashes but depth 3 components
    // "/" has 1 slash but depth 0 (root)
    if (path[0] == '/' && path[1] == '\0') return 0;
    return depth;
}

static inline int check_path_depth(const char *path) {
    if (path_depth(path) > MAX_PATH_DEPTH) {
        LOG_WARN("Path depth exceeds limit (%d): %.120s...", MAX_PATH_DEPTH, path);
        return -ELOOP;
    }
    return 0;
}

// ============================================================
// Global state
// ============================================================
static struct {
    char *mount_path;           // Mount point path
    char *local_dir;            // Local directory path
    char *external_dir;         // External directory path (can be NULL)
    int is_mounted;             // Whether mounted
    int external_offline;       // Whether external is offline
    int readonly;               // Whether read-only mode
    int index_ready;            // Whether index is ready (pre-mount blocking)
    uid_t owner_uid;            // Mount point owner UID
    gid_t owner_gid;            // Mount point owner GID
    struct fuse *fuse;          // FUSE instance
    struct fuse_chan *chan;     // FUSE channel
    pthread_mutex_t lock;       // State lock
} g_state = {
    .mount_path = NULL,
    .local_dir = NULL,
    .external_dir = NULL,
    .is_mounted = 0,
    .external_offline = 0,
    .readonly = 0,
    .index_ready = 0,           // Initially not ready, blocks all access
    .owner_uid = 0,
    .owner_gid = 0,
    .fuse = NULL,
    .chan = NULL,
    .lock = PTHREAD_MUTEX_INITIALIZER
};

// ============================================================
// Callbacks for Swift layer - DB tree updates
// ============================================================
static FuseCallbacks g_callbacks = {
    .on_file_created = NULL,
    .on_file_deleted = NULL,
    .on_file_written = NULL,
    .on_file_read = NULL,
    .on_file_renamed = NULL
};

// ============================================================
// Async callback queue - dispatch callbacks without blocking FUSE
// ============================================================
#define CALLBACK_QUEUE_SIZE 4096

typedef enum {
    CB_TYPE_CREATED,
    CB_TYPE_DELETED,
    CB_TYPE_WRITTEN,
    CB_TYPE_READ,
    CB_TYPE_RENAMED
} CallbackType;

typedef struct {
    CallbackType type;
    char path[1024];
    char path2[1024];  // For rename: to_path
    int is_directory;
} CallbackItem;

static struct {
    CallbackItem items[CALLBACK_QUEUE_SIZE];
    volatile int head;
    volatile int tail;
    pthread_mutex_t lock;
    pthread_cond_t cond;
    pthread_t thread;
    volatile int running;
} g_callback_queue = {
    .head = 0,
    .tail = 0,
    .lock = PTHREAD_MUTEX_INITIALIZER,
    .cond = PTHREAD_COND_INITIALIZER,
    .thread = 0,
    .running = 0
};

// Callback statistics for diagnostics
static volatile uint64_t g_cb_queued = 0;
static volatile uint64_t g_cb_processed = 0;
static volatile uint64_t g_cb_dropped = 0;

// ============================================================
// Pending delete set - hide deleted files from readdir until EXTERNAL is cleaned
// This prevents "ghost" files from appearing after delete
// ============================================================
#define PENDING_DELETE_SIZE 1024

static struct {
    char *paths[PENDING_DELETE_SIZE];
    int count;
    pthread_mutex_t lock;
} g_pending_delete = {
    .count = 0,
    .lock = PTHREAD_MUTEX_INITIALIZER
};

// Add a path to pending delete set (called before delete)
static void pending_delete_add(const char *path) {
    pthread_mutex_lock(&g_pending_delete.lock);

    // Check if already exists
    for (int i = 0; i < g_pending_delete.count; i++) {
        if (g_pending_delete.paths[i] && strcmp(g_pending_delete.paths[i], path) == 0) {
            pthread_mutex_unlock(&g_pending_delete.lock);
            return;
        }
    }

    // Add new entry (evict oldest if full)
    if (g_pending_delete.count >= PENDING_DELETE_SIZE) {
        free(g_pending_delete.paths[0]);
        memmove(&g_pending_delete.paths[0], &g_pending_delete.paths[1],
                (PENDING_DELETE_SIZE - 1) * sizeof(char*));
        g_pending_delete.count = PENDING_DELETE_SIZE - 1;
    }

    g_pending_delete.paths[g_pending_delete.count++] = strdup(path);
    pthread_mutex_unlock(&g_pending_delete.lock);
}

// Check if a full path is pending delete (for readdir filtering)
// Returns 1 if the given full path (e.g. "/foo/bar") is pending delete
static int pending_delete_contains(const char *full_path) {
    pthread_mutex_lock(&g_pending_delete.lock);
    for (int i = 0; i < g_pending_delete.count; i++) {
        if (g_pending_delete.paths[i] && strcmp(g_pending_delete.paths[i], full_path) == 0) {
            pthread_mutex_unlock(&g_pending_delete.lock);
            return 1;
        }
    }
    pthread_mutex_unlock(&g_pending_delete.lock);
    return 0;
}

// Remove a path from pending delete set (called after successful external delete or timeout)
static void pending_delete_remove(const char *path) {
    pthread_mutex_lock(&g_pending_delete.lock);
    for (int i = 0; i < g_pending_delete.count; i++) {
        if (g_pending_delete.paths[i] && strcmp(g_pending_delete.paths[i], path) == 0) {
            free(g_pending_delete.paths[i]);
            memmove(&g_pending_delete.paths[i], &g_pending_delete.paths[i + 1],
                    (g_pending_delete.count - i - 1) * sizeof(char*));
            g_pending_delete.count--;
            break;
        }
    }
    pthread_mutex_unlock(&g_pending_delete.lock);
}

// Clear all pending deletes (called on unmount)
static void pending_delete_clear(void) {
    pthread_mutex_lock(&g_pending_delete.lock);
    for (int i = 0; i < g_pending_delete.count; i++) {
        free(g_pending_delete.paths[i]);
        g_pending_delete.paths[i] = NULL;
    }
    g_pending_delete.count = 0;
    pthread_mutex_unlock(&g_pending_delete.lock);
}

// ============================================================
// Syncing Files Lock (files being synced to external - read-only)
// ============================================================

#define SYNCING_FILES_SIZE 1024

static struct {
    char *paths[SYNCING_FILES_SIZE];
    int count;
    pthread_mutex_t lock;
} g_syncing_files = {
    .count = 0,
    .lock = PTHREAD_MUTEX_INITIALIZER
};

// Add a path to syncing files set (blocks write/delete during sync)
static void syncing_files_add(const char *path) {
    pthread_mutex_lock(&g_syncing_files.lock);

    // Check if already exists
    for (int i = 0; i < g_syncing_files.count; i++) {
        if (g_syncing_files.paths[i] && strcmp(g_syncing_files.paths[i], path) == 0) {
            pthread_mutex_unlock(&g_syncing_files.lock);
            return;
        }
    }

    // Add new entry (evict oldest if full)
    if (g_syncing_files.count >= SYNCING_FILES_SIZE) {
        LOG_WARN("syncing_files full, evicting oldest entry");
        free(g_syncing_files.paths[0]);
        memmove(&g_syncing_files.paths[0], &g_syncing_files.paths[1],
                (SYNCING_FILES_SIZE - 1) * sizeof(char*));
        g_syncing_files.count = SYNCING_FILES_SIZE - 1;
    }

    g_syncing_files.paths[g_syncing_files.count++] = strdup(path);
    LOG_DEBUG("syncing_files_add: %s (count=%d)", path, g_syncing_files.count);
    pthread_mutex_unlock(&g_syncing_files.lock);
}

// Check if a path is currently syncing (blocks write/truncate/delete)
static int syncing_files_contains(const char *path) {
    pthread_mutex_lock(&g_syncing_files.lock);
    for (int i = 0; i < g_syncing_files.count; i++) {
        if (g_syncing_files.paths[i] && strcmp(g_syncing_files.paths[i], path) == 0) {
            pthread_mutex_unlock(&g_syncing_files.lock);
            return 1;
        }
    }
    pthread_mutex_unlock(&g_syncing_files.lock);
    return 0;
}

// Remove a path from syncing files set (sync completed)
static void syncing_files_remove(const char *path) {
    pthread_mutex_lock(&g_syncing_files.lock);
    for (int i = 0; i < g_syncing_files.count; i++) {
        if (g_syncing_files.paths[i] && strcmp(g_syncing_files.paths[i], path) == 0) {
            free(g_syncing_files.paths[i]);
            memmove(&g_syncing_files.paths[i], &g_syncing_files.paths[i + 1],
                    (g_syncing_files.count - i - 1) * sizeof(char*));
            g_syncing_files.count--;
            LOG_DEBUG("syncing_files_remove: %s (count=%d)", path, g_syncing_files.count);
            break;
        }
    }
    pthread_mutex_unlock(&g_syncing_files.lock);
}

// Clear all syncing files (called on unmount)
static void syncing_files_clear(void) {
    pthread_mutex_lock(&g_syncing_files.lock);
    for (int i = 0; i < g_syncing_files.count; i++) {
        free(g_syncing_files.paths[i]);
        g_syncing_files.paths[i] = NULL;
    }
    g_syncing_files.count = 0;
    pthread_mutex_unlock(&g_syncing_files.lock);
}

// ============================================================
// Public API for Swift to lock/unlock files during sync
// ============================================================

void fuse_wrapper_sync_lock(const char *path) {
    if (path) {
        syncing_files_add(path);
    }
}

void fuse_wrapper_sync_unlock(const char *path) {
    if (path) {
        syncing_files_remove(path);
    }
}

void fuse_wrapper_sync_unlock_all(void) {
    syncing_files_clear();
}

// Callback worker thread - processes callbacks asynchronously
static void* callback_worker(void *arg) {
    (void)arg;
    LOG_INFO("Callback worker thread started");

    while (g_callback_queue.running) {
        CallbackItem item;
        int has_item = 0;

        pthread_mutex_lock(&g_callback_queue.lock);

        // Wait for items or shutdown
        while (g_callback_queue.head == g_callback_queue.tail && g_callback_queue.running) {
            // Timeout wait to allow checking running flag
            struct timespec ts;
            clock_gettime(CLOCK_REALTIME, &ts);
            ts.tv_sec += 1;  // 1 second timeout
            pthread_cond_timedwait(&g_callback_queue.cond, &g_callback_queue.lock, &ts);
        }

        if (g_callback_queue.head != g_callback_queue.tail) {
            item = g_callback_queue.items[g_callback_queue.tail];
            g_callback_queue.tail = (g_callback_queue.tail + 1) % CALLBACK_QUEUE_SIZE;
            has_item = 1;
        }

        pthread_mutex_unlock(&g_callback_queue.lock);

        if (has_item) {
            // Process callback outside the lock
            switch (item.type) {
                case CB_TYPE_CREATED:
                    if (g_callbacks.on_file_created) {
                        g_callbacks.on_file_created(item.path, item.path2, item.is_directory);
                    }
                    break;
                case CB_TYPE_DELETED:
                    if (g_callbacks.on_file_deleted) {
                        g_callbacks.on_file_deleted(item.path, item.is_directory);
                    }
                    break;
                case CB_TYPE_WRITTEN:
                    if (g_callbacks.on_file_written) {
                        g_callbacks.on_file_written(item.path);
                    }
                    break;
                case CB_TYPE_READ:
                    if (g_callbacks.on_file_read) {
                        g_callbacks.on_file_read(item.path);
                    }
                    break;
                case CB_TYPE_RENAMED:
                    if (g_callbacks.on_file_renamed) {
                        g_callbacks.on_file_renamed(item.path, item.path2, item.is_directory);
                    }
                    break;
            }
            __sync_fetch_and_add(&g_cb_processed, 1);
        }
    }

    LOG_INFO("Callback worker thread exiting (processed=%llu, dropped=%llu)",
             (unsigned long long)g_cb_processed, (unsigned long long)g_cb_dropped);
    return NULL;
}

// Queue a callback for async processing (returns immediately, never blocks FUSE)
static void queue_callback(CallbackType type, const char *path, const char *path2, int is_dir) {
    pthread_mutex_lock(&g_callback_queue.lock);

    int next_head = (g_callback_queue.head + 1) % CALLBACK_QUEUE_SIZE;
    if (next_head == g_callback_queue.tail) {
        // Queue full - drop oldest item to make room (avoid blocking)
        g_callback_queue.tail = (g_callback_queue.tail + 1) % CALLBACK_QUEUE_SIZE;
        __sync_fetch_and_add(&g_cb_dropped, 1);
        if (g_cb_dropped % 100 == 1) {
            LOG_WARN("Callback queue overflow! dropped=%llu", (unsigned long long)g_cb_dropped);
        }
    }

    CallbackItem *item = &g_callback_queue.items[g_callback_queue.head];
    item->type = type;
    item->is_directory = is_dir;
    if (path) {
        strncpy(item->path, path, sizeof(item->path) - 1);
        item->path[sizeof(item->path) - 1] = '\0';
    } else {
        item->path[0] = '\0';
    }
    if (path2) {
        strncpy(item->path2, path2, sizeof(item->path2) - 1);
        item->path2[sizeof(item->path2) - 1] = '\0';
    } else {
        item->path2[0] = '\0';
    }

    g_callback_queue.head = next_head;
    __sync_fetch_and_add(&g_cb_queued, 1);

    pthread_cond_signal(&g_callback_queue.cond);
    pthread_mutex_unlock(&g_callback_queue.lock);
}

// Start callback worker thread
static void start_callback_worker(void) {
    if (g_callback_queue.running) return;

    g_callback_queue.running = 1;
    g_callback_queue.head = 0;
    g_callback_queue.tail = 0;
    g_cb_queued = 0;
    g_cb_processed = 0;
    g_cb_dropped = 0;

    if (pthread_create(&g_callback_queue.thread, NULL, callback_worker, NULL) != 0) {
        LOG_ERROR("Failed to create callback worker thread!");
        g_callback_queue.running = 0;
    }
}

// Stop callback worker thread
static void stop_callback_worker(void) {
    if (!g_callback_queue.running) return;

    g_callback_queue.running = 0;

    pthread_mutex_lock(&g_callback_queue.lock);
    pthread_cond_signal(&g_callback_queue.cond);
    pthread_mutex_unlock(&g_callback_queue.lock);

    pthread_join(g_callback_queue.thread, NULL);

    LOG_INFO("Callback worker stopped. Stats: queued=%llu, processed=%llu, dropped=%llu",
             (unsigned long long)g_cb_queued, (unsigned long long)g_cb_processed,
             (unsigned long long)g_cb_dropped);
}

void fuse_wrapper_set_callbacks(const FuseCallbacks *callbacks) {
    if (callbacks) {
        g_callbacks = *callbacks;
        LOG_INFO("Callbacks registered: created=%p, deleted=%p, written=%p, read=%p, renamed=%p",
                 (void*)g_callbacks.on_file_created,
                 (void*)g_callbacks.on_file_deleted,
                 (void*)g_callbacks.on_file_written,
                 (void*)g_callbacks.on_file_read,
                 (void*)g_callbacks.on_file_renamed);
    } else {
        memset(&g_callbacks, 0, sizeof(g_callbacks));
        LOG_INFO("Callbacks cleared");
    }
}

// Helper macros for invoking callbacks ASYNCHRONOUSLY (never blocks FUSE thread)
#define NOTIFY_FILE_CREATED(vpath, lpath, is_dir) \
    do { \
        queue_callback(CB_TYPE_CREATED, vpath, lpath, is_dir); \
        LOG_DEBUG("CB queued: created %s (dir=%d)", vpath, is_dir); \
    } while(0)

#define NOTIFY_FILE_DELETED(vpath, is_dir) \
    do { \
        queue_callback(CB_TYPE_DELETED, vpath, NULL, is_dir); \
        LOG_DEBUG("CB queued: deleted %s (dir=%d)", vpath, is_dir); \
    } while(0)

#define NOTIFY_FILE_WRITTEN(vpath) \
    do { \
        queue_callback(CB_TYPE_WRITTEN, vpath, NULL, 0); \
    } while(0)

// File read notifications - Swift layer implements throttled batch updates
#define NOTIFY_FILE_READ(vpath) \
    do { \
        queue_callback(CB_TYPE_READ, vpath, NULL, 0); \
    } while(0)

#define NOTIFY_FILE_RENAMED(from, to, is_dir) \
    do { \
        queue_callback(CB_TYPE_RENAMED, from, to, is_dir); \
        LOG_DEBUG("CB queued: renamed %s -> %s (dir=%d)", from, to, is_dir); \
    } while(0)

// ============================================================
// Helper functions
// ============================================================

// Index not ready check macro - blocks non-root directory access
// When index is not ready, returns EBUSY (device busy), telling apps to retry later
#define CHECK_INDEX_READY_FOR_PATH(path) \
    do { \
        if (!g_state.index_ready && strcmp(path, "/") != 0) { \
            LOG_DEBUG("Index not ready, blocking access: %s", path); \
            return -EBUSY; \
        } \
    } while (0)

// Index not ready check - for all operations except root directory
#define CHECK_INDEX_READY() \
    do { \
        if (!g_state.index_ready) { \
            LOG_DEBUG("Index not ready, blocking operation"); \
            return -EBUSY; \
        } \
    } while (0)

// Collect detailed exit diagnostics (implementation after g_state is defined)
static void collect_exit_diagnostics(const char *mount_path, int fuse_result, int saved_errno) {
    LOG_INFO("========== FUSE EXIT DIAGNOSTICS ==========");

    // Basic exit info
    LOG_INFO("Exit code: %d, errno: %d (%s)", fuse_result, saved_errno, strerror(saved_errno));

    // Signal info
    if (g_last_signal != 0) {
        LOG_WARN("Exit signal: %d (%s)", (int)g_last_signal, strsignal((int)g_last_signal));
    } else {
        LOG_INFO("Exit signal: none");
    }

    // Operation stats
    LOG_INFO("Total ops since mount: %llu", (unsigned long long)g_total_ops);
    if (g_last_op_time > 0) {
        time_t now = time(NULL);
        LOG_INFO("Last op: %lld seconds ago", (long long)(now - g_last_op_time));
    }

    // Callback queue stats
    LOG_INFO("Callback queue: queued=%llu, processed=%llu, dropped=%llu, pending=%d",
             (unsigned long long)g_cb_queued,
             (unsigned long long)g_cb_processed,
             (unsigned long long)g_cb_dropped,
             (int)((g_callback_queue.head - g_callback_queue.tail + CALLBACK_QUEUE_SIZE) % CALLBACK_QUEUE_SIZE));

    // macFUSE device state
    int macfuse_devs = check_macfuse_device();
    LOG_INFO("macFUSE devices in /dev: %d", macfuse_devs);

    // Mount point state
    struct stat mp_stat;
    if (stat(mount_path, &mp_stat) != 0) {
        LOG_WARN("Mount point stat failed: %s (errno=%d %s)", mount_path, errno, strerror(errno));
    } else {
        LOG_INFO("Mount point exists: mode=0x%x, uid=%d, gid=%d",
                 mp_stat.st_mode, mp_stat.st_uid, mp_stat.st_gid);
    }

    // Filesystem type at mount point
    struct statfs fs_stat;
    if (statfs(mount_path, &fs_stat) == 0) {
        LOG_INFO("Filesystem type: %s, flags=0x%x", fs_stat.f_fstypename, fs_stat.f_flags);
    } else {
        LOG_WARN("statfs failed: errno=%d (%s)", errno, strerror(errno));
    }

    // Check FUSE channel state
    if (g_state.chan) {
        LOG_INFO("FUSE channel: valid");
    } else {
        LOG_WARN("FUSE channel: NULL");
    }

    // Interpret common errno values
    switch (saved_errno) {
        case ENODEV:  // 19
            LOG_WARN("ENODEV: macFUSE kernel module may have been unloaded or device disconnected");
            break;
        case ENOTCONN:  // 57
            LOG_WARN("ENOTCONN: FUSE connection lost (kernel-userspace channel broken)");
            break;
        case EINTR:  // 4
            LOG_INFO("EINTR: Interrupted by signal");
            break;
        case EIO:  // 5
            LOG_WARN("EIO: I/O error on FUSE device");
            break;
        case ENOENT:  // 2
            LOG_WARN("ENOENT: Mount point or device no longer exists");
            break;
        default:
            if (saved_errno != 0) {
                LOG_INFO("errno %d: %s", saved_errno, strerror(saved_errno));
            }
            break;
    }

    LOG_INFO("========== END DIAGNOSTICS ==========");
}

// Join paths
static char* join_path(const char *base, const char *path) {
    if (!base || !path) return NULL;

    // Skip leading / from path
    while (*path == '/') path++;

    size_t base_len = strlen(base);
    size_t path_len = strlen(path);

    // Remove trailing / from base
    while (base_len > 0 && base[base_len - 1] == '/') {
        base_len--;
    }

    char *result = malloc(base_len + 1 + path_len + 1);
    if (!result) return NULL;

    memcpy(result, base, base_len);
    result[base_len] = '/';
    strcpy(result + base_len + 1, path);

    return result;
}

// Get local path
static char* get_local_path(const char *virtual_path) {
    return join_path(g_state.local_dir, virtual_path);
}

// Get external path
static char* get_external_path(const char *virtual_path) {
    if (!g_state.external_dir || g_state.external_offline) {
        return NULL;
    }
    return join_path(g_state.external_dir, virtual_path);
}

// Resolve actual path (prefer local, then external)
// If path is in eviction exclude list, skip LOCAL and go directly to EXTERNAL
static char* resolve_actual_path(const char *virtual_path) {
    int evicting = is_evicting(virtual_path);

    if (!evicting) {
        char *local = get_local_path(virtual_path);
        if (local) {
            struct stat st;
            if (stat(local, &st) == 0) {
                return local;
            }
            free(local);
        }
    }

    char *external = get_external_path(virtual_path);
    if (external) {
        struct stat st;
        if (stat(external, &st) == 0) {
            return external;
        }
        free(external);
    }

    return NULL;
}

// Fix ownership of a file/directory to the mount owner (user)
static void fix_ownership(const char *path) {
    if (g_state.owner_uid != 0 || g_state.owner_gid != 0) {
        lchown(path, g_state.owner_uid, g_state.owner_gid);
    }
}

// Ensure parent directory exists
static int ensure_parent_directory(const char *path) {
    char *path_copy = strdup(path);
    if (!path_copy) return -ENOMEM;

    char *parent = dirname(path_copy);

    struct stat st;
    if (stat(parent, &st) == 0) {
        free(path_copy);
        return 0;  // Parent directory already exists
    }

    // Recursively create
    int result = 0;
    char *p = path_copy;

    // Skip leading /
    if (*p == '/') p++;

    while (*p) {
        if (*p == '/') {
            *p = '\0';
            if (strlen(path_copy) > 0 && stat(path_copy, &st) != 0) {
                if (mkdir(path_copy, 0755) != 0 && errno != EEXIST) {
                    result = -errno;
                    break;
                }
                fix_ownership(path_copy);
            }
            *p = '/';
        }
        p++;
    }

    free(path_copy);
    return result;
}

// Check if file should be excluded
static int should_exclude(const char *name) {
    if (!name) return 1;

    const char *exclude_patterns[] = {
        ".DS_Store",
        ".Spotlight-V100",
        ".Trashes",
        ".fseventsd",
        ".TemporaryItems",
        ".FUSE",
        NULL
    };

    for (int i = 0; exclude_patterns[i]; i++) {
        if (strcmp(name, exclude_patterns[i]) == 0) {
            return 1;
        }
    }

    // Check for ._ prefixed files
    if (strncmp(name, "._", 2) == 0) {
        return 1;
    }

    return 0;
}

// ============================================================
// FUSE callback functions
// ============================================================

// getattr: get file attributes
static int root_getattr_logged = 0;  // Avoid log flooding
static int index_not_ready_logged = 0;  // Avoid index-not-ready log flooding

static int dmsa_getattr(const char *path, struct stat *stbuf) {
    track_operation();
    int depth_err = check_path_depth(path);
    if (depth_err) return depth_err;

    LOG_DEBUG("getattr: %s", path);

    memset(stbuf, 0, sizeof(struct stat));

    // Root directory special handling - allow access even when index is not ready
    if (strcmp(path, "/") == 0) {
        stbuf->st_mode = S_IFDIR | 0755;
        stbuf->st_nlink = 2;
        stbuf->st_uid = g_state.owner_uid;
        stbuf->st_gid = g_state.owner_gid;
        stbuf->st_atime = stbuf->st_mtime = stbuf->st_ctime = time(NULL);

        // Log on first root directory access
        if (!root_getattr_logged) {
            LOG_INFO("getattr(/): returning uid=%d, gid=%d, mode=0755",
                     g_state.owner_uid, g_state.owner_gid);
            root_getattr_logged = 1;
        }
        return 0;
    }

    // Block non-root directory access when index is not ready
    if (!g_state.index_ready) {
        if (!index_not_ready_logged) {
            LOG_INFO("Index not ready, blocking file access (returning EBUSY)");
            index_not_ready_logged = 1;
        }
        return -EBUSY;
    }

    char *actual_path = resolve_actual_path(path);
    if (!actual_path) {
        LOG_DEBUG("getattr: ENOENT for %s", path);
        return -ENOENT;
    }

    int res = stat(actual_path, stbuf);
    if (res == -1) {
        int err = errno;
        LOG_WARN("getattr: stat failed for %s (actual=%s): errno=%d (%s)", path, actual_path, err, strerror(err));
        free(actual_path);
        return -err;
    }
    free(actual_path);

    // Always report files as owned by the mount owner
    stbuf->st_uid = g_state.owner_uid;
    stbuf->st_gid = g_state.owner_gid;

    // Normalize permissions: VFS files should be readable by owner
    // Underlying files might have restrictive permissions (e.g., 600 from old system)
    // but VFS should present them with standard permissions
    if (S_ISDIR(stbuf->st_mode)) {
        // Directories: rwxr-xr-x (755)
        stbuf->st_mode = S_IFDIR | 0755;
    } else {
        // Files: rw-r--r-- (644) - preserve execute bit if present
        mode_t exec_bit = stbuf->st_mode & S_IXUSR;
        stbuf->st_mode = S_IFREG | 0644 | exec_bit;
    }

    return 0;
}

// readdir: read directory contents (smart merge LOCAL + EXTERNAL)
// NOTE: We pass NULL for stat in filler() - this is the standard approach:
//   - Only return entry names, no file attributes
//   - Applications (ls, etc.) will call getattr() separately for each entry
//   - This avoids symlink resolution during readdir, preventing deadlocks
//   - Combined with fuse_loop_mt(), handles symlinks pointing back to VFS
static int dmsa_readdir(const char *path, void *buf, fuse_fill_dir_t filler,
                        off_t offset, struct fuse_file_info *fi) {
    track_operation();
    (void) offset;
    (void) fi;

    int depth_err = check_path_depth(path);
    if (depth_err) return depth_err;

    LOG_DEBUG("readdir: %s", path);

    // Block directory reads when index is not ready (including root)
    // Note: Root must also be blocked since Finder will try to list contents
    if (!g_state.index_ready) {
        // Allow root directory access but return empty listing
        if (strcmp(path, "/") == 0) {
            filler(buf, ".", NULL, 0);
            filler(buf, "..", NULL, 0);
            // Return no files, so Finder sees an empty directory
            return 0;
        }
        return -EBUSY;
    }

    // Add . and ..
    filler(buf, ".", NULL, 0);
    filler(buf, "..", NULL, 0);

    // Heap-allocated deduplication table (supports larger directories)
    #define MAX_READDIR_ENTRIES 8192
    char **seen_names = calloc(MAX_READDIR_ENTRIES, sizeof(char*));
    if (!seen_names) {
        LOG_ERROR("readdir: failed to allocate seen_names table");
        return -ENOMEM;
    }
    int seen_count = 0;

    // Helper buffer for building full virtual paths
    char full_vpath[2048];
    int path_is_root = (strcmp(path, "/") == 0);

    // Read from local directory
    char *local = get_local_path(path);
    if (local) {
        DIR *dp = opendir(local);
        if (dp) {
            struct dirent *de;
            while ((de = readdir(dp)) != NULL) {
                if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0) {
                    continue;
                }
                if (should_exclude(de->d_name)) {
                    continue;
                }

                // Build full virtual path for pending delete check
                if (path_is_root) {
                    snprintf(full_vpath, sizeof(full_vpath), "/%s", de->d_name);
                } else {
                    snprintf(full_vpath, sizeof(full_vpath), "%s/%s", path, de->d_name);
                }

                // Skip if in pending delete set
                if (pending_delete_contains(full_vpath)) {
                    continue;
                }

                // Check if already added
                int found = 0;
                for (int i = 0; i < seen_count; i++) {
                    if (seen_names[i] && strcmp(seen_names[i], de->d_name) == 0) {
                        found = 1;
                        break;
                    }
                }

                if (!found && seen_count < MAX_READDIR_ENTRIES) {
                    seen_names[seen_count++] = strdup(de->d_name);
                    filler(buf, de->d_name, NULL, 0);
                }
            }
            closedir(dp);
        }
        free(local);
    }

    // Read from external directory (if online)
    char *external = get_external_path(path);
    if (external) {
        DIR *dp = opendir(external);
        if (dp) {
            struct dirent *de;
            while ((de = readdir(dp)) != NULL) {
                if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0) {
                    continue;
                }
                if (should_exclude(de->d_name)) {
                    continue;
                }

                // Build full virtual path for pending delete check
                if (path_is_root) {
                    snprintf(full_vpath, sizeof(full_vpath), "/%s", de->d_name);
                } else {
                    snprintf(full_vpath, sizeof(full_vpath), "%s/%s", path, de->d_name);
                }

                // Skip if in pending delete set (important: hides EXTERNAL files that couldn't be deleted)
                if (pending_delete_contains(full_vpath)) {
                    continue;
                }

                // Check if already added
                int found = 0;
                for (int i = 0; i < seen_count; i++) {
                    if (seen_names[i] && strcmp(seen_names[i], de->d_name) == 0) {
                        found = 1;
                        break;
                    }
                }

                if (!found && seen_count < MAX_READDIR_ENTRIES) {
                    seen_names[seen_count++] = strdup(de->d_name);
                    filler(buf, de->d_name, NULL, 0);
                }
            }
            closedir(dp);
        }
        free(external);
    }

    // Cleanup heap-allocated table
    for (int i = 0; i < seen_count; i++) {
        free(seen_names[i]);
    }
    free(seen_names);

    return 0;
}

// open: open file
static int dmsa_open(const char *path, struct fuse_file_info *fi) {
    track_operation();
    int depth_err = check_path_depth(path);
    if (depth_err) return depth_err;

    LOG_DEBUG("open: %s, flags=%d", path, fi->flags);

    // Block file open when index is not ready
    CHECK_INDEX_READY();

    // Limit concurrent open files to prevent FUSE resource exhaustion
    if (acquire_open_slot() < 0) {
        return -EMFILE;
    }

    char *actual_path = resolve_actual_path(path);

    if (!actual_path) {
        // File doesn't exist, check if in create mode
        if ((fi->flags & O_CREAT) || (fi->flags & O_WRONLY) || (fi->flags & O_RDWR)) {
            actual_path = get_local_path(path);
            if (!actual_path) {
                return -ENOENT;
            }

            // Ensure parent directory exists
            int res = ensure_parent_directory(actual_path);
            if (res != 0) {
                free(actual_path);
                return res;
            }

            // Create empty file
            int fd = open(actual_path, O_CREAT | O_WRONLY, 0644);
            if (fd == -1) {
                int err = errno;
                free(actual_path);
                return -err;
            }
            close(fd);
            fix_ownership(actual_path);
        } else {
            return -ENOENT;
        }
    }

    // If write mode and actual path is external, copy to local first
    char *local = get_local_path(path);
    if (local && ((fi->flags & O_WRONLY) || (fi->flags & O_RDWR))) {
        if (strcmp(actual_path, local) != 0) {
            // Actual path is external, copy to local
            ensure_parent_directory(local);

            // Simple file copy
            int src_fd = open(actual_path, O_RDONLY);
            if (src_fd != -1) {
                int dst_fd = open(local, O_CREAT | O_WRONLY | O_TRUNC, 0644);
                if (dst_fd != -1) {
                    char copy_buf[8192];
                    ssize_t bytes;
                    while ((bytes = read(src_fd, copy_buf, sizeof(copy_buf))) > 0) {
                        write(dst_fd, copy_buf, bytes);
                    }
                    close(dst_fd);
                }
                close(src_fd);
            }

            // Use local path
            free(actual_path);
            actual_path = local;
            local = NULL;
        }
    }

    // Try to open file
    int fd = open(actual_path, fi->flags);
    if (fd == -1) {
        int err = errno;
        LOG_WARN("open: failed for %s (actual=%s, flags=%d): errno=%d (%s)", path, actual_path, fi->flags, err, strerror(err));
        free(actual_path);
        if (local) free(local);
        release_open_slot();  // Release the slot on failure
        return -err;
    }

    fi->fh = fd;

    free(actual_path);
    if (local) free(local);

    return 0;
}

// read: read file contents
static int dmsa_read(const char *path, char *buf, size_t size, off_t offset,
                     struct fuse_file_info *fi) {
    track_operation();
    LOG_DEBUG("read: %s, size=%zu, offset=%lld", path, size, offset);

    int fd = fi->fh;
    if (fd <= 0) {
        return -EBADF;
    }

    int res = pread(fd, buf, size, offset);
    if (res == -1) {
        return -errno;
    }

    return res;
}

// write: write file contents
static int dmsa_write(const char *path, const char *buf, size_t size, off_t offset,
                      struct fuse_file_info *fi) {
    track_operation();
    LOG_DEBUG("write: %s, size=%zu, offset=%lld", path, size, offset);

    if (g_state.readonly) {
        return -EROFS;
    }

    // Block write if file is being synced
    if (syncing_files_contains(path)) {
        LOG_DEBUG("write blocked: %s is syncing", path);
        return -EBUSY;
    }

    int fd = fi->fh;
    if (fd <= 0) {
        // If no fh, try writing directly to local file
        char *local = get_local_path(path);
        if (!local) {
            return -ENOENT;
        }

        ensure_parent_directory(local);

        fd = open(local, O_WRONLY | O_CREAT, 0644);
        free(local);

        if (fd == -1) {
            return -errno;
        }

        int res = pwrite(fd, buf, size, offset);
        int err = errno;
        close(fd);

        if (res == -1) {
            return -err;
        }
        return res;
    }

    int res = pwrite(fd, buf, size, offset);
    if (res == -1) {
        return -errno;
    }

    return res;
}

// release: close file
static int dmsa_release(const char *path, struct fuse_file_info *fi) {
    LOG_DEBUG("release: %s", path);

    if (fi->fh > 0) {
        close(fi->fh);
    }

    // Release concurrent open slot
    release_open_slot();

    // Notify Swift layer if file was written (check flags)
    // fi->flags contains open flags: O_WRONLY, O_RDWR indicate write
    if ((fi->flags & O_WRONLY) || (fi->flags & O_RDWR)) {
        NOTIFY_FILE_WRITTEN(path);
    }

    return 0;
}

// create: create file
static int dmsa_create(const char *path, mode_t mode, struct fuse_file_info *fi) {
    LOG_DEBUG("create: %s, mode=%o", path, mode);

    // Block file creation when index is not ready
    CHECK_INDEX_READY();

    if (g_state.readonly) {
        return -EROFS;
    }

    char *local = get_local_path(path);
    if (!local) {
        return -ENOMEM;
    }

    int res = ensure_parent_directory(local);
    if (res != 0) {
        free(local);
        return res;
    }

    int fd = open(local, O_CREAT | O_WRONLY | O_TRUNC, mode);

    if (fd == -1) {
        int err = errno;
        free(local);
        return -err;
    }

    fix_ownership(local);

    // Notify Swift layer - file created
    NOTIFY_FILE_CREATED(path, local, 0);

    free(local);

    fi->fh = fd;
    return 0;
}

// unlink: delete file
// Order: 1. Add to pending delete 2. Notify Swift 3. Delete LOCAL 4. Delete EXTERNAL 5. Remove from pending
static int dmsa_unlink(const char *path) {
    LOG_DEBUG("unlink: %s", path);

    if (g_state.readonly) {
        return -EROFS;
    }

    // Block delete if file is being synced
    if (syncing_files_contains(path)) {
        LOG_DEBUG("unlink blocked: %s is syncing", path);
        return -EBUSY;
    }

    // Step 1: Add to pending delete set (hides from readdir immediately)
    pending_delete_add(path);

    // Step 2: Notify Swift layer (async, updates memory cache + DB)
    NOTIFY_FILE_DELETED(path, 0);

    int result = 0;
    int external_deleted = 0;

    // Step 3: Delete local copy
    char *local = get_local_path(path);
    if (local) {
        if (unlink(local) == -1 && errno != ENOENT) {
            result = -errno;
            LOG_WARN("unlink local failed: %s, errno=%d", local, errno);
        }
        free(local);
    }

    // Step 4: Delete external copy (best effort)
    char *external = get_external_path(path);
    if (external) {
        if (unlink(external) == 0 || errno == ENOENT) {
            external_deleted = 1;
        } else {
            LOG_DEBUG("unlink external failed: %s, errno=%d (will stay in pending)", external, errno);
        }
        free(external);
    } else {
        external_deleted = 1;  // No external path means nothing to delete
    }

    // Step 5: Remove from pending delete if external was deleted successfully
    // If external delete failed, keep in pending so readdir continues to hide it
    if (external_deleted) {
        pending_delete_remove(path);
    }

    return result;
}

// mkdir: create directory
static int dmsa_mkdir(const char *path, mode_t mode) {
    LOG_DEBUG("mkdir: %s, mode=%o", path, mode);

    if (g_state.readonly) {
        return -EROFS;
    }

    char *local = get_local_path(path);
    if (!local) {
        return -ENOMEM;
    }

    int res = ensure_parent_directory(local);
    if (res != 0) {
        free(local);
        return res;
    }

    res = mkdir(local, mode);

    if (res == -1) {
        int err = errno;
        free(local);
        return -err;
    }

    fix_ownership(local);

    // Notify Swift layer - directory created
    NOTIFY_FILE_CREATED(path, local, 1);

    free(local);

    return 0;
}

// rmdir: remove directory
// Order: 1. Add to pending delete 2. Notify Swift 3. Delete LOCAL 4. Delete EXTERNAL 5. Remove from pending
static int dmsa_rmdir(const char *path) {
    LOG_DEBUG("rmdir: %s", path);

    if (g_state.readonly) {
        return -EROFS;
    }

    // Block delete if directory is being synced
    if (syncing_files_contains(path)) {
        LOG_DEBUG("rmdir blocked: %s is syncing", path);
        return -EBUSY;
    }

    // Step 1: Add to pending delete set (hides from readdir immediately)
    pending_delete_add(path);

    // Step 2: Notify Swift layer (async, updates memory cache + DB)
    NOTIFY_FILE_DELETED(path, 1);

    int result = 0;
    int external_deleted = 0;

    // Step 3: Delete local copy
    char *local = get_local_path(path);
    if (local) {
        if (rmdir(local) == -1 && errno != ENOENT) {
            result = -errno;
            LOG_WARN("rmdir local failed: %s, errno=%d", local, errno);
        }
        free(local);
    }

    // Step 4: Delete external copy (best effort)
    char *external = get_external_path(path);
    if (external) {
        if (rmdir(external) == 0 || errno == ENOENT) {
            external_deleted = 1;
        } else {
            LOG_DEBUG("rmdir external failed: %s, errno=%d (will stay in pending)", external, errno);
        }
        free(external);
    } else {
        external_deleted = 1;  // No external path means nothing to delete
    }

    // Step 5: Remove from pending delete if external was deleted successfully
    if (external_deleted) {
        pending_delete_remove(path);
    }

    return result;
}

// rename: rename file/directory
static int dmsa_rename(const char *from, const char *to) {
    LOG_DEBUG("rename: %s -> %s", from, to);

    if (g_state.readonly) {
        return -EROFS;
    }

    char *local_from = get_local_path(from);
    char *local_to = get_local_path(to);

    if (!local_from || !local_to) {
        if (local_from) free(local_from);
        if (local_to) free(local_to);
        return -ENOMEM;
    }

    int res = ensure_parent_directory(local_to);
    if (res != 0) {
        free(local_from);
        free(local_to);
        return res;
    }

    // If source file is in external directory, copy to local first
    struct stat st;
    if (stat(local_from, &st) != 0) {
        char *external_from = get_external_path(from);
        if (external_from && stat(external_from, &st) == 0) {
            // Copy external file to local
            int src_fd = open(external_from, O_RDONLY);
            if (src_fd != -1) {
                ensure_parent_directory(local_from);
                int dst_fd = open(local_from, O_CREAT | O_WRONLY | O_TRUNC, st.st_mode);
                if (dst_fd != -1) {
                    char copy_buf[8192];
                    ssize_t bytes;
                    while ((bytes = read(src_fd, copy_buf, sizeof(copy_buf))) > 0) {
                        write(dst_fd, copy_buf, bytes);
                    }
                    close(dst_fd);
                    fix_ownership(local_from);
                }
                close(src_fd);
            }
            free(external_from);
        } else {
            if (external_from) free(external_from);
            free(local_from);
            free(local_to);
            return -ENOENT;
        }
    }

    res = rename(local_from, local_to);
    int err = errno;

    free(local_from);
    free(local_to);

    if (res == -1) {
        return -err;
    }

    // Also rename in external directory (if online)
    char *external_from = get_external_path(from);
    char *external_to = get_external_path(to);
    if (external_from && external_to) {
        // Ensure external target directory exists
        char *ext_to_copy = strdup(external_to);
        if (ext_to_copy) {
            char *parent = dirname(ext_to_copy);
            mkdir(parent, 0755);  // Ignore errors
            free(ext_to_copy);
        }
        rename(external_from, external_to);  // Ignore errors
    }
    if (external_from) free(external_from);
    if (external_to) free(external_to);

    // Notify Swift layer - file renamed (check if directory via stat on 'to')
    struct stat to_st;
    char *local_to_check = get_local_path(to);
    int is_dir = 0;
    if (local_to_check) {
        if (stat(local_to_check, &to_st) == 0) {
            is_dir = S_ISDIR(to_st.st_mode);
        }
        free(local_to_check);
    }
    NOTIFY_FILE_RENAMED(from, to, is_dir);

    return 0;
}

// truncate: truncate file
static int dmsa_truncate(const char *path, off_t size) {
    LOG_DEBUG("truncate: %s, size=%lld", path, size);

    if (g_state.readonly) {
        return -EROFS;
    }

    // Block truncate if file is being synced
    if (syncing_files_contains(path)) {
        LOG_DEBUG("truncate blocked: %s is syncing", path);
        return -EBUSY;
    }

    char *local = get_local_path(path);
    if (!local) {
        return -ENOMEM;
    }

    // If not in local, copy from external
    struct stat st;
    if (stat(local, &st) != 0) {
        char *external = get_external_path(path);
        if (external && stat(external, &st) == 0) {
            ensure_parent_directory(local);

            int src_fd = open(external, O_RDONLY);
            if (src_fd != -1) {
                int dst_fd = open(local, O_CREAT | O_WRONLY | O_TRUNC, st.st_mode);
                if (dst_fd != -1) {
                    char copy_buf[8192];
                    ssize_t bytes;
                    while ((bytes = read(src_fd, copy_buf, sizeof(copy_buf))) > 0) {
                        write(dst_fd, copy_buf, bytes);
                    }
                    close(dst_fd);
                }
                close(src_fd);
            }
            free(external);
        }
    }

    int res = truncate(local, size);
    free(local);

    if (res == -1) {
        return -errno;
    }

    return 0;
}

// chmod: change permissions
static int dmsa_chmod(const char *path, mode_t mode) {
    LOG_DEBUG("chmod: %s, mode=%o", path, mode);

    if (g_state.readonly) {
        return -EROFS;
    }

    char *actual = resolve_actual_path(path);
    if (!actual) {
        return -ENOENT;
    }

    int res = chmod(actual, mode);
    int err = errno;
    free(actual);

    if (res == -1) {
        // VFS presents normalized permissions to users (644/755).
        // The underlying file's actual permissions don't matter since Service runs as root.
        // Ignore permission errors to allow Finder copy operations (ditto uses fchmod).
        if (err == EPERM || err == EACCES) {
            LOG_INFO("chmod: %s mode=%o -> EPERM/EACCES ignored", path, mode);
            return 0;
        }
        LOG_WARN("chmod failed: %s, mode=%o, errno=%d (%s)", path, mode, err, strerror(err));
        return -err;
    }

    return 0;
}

// chown: change owner
static int dmsa_chown(const char *path, uid_t uid, gid_t gid) {
    LOG_DEBUG("chown: %s, uid=%d, gid=%d", path, uid, gid);

    if (g_state.readonly) {
        return -EROFS;
    }

    char *actual = resolve_actual_path(path);
    if (!actual) {
        return -ENOENT;
    }

    int res = lchown(actual, uid, gid);
    int err = errno;
    free(actual);

    if (res == -1) {
        // VFS presents all files as owned by the mount point owner.
        // The underlying file's actual owner doesn't matter since Service runs as root.
        // Ignore permission errors to allow Finder copy operations (ditto uses fchown).
        if (err == EPERM || err == EACCES) {
            LOG_INFO("chown: %s uid=%d gid=%d -> EPERM/EACCES ignored", path, uid, gid);
            return 0;
        }
        LOG_WARN("chown failed: %s, uid=%d, gid=%d, errno=%d (%s)", path, uid, gid, err, strerror(err));
        return -err;
    }

    return 0;
}

// utimens: modify timestamps
static int dmsa_utimens(const char *path, const struct timespec ts[2]) {
    LOG_DEBUG("utimens: %s", path);

    char *actual = resolve_actual_path(path);
    if (!actual) {
        return -ENOENT;
    }

    // Use utimensat (macOS 10.13+)
    int res = utimensat(AT_FDCWD, actual, ts, AT_SYMLINK_NOFOLLOW);
    int err = errno;
    free(actual);

    if (res == -1) {
        // Timestamp modification failure shouldn't block file copy operations.
        // Ignore permission errors to allow Finder copy operations.
        if (err == EPERM || err == EACCES) {
            LOG_INFO("utimens: %s -> EPERM/EACCES ignored", path);
            return 0;
        }
        LOG_WARN("utimens failed: %s, errno=%d (%s)", path, err, strerror(err));
        return -err;
    }

    return 0;
}

// statfs: filesystem statistics
static int dmsa_statfs(const char *path, struct statvfs *stbuf) {
    LOG_DEBUG("statfs: %s", path);
    (void)path;

    // Use local directory statistics
    int res = statvfs(g_state.local_dir, stbuf);
    if (res == -1) {
        return -errno;
    }

    return 0;
}

// readlink: read symbolic link
static int dmsa_readlink(const char *path, char *buf, size_t size) {
    int depth_err = check_path_depth(path);
    if (depth_err) return depth_err;

    LOG_DEBUG("readlink: %s", path);

    char *actual = resolve_actual_path(path);
    if (!actual) {
        return -ENOENT;
    }

    ssize_t res = readlink(actual, buf, size - 1);
    free(actual);

    if (res == -1) {
        return -errno;
    }

    buf[res] = '\0';
    return 0;
}

// symlink: create symbolic link
static int dmsa_symlink(const char *target, const char *linkpath) {
    LOG_DEBUG("symlink: %s -> %s", linkpath, target);

    if (g_state.readonly) {
        return -EROFS;
    }

    char *local = get_local_path(linkpath);
    if (!local) {
        return -ENOMEM;
    }

    ensure_parent_directory(local);

    int res = symlink(target, local);

    if (res == -1) {
        int err = errno;
        free(local);
        return -err;
    }

    fix_ownership(local);
    free(local);

    return 0;
}

// access: check access permissions
static int dmsa_access(const char *path, int mask) {
    LOG_DEBUG("access: %s, mask=%d", path, mask);

    // Root directory: always allow
    if (strcmp(path, "/") == 0) {
        return 0;
    }

    // Check if file exists
    char *actual = resolve_actual_path(path);
    if (!actual) {
        return -ENOENT;
    }
    free(actual);

    // VFS presents all files as owned by user with full permissions (mode 0644/0755)
    // Since Service runs as root and handles actual file I/O, we always grant access
    // to existing files. The underlying file permissions don't matter to VFS users.
    //
    // This fixes "permission denied" errors in Finder when copying files that have
    // restrictive permissions (e.g., 600) on the underlying storage.
    return 0;
}

// getxattr: get extended attributes (macOS version)
static int dmsa_getxattr(const char *path, const char *name, char *value, size_t size, uint32_t position) {
    LOG_DEBUG("getxattr: %s, name=%s", path, name);

    char *actual = resolve_actual_path(path);
    if (!actual) {
        return -ENOENT;
    }

    ssize_t res = getxattr(actual, name, value, size, position, XATTR_NOFOLLOW);
    free(actual);

    if (res == -1) {
        int err = errno;
        // For permission errors on underlying storage, report "no such attribute"
        // This allows Finder to proceed with copy operations
        if (err == EPERM || err == EACCES) {
            return -ENOATTR;
        }
        return -err;
    }

    return (int)res;
}

// setxattr: set extended attributes (macOS version)
static int dmsa_setxattr(const char *path, const char *name, const char *value,
                         size_t size, int flags, uint32_t position) {
    LOG_DEBUG("setxattr: %s, name=%s, size=%zu", path, name, size);

    if (g_state.readonly) {
        return -EROFS;
    }

    // For Apple security-related xattrs that can't be set normally, fake success.
    // These include: com.apple.macl (MAC label), com.apple.provenance,
    // com.apple.quarantine, etc. The kernel or security framework manages these.
    // Returning success allows cp/Finder copy to proceed without errors.
    if (strncmp(name, "com.apple.", 10) == 0) {
        // Try to set it, but ignore all errors for com.apple.* attrs
        char *local = get_local_path(path);
        if (local) {
            int res = setxattr(local, name, value, size, position, flags | XATTR_NOFOLLOW);
            if (res == -1) {
                LOG_DEBUG("setxattr: %s name=%s -> ignored (com.apple.* attr)", path, name);
            }
            free(local);
        }
        return 0;  // Always return success for com.apple.* attributes
    }

    char *local = get_local_path(path);
    if (!local) {
        return -ENOMEM;
    }

    int res = setxattr(local, name, value, size, position, flags | XATTR_NOFOLLOW);
    int err = errno;
    free(local);

    if (res == -1) {
        // Extended attribute setting failure shouldn't block file copy operations.
        // Ignore permission errors to allow Finder copy operations (ditto sets xattrs).
        if (err == EPERM || err == EACCES || err == EINVAL) {
            LOG_DEBUG("setxattr: %s name=%s -> error %d ignored", path, name, err);
            return 0;
        }
        LOG_WARN("setxattr failed: %s, name=%s, errno=%d (%s)", path, name, err, strerror(err));
        return -err;
    }

    return 0;
}

// listxattr: list extended attributes
static int dmsa_listxattr(const char *path, char *list, size_t size) {
    LOG_DEBUG("listxattr: %s", path);

    char *actual = resolve_actual_path(path);
    if (!actual) {
        return -ENOENT;
    }

    ssize_t res = listxattr(actual, list, size, XATTR_NOFOLLOW);
    free(actual);

    if (res == -1) {
        int err = errno;
        // For permission errors on underlying storage, report empty xattr list
        // This allows Finder to proceed with copy operations
        if (err == EPERM || err == EACCES) {
            return 0;  // Empty list
        }
        return -err;
    }

    return (int)res;
}

// removexattr: remove extended attributes
static int dmsa_removexattr(const char *path, const char *name) {
    LOG_DEBUG("removexattr: %s, name=%s", path, name);

    if (g_state.readonly) {
        return -EROFS;
    }

    char *local = get_local_path(path);
    if (!local) {
        return -ENOMEM;
    }

    int res = removexattr(local, name, XATTR_NOFOLLOW);
    free(local);

    if (res == -1) {
        return -errno;
    }

    return 0;
}

// ============================================================
// FUSE operations table
// ============================================================
static struct fuse_operations dmsa_oper = {
    .getattr     = dmsa_getattr,
    .readdir     = dmsa_readdir,
    .open        = dmsa_open,
    .read        = dmsa_read,
    .write       = dmsa_write,
    .release     = dmsa_release,
    .create      = dmsa_create,
    .unlink      = dmsa_unlink,
    .mkdir       = dmsa_mkdir,
    .rmdir       = dmsa_rmdir,
    .rename      = dmsa_rename,
    .truncate    = dmsa_truncate,
    .chmod       = dmsa_chmod,
    .chown       = dmsa_chown,
    .utimens     = dmsa_utimens,
    .statfs      = dmsa_statfs,
    .readlink    = dmsa_readlink,
    .symlink     = dmsa_symlink,
    .access      = dmsa_access,
    .getxattr    = dmsa_getxattr,
    .setxattr    = dmsa_setxattr,
    .listxattr   = dmsa_listxattr,
    .removexattr = dmsa_removexattr,
};

// ============================================================
// Public API implementation
// ============================================================

int fuse_wrapper_mount(const char *mount_path, const char *local_dir, const char *external_dir) {
    if (!mount_path || !local_dir) {
        return FUSE_WRAPPER_ERR_INVALID_ARG;
    }

    pthread_mutex_lock(&g_state.lock);

    if (g_state.is_mounted) {
        pthread_mutex_unlock(&g_state.lock);
        return FUSE_WRAPPER_ERR_ALREADY_MOUNTED;
    }

    // Save paths
    g_state.mount_path = strdup(mount_path);
    g_state.local_dir = strdup(local_dir);
    g_state.external_dir = external_dir ? strdup(external_dir) : NULL;
    g_state.external_offline = (external_dir == NULL);

    // Extract user uid/gid from mount point path
    // Mount point is typically /Users/{username}/... format
    // We need to get the owner of the user directory
    struct stat parent_stat;
    char *parent_path = strdup(mount_path);
    // Try to get mount point parent directory owner
    char *last_slash = strrchr(parent_path, '/');
    if (last_slash && last_slash != parent_path) {
        *last_slash = '\0';
        if (stat(parent_path, &parent_stat) == 0) {
            g_state.owner_uid = parent_stat.st_uid;
            g_state.owner_gid = parent_stat.st_gid;
            LOG_INFO("Got owner from parent dir: uid=%d, gid=%d", g_state.owner_uid, g_state.owner_gid);
        } else {
            // Fall back to local_dir owner
            struct stat local_stat;
            if (stat(local_dir, &local_stat) == 0) {
                g_state.owner_uid = local_stat.st_uid;
                g_state.owner_gid = local_stat.st_gid;
                LOG_INFO("Got owner from local dir: uid=%d, gid=%d", g_state.owner_uid, g_state.owner_gid);
            }
        }
    }
    free(parent_path);

    pthread_mutex_unlock(&g_state.lock);

    LOG_INFO("Mounting FUSE filesystem:");
    LOG_INFO("  Mount point: %s", mount_path);
    LOG_INFO("  Local dir: %s", local_dir);
    LOG_INFO("  External dir: %s", external_dir ? external_dir : "(offline)");

    // Build FUSE arguments - using simpler parameter set
    char *mount_path_copy = strdup(mount_path);
    char *volname = basename(mount_path_copy);

    char volname_opt[256];
    snprintf(volname_opt, sizeof(volname_opt), "volname=%s", volname);

    // Build mount options
    // auto_xattr: let kernel handle xattr via AppleDouble (._ files), bypassing our callbacks
    //             This allows fcopyfile() to work properly for cp/Finder copy operations
    // local: indicates local filesystem (enables Finder features)
    // entry_timeout/attr_timeout/negative_timeout: cache directory entries and attributes
    //             Reduces kernel<->userspace round trips under heavy load
    // daemon_timeout=0: disable idle timeout (prevent FUSE from exiting when idle)
    // Note: We still implement setxattr/getxattr callbacks for non-Apple xattrs
    char mount_opts[1024];
    snprintf(mount_opts, sizeof(mount_opts),
             "%s,allow_other,default_permissions,auto_xattr,local,"
             "daemon_timeout=0,entry_timeout=1,attr_timeout=1,negative_timeout=1",
             volname_opt);

    LOG_INFO("Mount options: %s", mount_opts);

    // Use fuse_mount + fuse_new + fuse_loop instead of fuse_main
    // This avoids some internal issues with fuse_main

    struct fuse_args args = FUSE_ARGS_INIT(0, NULL);

    // Add mount options
    if (fuse_opt_add_arg(&args, "dmsa") == -1 ||
        fuse_opt_add_arg(&args, "-o") == -1 ||
        fuse_opt_add_arg(&args, mount_opts) == -1) {
        LOG_ERROR("fuse_opt_add_arg failed");
        free(mount_path_copy);
        fuse_opt_free_args(&args);
        return FUSE_WRAPPER_ERR_MOUNT_FAILED;
    }

    LOG_INFO("Calling fuse_mount...");

    // Mount
    g_state.chan = fuse_mount(mount_path, &args);
    if (!g_state.chan) {
        LOG_ERROR("fuse_mount failed! errno=%d (%s)", errno, strerror(errno));
        free(mount_path_copy);
        fuse_opt_free_args(&args);

        pthread_mutex_lock(&g_state.lock);
        free(g_state.mount_path);
        free(g_state.local_dir);
        if (g_state.external_dir) free(g_state.external_dir);
        g_state.mount_path = NULL;
        g_state.local_dir = NULL;
        g_state.external_dir = NULL;
        pthread_mutex_unlock(&g_state.lock);

        return FUSE_WRAPPER_ERR_FUSE_MOUNT_FAILED;
    }

    LOG_INFO("fuse_mount succeeded, calling fuse_new...");

    // Create FUSE instance
    g_state.fuse = fuse_new(g_state.chan, &args, &dmsa_oper, sizeof(dmsa_oper), NULL);
    fuse_opt_free_args(&args);

    if (!g_state.fuse) {
        LOG_ERROR("fuse_new failed! errno=%d (%s)", errno, strerror(errno));
        fuse_unmount(mount_path, g_state.chan);
        free(mount_path_copy);

        pthread_mutex_lock(&g_state.lock);
        g_state.chan = NULL;
        free(g_state.mount_path);
        free(g_state.local_dir);
        if (g_state.external_dir) free(g_state.external_dir);
        g_state.mount_path = NULL;
        g_state.local_dir = NULL;
        g_state.external_dir = NULL;
        pthread_mutex_unlock(&g_state.lock);

        return FUSE_WRAPPER_ERR_FUSE_NEW_FAILED;
    }

    pthread_mutex_lock(&g_state.lock);
    g_state.is_mounted = 1;
    pthread_mutex_unlock(&g_state.lock);

    LOG_INFO("FUSE mount successful! Starting event loop...");
    LOG_INFO("  File owner UID: %d, GID: %d", g_state.owner_uid, g_state.owner_gid);

    free(mount_path_copy);

    // Install signal handlers for exit diagnostics
    g_last_signal = 0;
    g_total_ops = 0;
    g_last_op_time = time(NULL);
    install_signal_handlers();

    // Start async callback worker thread
    start_callback_worker();

    // Pre-loop diagnostics
    LOG_INFO("FUSE pre-loop state:");
    LOG_INFO("  macFUSE devices: %d", check_macfuse_device());
    LOG_INFO("  Channel: %s", g_state.chan ? "valid" : "NULL");
    LOG_INFO("  Async callback queue: enabled (size=%d)", CALLBACK_QUEUE_SIZE);

    // Mark loop as running
    g_fuse_loop_running = 1;

    // Run FUSE event loop in MULTI-THREADED mode
    // Critical for handling symlinks pointing back to VFS mount point
    // Single-threaded mode deadlocks when readdir encounters such symlinks
    LOG_INFO("Starting fuse_loop_mt (multi-threaded)...");
    int result = fuse_loop_mt(g_state.fuse);
    int saved_errno = errno;

    // Mark loop as stopped
    g_fuse_loop_running = 0;

    // Stop callback worker thread
    stop_callback_worker();

    // ---- Comprehensive post-exit diagnostics ----
    collect_exit_diagnostics(mount_path, result, saved_errno);

    // Cleanup
    fuse_destroy(g_state.fuse);
    fuse_unmount(mount_path, g_state.chan);

    pthread_mutex_lock(&g_state.lock);

    free(g_state.mount_path);
    free(g_state.local_dir);
    if (g_state.external_dir) free(g_state.external_dir);

    g_state.mount_path = NULL;
    g_state.local_dir = NULL;
    g_state.external_dir = NULL;
    g_state.is_mounted = 0;
    g_state.fuse = NULL;
    g_state.chan = NULL;

    pthread_mutex_unlock(&g_state.lock);

    LOG_INFO("FUSE cleanup complete");

    return result == 0 ? FUSE_WRAPPER_OK : FUSE_WRAPPER_ERR_MOUNT_FAILED;
}

int fuse_wrapper_unmount(void) {
    pthread_mutex_lock(&g_state.lock);

    if (!g_state.is_mounted || !g_state.mount_path) {
        pthread_mutex_unlock(&g_state.lock);
        return FUSE_WRAPPER_ERR_NOT_MOUNTED;
    }

    char *mount_path = strdup(g_state.mount_path);
    pthread_mutex_unlock(&g_state.lock);

    LOG_INFO("Unmounting FUSE: %s", mount_path);

    // Clear pending delete set
    pending_delete_clear();

    // Clear syncing files set
    syncing_files_clear();

    // Use umount command to unmount
    char cmd[1024];
    snprintf(cmd, sizeof(cmd), "/sbin/umount '%s'", mount_path);
    int result = system(cmd);

    free(mount_path);

    return result == 0 ? FUSE_WRAPPER_OK : FUSE_WRAPPER_ERR_MOUNT_FAILED;
}

int fuse_wrapper_is_mounted(void) {
    pthread_mutex_lock(&g_state.lock);
    int result = g_state.is_mounted;
    pthread_mutex_unlock(&g_state.lock);
    return result;
}

void fuse_wrapper_update_external_dir(const char *external_dir) {
    pthread_mutex_lock(&g_state.lock);

    if (g_state.external_dir) {
        free(g_state.external_dir);
    }

    g_state.external_dir = external_dir ? strdup(external_dir) : NULL;
    g_state.external_offline = (external_dir == NULL);

    pthread_mutex_unlock(&g_state.lock);

    LOG_INFO("External dir updated: %s", external_dir ? external_dir : "(offline)");
}

void fuse_wrapper_set_external_offline(bool offline) {
    pthread_mutex_lock(&g_state.lock);
    g_state.external_offline = offline;
    pthread_mutex_unlock(&g_state.lock);

    LOG_INFO("External storage state: %s", offline ? "offline" : "online");
}

void fuse_wrapper_set_readonly(bool readonly) {
    pthread_mutex_lock(&g_state.lock);
    g_state.readonly = readonly;
    pthread_mutex_unlock(&g_state.lock);

    LOG_INFO("Read-only mode: %s", readonly ? "yes" : "no");
}

void fuse_wrapper_set_index_ready(bool ready) {
    pthread_mutex_lock(&g_state.lock);
    int was_ready = g_state.index_ready;
    g_state.index_ready = ready;
    pthread_mutex_unlock(&g_state.lock);

    // Reset log flag to allow printing on next state change
    if (ready && !was_ready) {
        index_not_ready_logged = 0;
        LOG_INFO("*** Index ready, VFS access open ***");
    } else if (!ready && was_ready) {
        LOG_INFO("Index marked not ready, VFS blocking access");
    }
}

int fuse_wrapper_is_index_ready(void) {
    pthread_mutex_lock(&g_state.lock);
    int result = g_state.index_ready;
    pthread_mutex_unlock(&g_state.lock);
    return result;
}

const char* fuse_wrapper_error_string(int error) {
    switch (error) {
        case FUSE_WRAPPER_OK:
            return "Success";
        case FUSE_WRAPPER_ERR_INVALID_ARG:
            return "Invalid argument";
        case FUSE_WRAPPER_ERR_ALREADY_MOUNTED:
            return "Already mounted";
        case FUSE_WRAPPER_ERR_NOT_MOUNTED:
            return "Not mounted";
        case FUSE_WRAPPER_ERR_MOUNT_FAILED:
            return "Mount failed";
        case FUSE_WRAPPER_ERR_FUSE_NEW_FAILED:
            return "fuse_new failed";
        case FUSE_WRAPPER_ERR_FUSE_MOUNT_FAILED:
            return "fuse_mount failed";
        default:
            return "Unknown error";
    }
}

// ============================================================
// Diagnostics API implementation
// ============================================================

void fuse_wrapper_get_diagnostics(FuseDiagnostics *diag) {
    if (!diag) return;

    pthread_mutex_lock(&g_state.lock);

    diag->is_mounted = g_state.is_mounted;
    diag->is_loop_running = g_fuse_loop_running;
    diag->channel_fd = g_state.chan ? 1 : -1;  // 1 means valid channel, -1 means NULL
    diag->total_ops = g_total_ops;
    diag->last_op_time = g_last_op_time;
    diag->last_signal = (int)g_last_signal;

    pthread_mutex_unlock(&g_state.lock);

    // Callback queue statistics
    diag->cb_queued = g_cb_queued;
    diag->cb_processed = g_cb_processed;
    diag->cb_dropped = g_cb_dropped;
    diag->cb_pending = (g_callback_queue.head - g_callback_queue.tail + CALLBACK_QUEUE_SIZE) % CALLBACK_QUEUE_SIZE;

    // Check macFUSE device count (outside lock to avoid blocking)
    diag->macfuse_dev_count = check_macfuse_device();
}

int fuse_wrapper_is_loop_running(void) {
    return g_fuse_loop_running;
}
