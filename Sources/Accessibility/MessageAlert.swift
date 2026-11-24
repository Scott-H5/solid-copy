// MessageAlert.swift
//
// The message sheet AppDelegate.showMessage puts on the main window: a
// title, the details, and OK and Copy buttons. Made here, apart from
// AppDelegate, so tools/screen-size-check can measure the real thing.
//
// A long message (an import or upload report listing many contacts)
// goes in a scrolling box below the title, not in the alert's own text:
// macOS makes an alert as tall as its text, and 60 lines made it 2,054
// points tall, its OK and Copy buttons far off any screen (found by
// tools/screen-size-check, 24 November 2026). The alert's own text then
// gives the first line and says where the rest is, so VoiceOver still
// reads that much when it appears; the box is the next thing after it,
// and its text can be selected as well as read.

import AppKit

@MainActor
enum MessageAlert {
    // Longer than this goes in the box: about what fits on a small screen.
    static let longLines = 8
    static let longCharacters = 600

    static func make(title: String, details: String) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Copy")
        let lines = details.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > longLines || details.count > longCharacters else {
            alert.informativeText = details
            return alert
        }
        let first = lines.first.map(String.init) ?? ""
        let opening = first.count > 200 ? String(first.prefix(200)) + "…" : first
        alert.informativeText = opening + "\n\nThe whole message is in the box below. Copy puts it on the clipboard."

        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 440, height: 220))
        text.string = details
        text.isEditable = false
        text.isSelectable = true
        text.font = .systemFont(ofSize: NSFont.systemFontSize)
        text.textContainerInset = NSSize(width: 4, height: 4)
        text.isVerticallyResizable = true
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.setAccessibilityLabel("The whole message")
        let box = NSScrollView(frame: NSRect(x: 0, y: 0, width: 440, height: 220))
        box.documentView = text
        box.hasVerticalScroller = true
        box.borderType = .bezelBorder
        alert.accessoryView = box
        return alert
    }
}
