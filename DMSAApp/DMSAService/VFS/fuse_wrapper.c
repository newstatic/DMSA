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
// Logging macros
// ============================================================
#define LOG_PREFIX "[FUSE-C] "

#ifdef DEBUG
#define LOG_DEBUG(fmt, ...) fprintf(stderr, LOG_PREFIX "DEBUG: " fmt "\n", ##__VA_ARGS__)
#else
#define LOG_DEBUG(fmt, ...) ((void)0)
#endif

#define LOG_INFO(fmt, ...) fprintf(stderr, LOG_PREFIX "INFO: " fmt "\n", ##__VA_ARGS__)
#define LOG_WARN(fmt, ...) fprintf(stderr, LOG_PREFIX "WARN: " fmt "\n", ##__VA_ARGS__)
#define LOG_ERROR(fmt, ...) fprintf(stderr, LOG_PREFIX "ERROR: " fmt "\n", ##__VA_ARGS__)

// ============================================================
// Signal tracking for exit diagnostics
// ============================================================
static volatile sig_atomic_t g_last_signal = 0;

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
static char* resolve_actual_path(const char *virtual_path) {
    char *local = get_local_path(virtual_path);
    if (local) {
        struct stat st;
        if (stat(local, &st) == 0) {
            return local;
        }
        free(local);
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
        return -ENOENT;
    }

    int res = stat(actual_path, stbuf);
    free(actual_path);

    if (res == -1) {
        return -errno;
    }

    // Always report files as owned by the mount owner
    stbuf->st_uid = g_state.owner_uid;
    stbuf->st_gid = g_state.owner_gid;

    return 0;
}

// readdir: read directory contents (smart merge)
static int dmsa_readdir(const char *path, void *buf, fuse_fill_dir_t filler,
                        off_t offset, struct fuse_file_info *fi) {
    (void) offset;
    (void) fi;

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

    // Simple hash table for deduplication (max 4096 entries)
    #define MAX_ENTRIES 4096
    char *seen_names[MAX_ENTRIES];
    int seen_count = 0;

    memset(seen_names, 0, sizeof(seen_names));

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

                // Check if already added
                int found = 0;
                for (int i = 0; i < seen_count; i++) {
                    if (seen_names[i] && strcmp(seen_names[i], de->d_name) == 0) {
                        found = 1;
                        break;
                    }
                }

                if (!found && seen_count < MAX_ENTRIES) {
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

                // Check if already added
                int found = 0;
                for (int i = 0; i < seen_count; i++) {
                    if (seen_names[i] && strcmp(seen_names[i], de->d_name) == 0) {
                        found = 1;
                        break;
                    }
                }

                if (!found && seen_count < MAX_ENTRIES) {
                    seen_names[seen_count++] = strdup(de->d_name);
                    filler(buf, de->d_name, NULL, 0);
                }
            }
            closedir(dp);
        }
        free(external);
    }

    // Cleanup
    for (int i = 0; i < seen_count; i++) {
        free(seen_names[i]);
    }

    return 0;
}

// open: open file
static int dmsa_open(const char *path, struct fuse_file_info *fi) {
    LOG_DEBUG("open: %s, flags=%d", path, fi->flags);

    // Block file open when index is not ready
    CHECK_INDEX_READY();

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
        free(actual_path);
        if (local) free(local);
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
    LOG_DEBUG("write: %s, size=%zu, offset=%lld", path, size, offset);

    if (g_state.readonly) {
        return -EROFS;
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
    (void)path;

    if (fi->fh > 0) {
        close(fi->fh);
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
    free(local);

    fi->fh = fd;
    return 0;
}

// unlink: delete file
static int dmsa_unlink(const char *path) {
    LOG_DEBUG("unlink: %s", path);

    if (g_state.readonly) {
        return -EROFS;
    }

    int result = 0;

    // Delete local copy
    char *local = get_local_path(path);
    if (local) {
        if (unlink(local) == -1 && errno != ENOENT) {
            result = -errno;
        }
        free(local);
    }

    // Delete external copy (if online)
    char *external = get_external_path(path);
    if (external) {
        unlink(external);  // Ignore errors
        free(external);
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
    free(local);

    return 0;
}

// rmdir: remove directory
static int dmsa_rmdir(const char *path) {
    LOG_DEBUG("rmdir: %s", path);

    if (g_state.readonly) {
        return -EROFS;
    }

    int result = 0;

    // Delete local copy
    char *local = get_local_path(path);
    if (local) {
        if (rmdir(local) == -1 && errno != ENOENT) {
            result = -errno;
        }
        free(local);
    }

    // Delete external copy (if online)
    char *external = get_external_path(path);
    if (external) {
        rmdir(external);  // Ignore errors
        free(external);
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

    return 0;
}

// truncate: truncate file
static int dmsa_truncate(const char *path, off_t size) {
    LOG_DEBUG("truncate: %s, size=%lld", path, size);

    if (g_state.readonly) {
        return -EROFS;
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
    free(actual);

    if (res == -1) {
        return -errno;
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
    free(actual);

    if (res == -1) {
        return -errno;
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
    free(actual);

    if (res == -1) {
        return -errno;
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

    char *actual = resolve_actual_path(path);
    if (!actual) {
        // Root directory special handling
        if (strcmp(path, "/") == 0) {
            return 0;
        }
        return -ENOENT;
    }

    int res = access(actual, mask);
    free(actual);

    if (res == -1) {
        return -errno;
    }

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
        return -errno;
    }

    return (int)res;
}

// setxattr: set extended attributes (macOS version)
static int dmsa_setxattr(const char *path, const char *name, const char *value,
                         size_t size, int flags, uint32_t position) {
    LOG_DEBUG("setxattr: %s, name=%s", path, name);

    if (g_state.readonly) {
        return -EROFS;
    }

    char *local = get_local_path(path);
    if (!local) {
        return -ENOMEM;
    }

    int res = setxattr(local, name, value, size, position, flags | XATTR_NOFOLLOW);
    free(local);

    if (res == -1) {
        return -errno;
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
        return -errno;
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
    char mount_opts[1024];
    snprintf(mount_opts, sizeof(mount_opts),
             "%s,allow_other,default_permissions,noappledouble,noapplexattr,local",
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
    install_signal_handlers();

    // Run FUSE event loop (blocking)
    int result = fuse_loop(g_state.fuse);
    int saved_errno = errno;

    // ---- Post-exit diagnostics ----
    LOG_INFO("FUSE event loop exited, return value: %d, errno: %d (%s)",
             result, saved_errno, strerror(saved_errno));

    if (g_last_signal != 0) {
        LOG_WARN("Exit caused by signal: %d (%s)", (int)g_last_signal, strsignal((int)g_last_signal));
    } else {
        LOG_INFO("No signal received before exit");
    }

    // Check if mount point still exists
    struct stat mp_stat;
    if (stat(mount_path, &mp_stat) != 0) {
        LOG_WARN("Mount point gone after exit: %s (errno=%d %s)",
                 mount_path, errno, strerror(errno));
    } else {
        LOG_INFO("Mount point still exists: %s (type=0x%x)",
                 mount_path, mp_stat.st_mode & S_IFMT);
    }

    // Check if still mounted via statfs
    struct statfs fs_stat;
    if (statfs(mount_path, &fs_stat) == 0) {
        LOG_INFO("Filesystem at mount point: type=%s", fs_stat.f_fstypename);
    } else {
        LOG_WARN("statfs failed on mount point: errno=%d (%s)", errno, strerror(errno));
    }

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
