import AppKit

// Imperative entry point — required when @main cannot be used alongside main.swift.
// BusyLightApp conforms to NSApplicationDelegate and is wired up here.
let app = NSApplication.shared
let delegate = BusyLightApp()
app.delegate = delegate
app.run()

