//
//  DMSAApp-Bridging-Header.h
//  DMSAApp
//
//  Bridging header for macFUSE framework integration
//

#ifndef DMSAApp_Bridging_Header_h
#define DMSAApp_Bridging_Header_h

// macFUSE Framework
// 注意: 不要在 Swift 中使用 "import macFUSE"，因为 Swift 模块可能版本不兼容
// 我们使用动态加载方式 (NSClassFromString, perform:) 来调用 GMUserFileSystem
//
// macFUSE must be installed at /Library/Frameworks/macFUSE.framework

// 我们不直接导入 macFUSE 头文件，因为：
// 1. Swift 编译器会自动发现并尝试导入 Swift 模块（可能版本不兼容）
// 2. 如果通过 Framework Search Paths 导入，会导致重复定义
//
// 相反，我们使用纯动态方法：
// - NSClassFromString("GMUserFileSystem") 获取类
// - setValue:forKey: 和 perform: 调用方法
// 这不需要任何编译时类型信息

// 如果需要编译时类型检查，可以前向声明类
@class GMUserFileSystem;

#endif /* DMSAApp_Bridging_Header_h */
