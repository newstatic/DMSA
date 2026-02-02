/*
 * DMSAService-Bridging-Header.h
 * Bridging header for DMSAService
 *
 * Allows Swift code to call C functions
 */

#ifndef DMSAService_Bridging_Header_h
#define DMSAService_Bridging_Header_h

// Custom FUSE wrapper (no need to include fuse.h directly, handled internally by fuse_wrapper.c)
#include "VFS/fuse_wrapper.h"

#endif /* DMSAService_Bridging_Header_h */
