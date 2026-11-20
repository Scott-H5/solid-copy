// FormTextField.swift
//
// Contacts pasted in the logging form go into the log. Contacts on the
// clipboard (copied with Command-C in a log) are a block of ADIF text, and
// Command-V in a field would drop all of it into Callsign. Instead they're
// added to the open log, as Command-V in the log does, and the field is
// left as it was. Any other paste works as usual. (Scott, 17 November
// 2026. First it said to go to the log with Command-I; but in an empty
// log VoiceOver had nothing to land on, so focus seemed to stay or move
// at random. Pasting from where you are avoids moving at all.)
//
// How: every text field in a window types into one shared "field editor"
// (an NSTextView). The logging window's delegate (FormFieldEditor.Provider)
// hands its form fields this field editor, whose paste checks first.
// Edit Contact and Settings keep the usual one.

import AppKit

// The form's fields: ordinary text fields, marked so the window knows to
// give them the checking field editor.
final class FormTextField: NSTextField {}

final class FormFieldEditor: NSTextView {
    // Adds the clipboard's contacts to the open log (LogTableViewController
    // .paste); set by the Provider.
    var pasteContacts: (() -> Void)?

    override func paste(_ sender: Any?) {
        if let text = NSPasteboard.general.string(forType: .string), Self.isContacts(text) {
            return pasteContacts?() ?? NSSound.beep()
        }
        super.paste(sender)
    }

    // ADIF with at least one whole record: what Command-C in a log copies.
    // A callsign or a frequency never has "<EOR>" in it.
    static func isContacts(_ text: String) -> Bool {
        text.range(of: "<EOR>", options: .caseInsensitive) != nil
    }

    // The logging window's delegate: the checking field editor for the
    // form's fields, the usual one (nil) for anything else.
    final class Provider: NSObject, NSWindowDelegate {
        // What pasting contacts in a form field does (AppDelegate sets it).
        var pasteContacts: (() -> Void)?

        private lazy var editor: FormFieldEditor = {
            let editor = FormFieldEditor()
            editor.pasteContacts = { [weak self] in self?.pasteContacts?() }
            // As macOS's own field editor: one line, plain text, with
            // Command-Z (a new NSTextView has undo off).
            editor.isFieldEditor = true
            editor.isRichText = false
            editor.importsGraphics = false
            editor.allowsUndo = true
            return editor
        }()

        func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
            client is FormTextField ? editor : nil
        }
    }
}
