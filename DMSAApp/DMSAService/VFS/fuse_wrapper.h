/*
 * fuse_wrapper.h
 * DMSA - Direct libfuse C wrapper
 *
 * 直接使用 libfuse C API，避免 GMUserFileSystem 的 Objective-C 运行时问题
 * 解决多线程进程中 fork() 导致的崩溃
 *
 * 设计原则:
 * - C 代码直接实现所有 FUSE 回调
 * - 使用 local_dir 和 external_dir 路径进行智能合并
 * - 写操作写入 local_dir，读操作优先 local_dir，其次 external_dir
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
// 错误码定义
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
// 公共 API - 简化版
// ============================================================

/**
 * 挂载 FUSE 文件系统
 *
 * 此函数会阻塞，直到文件系统被卸载。
 * 应在后台线程中调用。
 *
 * @param mount_path 挂载点路径 (例如 /Users/xxx/Downloads)
 * @param local_dir 本地目录路径 (例如 /Users/xxx/Downloads_Local)
 * @param external_dir 外部目录路径 (可以为 NULL，表示离线)
 * @return FUSE_WRAPPER_OK 成功，其他值表示错误
 */
int fuse_wrapper_mount(
    const char *mount_path,
    const char *local_dir,
    const char *external_dir
);

/**
 * 卸载 FUSE 文件系统
 *
 * @return FUSE_WRAPPER_OK 成功
 */
int fuse_wrapper_unmount(void);

/**
 * 检查是否已挂载
 *
 * @return 1 已挂载，0 未挂载
 */
int fuse_wrapper_is_mounted(void);

/**
 * 更新外部目录路径
 * 可在运行时调用，用于外部存储上线/离线
 *
 * @param external_dir 新的外部目录路径，NULL 表示离线
 */
void fuse_wrapper_update_external_dir(const char *external_dir);

/**
 * 设置外部存储离线状态
 *
 * @param offline true 表示离线，false 表示在线
 */
void fuse_wrapper_set_external_offline(bool offline);

/**
 * 设置只读模式
 *
 * @param readonly true 表示只读，false 表示读写
 */
void fuse_wrapper_set_readonly(bool readonly);

/**
 * 设置索引就绪状态
 * 索引未就绪时，所有文件操作返回 EBUSY
 *
 * @param ready true 表示索引就绪，false 表示索引未就绪
 */
void fuse_wrapper_set_index_ready(bool ready);

/**
 * 获取索引就绪状态
 *
 * @return 1 已就绪，0 未就绪
 */
int fuse_wrapper_is_index_ready(void);

/**
 * 获取错误描述
 *
 * @param error 错误码
 * @return 错误描述字符串
 */
const char* fuse_wrapper_error_string(int error);

#ifdef __cplusplus
}
#endif

#endif /* FUSE_WRAPPER_H */
