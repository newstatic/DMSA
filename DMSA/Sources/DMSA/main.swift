import Cocoa

// DMSA - Delt MACOS Sync App
// macOS 菜单栏同步应用

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// 设置为 accessory 应用（仅在菜单栏显示）
app.setActivationPolicy(.accessory)

app.run()
