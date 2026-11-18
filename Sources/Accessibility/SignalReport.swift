// SignalReport.swift
//
// What can be typed in RST sent and RST received: an optional plus or
// minus, then up to three digits. That covers every report people give:
// 59 on phone, 599 on CW, and decibels such as -12 or +05 on FT8 and the
// other digital modes. Anything else (a letter typed by mistake, "5o9")
// beeps and isn't entered, and VoiceOver says what's allowed.
//
// Only typing is checked. A report that's already in the log (imported
// from another program, say "5NN") is shown and kept as it is; select it
// and type to replace it.
//
// A Formatter is AppKit's way of checking what's typed in a text field:
// isPartialStringValid is asked about each change before it's made.

import AppKit

final class SignalReportFormatter: Formatter {
    // The ADIF fields this applies to.
    static let fields: Set<String> = ["rst_sent", "rst_rcvd"]

    // True for a report as it's being typed: "", "-", "5", "59", "-12".
    static func isAllowed(_ text: String) -> Bool {
        var digits = Substring(text)
        if let first = digits.first, first == "+" || first == "-" { digits = digits.dropFirst() }
        return digits.count <= 3 && digits.allSatisfy { $0.isASCII && $0.isNumber }
    }

    override func string(for obj: Any?) -> String? {
        obj as? String ?? ""
    }

    override func getObjectValue(_ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?,
                                 for string: String,
                                 errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        obj?.pointee = string as NSString
        return true
    }

    override func isPartialStringValid(_ partialString: String,
                                       newEditingString newString: AutoreleasingUnsafeMutablePointer<NSString?>?,
                                       errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        if Self.isAllowed(partialString) { return true }
        // Typing happens on the main thread, where speech must be made.
        MainActor.assumeIsolated {
            NSSound.beep()
            Speaker.announce("Numbers only, with plus or minus. Up to 3 digits.")
        }
        return false
    }
}
