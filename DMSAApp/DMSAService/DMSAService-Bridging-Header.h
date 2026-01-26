/*
 * DMSAService-Bridging-Header.h
 * Bridging header for DMSAService
 *
 * 允许 Swift 代码调用 C 函数
 */

#ifndef DMSAService_Bridging_Header_h
#define DMSAService_Bridging_Header_h

// 自定义 FUSE 包装器 (不需要直接包含 fuse.h，fuse_wrapper.c 内部处理)
#include "VFS/fuse_wrapper.h"

#endif /* DMSAService_Bridging_Header_h */
