import AppKit

// 🍝 Pasta — paste + fun.
// A menu bar app: no Dock icon, lives quietly in the background.

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
