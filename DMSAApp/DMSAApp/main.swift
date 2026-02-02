import Cocoa

// DMSA - Delt MACOS Sync App
// macOS menu bar sync application

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// Set as accessory app (menu bar only)
app.setActivationPolicy(.accessory)

app.run()
