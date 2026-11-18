// main.swift
//
// The program starts running here. It creates the application object,
// hands it the AppDelegate (which builds the menus and the window), and
// starts the app's event loop, which waits for key presses and clicks
// until you quit.

import AppKit

// Everything that touches the interface must run on the "main thread".
// The program does start there, but Swift can't tell, so this says so.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // A normal app, with a Dock icon and a menu bar.
    app.setActivationPolicy(.regular)
    app.run()
}
