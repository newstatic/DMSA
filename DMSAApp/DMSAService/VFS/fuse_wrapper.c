/*
 * fuse_wrapper.c
 * DMSA - Direct libfuse C wrapper implementation
 *
 * 直接实现 FUSE 文件系统回调，不使用 GMUserFileSystem
 * 解决多线程进程中 fork() 导致的崩溃问题
 */

// macOS 特定定义
#define _DARWIN_USE_64_BIT_INODE 1

// FUSE API 版本 (macFUSE 使用 FUSE 2.x API)
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

#include "fuse_wrapper.h"

// ============================================================
// 日志宏
// ============================================================
#define LOG_PREFIX "[FUSE-C] "

#ifdef DEBUG
#define LOG_DEBUG(fmt, ...) fprintf(stderr, LOG_PREFIX "DEBUG: " fmt "\n", ##__VA_ARGS__)
#else
#define LOG_DEBUG(fmt, ...) ((void)0)
#endif

#define LOG_INFO(fmt, ...) fprintf(stderr, LOG_PREFIX "INFO: " fmt "\n", ##__VA_ARGS__)
#define LOG_ERROR(fmt, ...) fprintf(stderr, LOG_PREFIX "ERROR: " fmt "\n", ##__VA_ARGS__)

// ============================================================
// 全局状态
// ============================================================
static struct {
    char *mount_path;           // 挂载点路径
    char *local_dir;            // 本地目录路径
    char *external_dir;         // 外部目录路径 (可为 NULL)
    int is_mounted;             // 是否已挂载
    int external_offline;       // 外部是否离线
    int readonly;               // 是否只读模式
    uid_t owner_uid;            // 挂载点所有者 UID
    gid_t owner_gid;            // 挂载点所有者 GID
    struct fuse *fuse;          // FUSE 实例
    struct fuse_chan *chan;     // FUSE 通道
    pthread_mutex_t lock;       // 状态锁
} g_state = {
    .mount_path = NULL,
    .local_dir = NULL,
    .external_dir = NULL,
    .is_mounted = 0,
    .external_offline = 0,
    .readonly = 0,
    .owner_uid = 0,
    .owner_gid = 0,
    .fuse = NULL,
    .chan = NULL,
    .lock = PTHREAD_MUTEX_INITIALIZER
};

// ============================================================
// 辅助函数
// ============================================================

// 拼接路径
static char* join_path(const char *base, const char *path) {
    if (!base || !path) return NULL;

    // 跳过 path 开头的 /
    while (*path == '/') path++;

    size_t base_len = strlen(base);
    size_t path_len = strlen(path);

    // 移除 base 末尾的 /
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

// 获取本地路径
static char* get_local_path(const char *virtual_path) {
    return join_path(g_state.local_dir, virtual_path);
}

// 获取外部路径
static char* get_external_path(const char *virtual_path) {
    if (!g_state.external_dir || g_state.external_offline) {
        return NULL;
    }
    return join_path(g_state.external_dir, virtual_path);
}

// 解析实际路径 (优先本地，其次外部)
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

// 确保父目录存在
static int ensure_parent_directory(const char *path) {
    char *path_copy = strdup(path);
    if (!path_copy) return -ENOMEM;

    char *parent = dirname(path_copy);

    struct stat st;
    if (stat(parent, &st) == 0) {
        free(path_copy);
        return 0;  // 父目录已存在
    }

    // 递归创建
    int result = 0;
    char *p = path_copy;

    // 跳过开头的 /
    if (*p == '/') p++;

    while (*p) {
        if (*p == '/') {
            *p = '\0';
            if (strlen(path_copy) > 0 && stat(path_copy, &st) != 0) {
                if (mkdir(path_copy, 0755) != 0 && errno != EEXIST) {
                    result = -errno;
                    break;
                }
            }
            *p = '/';
        }
        p++;
    }

    free(path_copy);
    return result;
}

// 检查是否应该排除的文件
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

    // 检查 ._ 开头的文件
    if (strncmp(name, "._", 2) == 0) {
        return 1;
    }

    return 0;
}

// ============================================================
// FUSE 回调函数
// ============================================================

// getattr: 获取文件属性
static int root_getattr_logged = 0;  // 避免日志刷屏

static int dmsa_getattr(const char *path, struct stat *stbuf) {
    LOG_DEBUG("getattr: %s", path);

    memset(stbuf, 0, sizeof(struct stat));

    // 根目录特殊处理
    if (strcmp(path, "/") == 0) {
        stbuf->st_mode = S_IFDIR | 0755;
        stbuf->st_nlink = 2;
        stbuf->st_uid = g_state.owner_uid;
        stbuf->st_gid = g_state.owner_gid;
        stbuf->st_atime = stbuf->st_mtime = stbuf->st_ctime = time(NULL);

        // 首次访问根目录时打印日志
        if (!root_getattr_logged) {
            LOG_INFO("getattr(/): 返回 uid=%d, gid=%d, mode=0755",
                     g_state.owner_uid, g_state.owner_gid);
            root_getattr_logged = 1;
        }
        return 0;
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

    return 0;
}

// readdir: 读取目录内容 (智能合并)
static int dmsa_readdir(const char *path, void *buf, fuse_fill_dir_t filler,
                        off_t offset, struct fuse_file_info *fi) {
    (void) offset;
    (void) fi;

    LOG_DEBUG("readdir: %s", path);

    // 添加 . 和 ..
    filler(buf, ".", NULL, 0);
    filler(buf, "..", NULL, 0);

    // 用于去重的简单哈希表 (最多 4096 个条目)
    #define MAX_ENTRIES 4096
    char *seen_names[MAX_ENTRIES];
    int seen_count = 0;

    memset(seen_names, 0, sizeof(seen_names));

    // 从本地目录读取
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

                // 检查是否已添加
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

    // 从外部目录读取 (如果在线)
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

                // 检查是否已添加
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

    // 清理
    for (int i = 0; i < seen_count; i++) {
        free(seen_names[i]);
    }

    return 0;
}

// open: 打开文件
static int dmsa_open(const char *path, struct fuse_file_info *fi) {
    LOG_DEBUG("open: %s, flags=%d", path, fi->flags);

    char *actual_path = resolve_actual_path(path);

    if (!actual_path) {
        // 文件不存在，检查是否是创建模式
        if ((fi->flags & O_CREAT) || (fi->flags & O_WRONLY) || (fi->flags & O_RDWR)) {
            actual_path = get_local_path(path);
            if (!actual_path) {
                return -ENOENT;
            }

            // 确保父目录存在
            int res = ensure_parent_directory(actual_path);
            if (res != 0) {
                free(actual_path);
                return res;
            }

            // 创建空文件
            int fd = open(actual_path, O_CREAT | O_WRONLY, 0644);
            if (fd == -1) {
                int err = errno;
                free(actual_path);
                return -err;
            }
            close(fd);
        } else {
            return -ENOENT;
        }
    }

    // 如果是写模式且实际路径是外部路径，需要先复制到本地
    char *local = get_local_path(path);
    if (local && ((fi->flags & O_WRONLY) || (fi->flags & O_RDWR))) {
        if (strcmp(actual_path, local) != 0) {
            // 实际路径是外部路径，复制到本地
            ensure_parent_directory(local);

            // 简单的文件复制
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

            // 使用本地路径
            free(actual_path);
            actual_path = local;
            local = NULL;
        }
    }

    // 尝试打开文件
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

// read: 读取文件内容
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

// write: 写入文件内容
static int dmsa_write(const char *path, const char *buf, size_t size, off_t offset,
                      struct fuse_file_info *fi) {
    LOG_DEBUG("write: %s, size=%zu, offset=%lld", path, size, offset);

    if (g_state.readonly) {
        return -EROFS;
    }

    int fd = fi->fh;
    if (fd <= 0) {
        // 如果没有 fh，尝试直接写入本地文件
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

// release: 关闭文件
static int dmsa_release(const char *path, struct fuse_file_info *fi) {
    LOG_DEBUG("release: %s", path);
    (void)path;

    if (fi->fh > 0) {
        close(fi->fh);
    }

    return 0;
}

// create: 创建文件
static int dmsa_create(const char *path, mode_t mode, struct fuse_file_info *fi) {
    LOG_DEBUG("create: %s, mode=%o", path, mode);

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
    free(local);

    if (fd == -1) {
        return -errno;
    }

    fi->fh = fd;
    return 0;
}

// unlink: 删除文件
static int dmsa_unlink(const char *path) {
    LOG_DEBUG("unlink: %s", path);

    if (g_state.readonly) {
        return -EROFS;
    }

    int result = 0;

    // 删除本地副本
    char *local = get_local_path(path);
    if (local) {
        if (unlink(local) == -1 && errno != ENOENT) {
            result = -errno;
        }
        free(local);
    }

    // 删除外部副本 (如果在线)
    char *external = get_external_path(path);
    if (external) {
        unlink(external);  // 忽略错误
        free(external);
    }

    return result;
}

// mkdir: 创建目录
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
    free(local);

    if (res == -1) {
        return -errno;
    }

    return 0;
}

// rmdir: 删除目录
static int dmsa_rmdir(const char *path) {
    LOG_DEBUG("rmdir: %s", path);

    if (g_state.readonly) {
        return -EROFS;
    }

    int result = 0;

    // 删除本地副本
    char *local = get_local_path(path);
    if (local) {
        if (rmdir(local) == -1 && errno != ENOENT) {
            result = -errno;
        }
        free(local);
    }

    // 删除外部副本 (如果在线)
    char *external = get_external_path(path);
    if (external) {
        rmdir(external);  // 忽略错误
        free(external);
    }

    return result;
}

// rename: 重命名
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

    // 如果源文件在外部目录，先复制到本地
    struct stat st;
    if (stat(local_from, &st) != 0) {
        char *external_from = get_external_path(from);
        if (external_from && stat(external_from, &st) == 0) {
            // 复制外部文件到本地
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

    // 也在外部目录重命名 (如果在线)
    char *external_from = get_external_path(from);
    char *external_to = get_external_path(to);
    if (external_from && external_to) {
        // 确保外部目标目录存在
        char *ext_to_copy = strdup(external_to);
        if (ext_to_copy) {
            char *parent = dirname(ext_to_copy);
            mkdir(parent, 0755);  // 忽略错误
            free(ext_to_copy);
        }
        rename(external_from, external_to);  // 忽略错误
    }
    if (external_from) free(external_from);
    if (external_to) free(external_to);

    return 0;
}

// truncate: 截断文件
static int dmsa_truncate(const char *path, off_t size) {
    LOG_DEBUG("truncate: %s, size=%lld", path, size);

    if (g_state.readonly) {
        return -EROFS;
    }

    char *local = get_local_path(path);
    if (!local) {
        return -ENOMEM;
    }

    // 如果本地不存在，从外部复制
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

// chmod: 修改权限
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

// chown: 修改所有者
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

// utimens: 修改时间戳
static int dmsa_utimens(const char *path, const struct timespec ts[2]) {
    LOG_DEBUG("utimens: %s", path);

    char *actual = resolve_actual_path(path);
    if (!actual) {
        return -ENOENT;
    }

    // 使用 utimensat (macOS 10.13+)
    int res = utimensat(AT_FDCWD, actual, ts, AT_SYMLINK_NOFOLLOW);
    free(actual);

    if (res == -1) {
        return -errno;
    }

    return 0;
}

// statfs: 文件系统统计
static int dmsa_statfs(const char *path, struct statvfs *stbuf) {
    LOG_DEBUG("statfs: %s", path);
    (void)path;

    // 使用本地目录的统计信息
    int res = statvfs(g_state.local_dir, stbuf);
    if (res == -1) {
        return -errno;
    }

    return 0;
}

// readlink: 读取符号链接
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

// symlink: 创建符号链接
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
    free(local);

    if (res == -1) {
        return -errno;
    }

    return 0;
}

// access: 检查访问权限
static int dmsa_access(const char *path, int mask) {
    LOG_DEBUG("access: %s, mask=%d", path, mask);

    char *actual = resolve_actual_path(path);
    if (!actual) {
        // 根目录特殊处理
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

// getxattr: 获取扩展属性 (macOS 版本)
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

// setxattr: 设置扩展属性 (macOS 版本)
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

// listxattr: 列出扩展属性
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

// removexattr: 删除扩展属性
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
// FUSE 操作表
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
// 公共 API 实现
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

    // 保存路径
    g_state.mount_path = strdup(mount_path);
    g_state.local_dir = strdup(local_dir);
    g_state.external_dir = external_dir ? strdup(external_dir) : NULL;
    g_state.external_offline = (external_dir == NULL);

    // 从挂载点路径提取用户 uid/gid
    // 挂载点通常是 /Users/{username}/... 格式
    // 我们需要获取用户目录的所有者
    struct stat parent_stat;
    char *parent_path = strdup(mount_path);
    // 尝试获取挂载点父目录的 owner
    char *last_slash = strrchr(parent_path, '/');
    if (last_slash && last_slash != parent_path) {
        *last_slash = '\0';
        if (stat(parent_path, &parent_stat) == 0) {
            g_state.owner_uid = parent_stat.st_uid;
            g_state.owner_gid = parent_stat.st_gid;
            LOG_INFO("从父目录获取 owner: uid=%d, gid=%d", g_state.owner_uid, g_state.owner_gid);
        } else {
            // 回退到 local_dir 的所有者
            struct stat local_stat;
            if (stat(local_dir, &local_stat) == 0) {
                g_state.owner_uid = local_stat.st_uid;
                g_state.owner_gid = local_stat.st_gid;
                LOG_INFO("从本地目录获取 owner: uid=%d, gid=%d", g_state.owner_uid, g_state.owner_gid);
            }
        }
    }
    free(parent_path);

    pthread_mutex_unlock(&g_state.lock);

    LOG_INFO("挂载 FUSE 文件系统:");
    LOG_INFO("  挂载点: %s", mount_path);
    LOG_INFO("  本地目录: %s", local_dir);
    LOG_INFO("  外部目录: %s", external_dir ? external_dir : "(离线)");

    // 构建 FUSE 参数 - 使用更简单的参数集
    char *mount_path_copy = strdup(mount_path);
    char *volname = basename(mount_path_copy);

    char volname_opt[256];
    snprintf(volname_opt, sizeof(volname_opt), "volname=%s", volname);

    // 构建挂载选项
    char mount_opts[1024];
    snprintf(mount_opts, sizeof(mount_opts),
             "%s,allow_other,default_permissions,noappledouble,noapplexattr,local",
             volname_opt);

    LOG_INFO("挂载选项: %s", mount_opts);

    // 使用 fuse_mount + fuse_new + fuse_loop 替代 fuse_main
    // 这样可以避免 fuse_main 内部的一些问题

    struct fuse_args args = FUSE_ARGS_INIT(0, NULL);

    // 添加挂载选项
    if (fuse_opt_add_arg(&args, "dmsa") == -1 ||
        fuse_opt_add_arg(&args, "-o") == -1 ||
        fuse_opt_add_arg(&args, mount_opts) == -1) {
        LOG_ERROR("fuse_opt_add_arg 失败");
        free(mount_path_copy);
        fuse_opt_free_args(&args);
        return FUSE_WRAPPER_ERR_MOUNT_FAILED;
    }

    LOG_INFO("调用 fuse_mount...");

    // 挂载
    g_state.chan = fuse_mount(mount_path, &args);
    if (!g_state.chan) {
        LOG_ERROR("fuse_mount 失败! errno=%d (%s)", errno, strerror(errno));
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

    LOG_INFO("fuse_mount 成功, 调用 fuse_new...");

    // 创建 FUSE 实例
    g_state.fuse = fuse_new(g_state.chan, &args, &dmsa_oper, sizeof(dmsa_oper), NULL);
    fuse_opt_free_args(&args);

    if (!g_state.fuse) {
        LOG_ERROR("fuse_new 失败! errno=%d (%s)", errno, strerror(errno));
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

    LOG_INFO("FUSE 挂载成功! 启动事件循环...");
    LOG_INFO("  文件所有者 UID: %d, GID: %d", g_state.owner_uid, g_state.owner_gid);

    free(mount_path_copy);

    // 运行 FUSE 事件循环 (阻塞)
    int result = fuse_loop(g_state.fuse);

    LOG_INFO("FUSE 事件循环退出, 返回值: %d", result);

    // 清理
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

    LOG_INFO("FUSE 清理完成");

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

    LOG_INFO("卸载 FUSE: %s", mount_path);

    // 使用 umount 命令卸载
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

    LOG_INFO("外部目录已更新: %s", external_dir ? external_dir : "(离线)");
}

void fuse_wrapper_set_external_offline(bool offline) {
    pthread_mutex_lock(&g_state.lock);
    g_state.external_offline = offline;
    pthread_mutex_unlock(&g_state.lock);

    LOG_INFO("外部存储状态: %s", offline ? "离线" : "在线");
}

void fuse_wrapper_set_readonly(bool readonly) {
    pthread_mutex_lock(&g_state.lock);
    g_state.readonly = readonly;
    pthread_mutex_unlock(&g_state.lock);

    LOG_INFO("只读模式: %s", readonly ? "是" : "否");
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
