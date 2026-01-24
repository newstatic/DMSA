//
//  DMSAApp-Bridging-Header.h
//  DMSAApp
//
//  Bridging header for macFUSE framework integration
//

#ifndef DMSAApp_Bridging_Header_h
#define DMSAApp_Bridging_Header_h

// macFUSE Framework
// Note: macFUSE must be installed at /Library/Frameworks/macFUSE.framework
#if __has_include(<macFUSE/macFUSE.h>)
#import <macFUSE/macFUSE.h>
#else
// Fallback: Define empty stubs when macFUSE is not installed
// This allows the project to compile without macFUSE for development

@class GMUserFileSystem;

#endif

#endif /* DMSAApp_Bridging_Header_h */
