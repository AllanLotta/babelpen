import AppKit

// Revisor: AI proofreading in every text field on your Mac, powered by the
// AI CLI you already pay for (Claude Code, Codex, or your own command).

let app = NSApplication.shared
let controller = AppController()
app.delegate = controller
app.setActivationPolicy(.accessory)
app.run()
