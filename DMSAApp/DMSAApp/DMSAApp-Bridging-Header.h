//
//  DMSAApp-Bridging-Header.h
//  DMSAApp
//
//  Bridging header for macFUSE framework integration
//

#ifndef DMSAApp_Bridging_Header_h
#define DMSAApp_Bridging_Header_h

// macFUSE Framework
// Note: Do not use "import macFUSE" in Swift, as the Swift module may have version incompatibilities
// We use dynamic loading (NSClassFromString, perform:) to call GMUserFileSystem
//
// macFUSE must be installed at /Library/Frameworks/macFUSE.framework

// We do not directly import macFUSE headers because:
// 1. The Swift compiler will auto-discover and try to import the Swift module (possible version mismatch)
// 2. Importing via Framework Search Paths would cause duplicate definitions
//
// Instead, we use pure dynamic methods:
// - NSClassFromString("GMUserFileSystem") to get the class
// - setValue:forKey: and perform: to call methods
// This requires no compile-time type information

// Forward-declare the class if compile-time type checking is needed
@class GMUserFileSystem;

#endif /* DMSAApp_Bridging_Header_h */
