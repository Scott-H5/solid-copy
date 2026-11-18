// RadioSlider.swift
//
// The controls at the bottom of the window that the arrow keys change:
// Tuning (the radio's frequency), Offset (its RIT or XIT offset), Power,
// RF gain and Squelch (FM only). Command-T (Radio > Tune) puts focus on
// Tuning; Tab goes on through the others shown, then back to Callsign;
// Shift-Tab goes back; Escape goes to Callsign from any of them.
//
//                      Tuning   Offset  Power   RF gain, Squelch
//   Up, Down           100 Hz   10 Hz   1 W     5%
//   Shift-Up, -Down     10 Hz   10 Hz   0.1 W   1%
//   Option-Up, -Down     1 kHz  100 Hz  5 W     20%
//   Delete               -      to 0    -       -
//
// To VoiceOver each is a slider ("Tuning", "Offset"), whose value is
// what's shown, in words ("7025.30 kilohertz", "plus 120 hertz"). Each
// change is spoken, a quick press interrupting the last, including when
// you turn the radio's own knob while you're here. VO-Up and VO-Down
// (VoiceOver's own slider keys) work as Up and Down.
//
// It's drawn rather than built from a text field, so VoiceOver meets one
// thing here, not a field and a label. (If VoiceOver's Quick Nav is on,
// VoiceOver takes the arrow keys itself; turn it off with Left and Right
// arrows together.)

import AppKit

@MainActor
final class RadioSlider: NSView {

    enum Leaving { case escape, tab, backTab }

    // What VoiceOver calls it, and its help.
    private let name: String
    private let help: String
    // The steps for Up and Down: plain, with Shift, with Option.
    private let steps: (plain: Int, shift: Int, option: Int)

    // Up and Down (positive up), Delete, and leaving by Escape or Tab.
    var onStep: ((Int) -> Void)?
    var onClear: (() -> Void)?
    var onLeave: ((Leaving) -> Void)?

    // What's drawn, and what VoiceOver hears as the value.
    private var shown = ""
    private var spoken = ""

    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 20, weight: .semibold)

    init(name: String, help: String, steps: (plain: Int, shift: Int, option: Int)) {
        self.name = name
        self.help = help
        self.steps = steps
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("Not used") }

    // Shows a new value. Says it, if focus is here and it changed.
    func show(_ newShown: String, spoken newSpoken: String) {
        guard newShown != shown else { return }
        shown = newShown
        spoken = newSpoken
        invalidateIntrinsicContentSize()
        needsDisplay = true
        if window?.firstResponder === self {
            NSAccessibility.post(element: self, notification: .valueChanged)
        }
    }

    // MARK: - Drawing

    private var attributes: [NSAttributedString.Key: Any] {
        [.font: Self.font, .foregroundColor: NSColor.labelColor]
    }

    override var intrinsicContentSize: NSSize {
        let size = (shown as NSString).size(withAttributes: attributes)
        return NSSize(width: ceil(size.width) + 16, height: ceil(size.height) + 8)
    }

    override func draw(_ dirtyRect: NSRect) {
        (shown as NSString).draw(at: NSPoint(x: 8, y: 4), withAttributes: attributes)
    }

    // The blue focus ring, round the whole control, when it has focus.
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() { bounds.fill() }

    // MARK: - Keys

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.shift, .option, .command, .control])
        let step = modifiers == .shift ? steps.shift
            : modifiers == .option ? steps.option
            : modifiers.isEmpty ? steps.plain : 0
        switch event.keyCode {
        case 126 where step > 0: onStep?(step)                             // Up
        case 125 where step > 0: onStep?(-step)                            // Down
        case 51 where onClear != nil, 117 where onClear != nil: onClear?() // Delete, Forward Delete
        case 53: onLeave?(.escape)                                          // Escape
        case 48: onLeave?(modifiers == .shift ? .backTab : .tab)            // Tab, Shift-Tab
        default: super.keyDown(with: event)
        }
    }

    // MARK: - VoiceOver

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .slider }
    override func accessibilityLabel() -> String? { name }
    override func accessibilityValue() -> Any? { spoken }
    override func accessibilityHelp() -> String? { help }
    override func accessibilityPerformIncrement() -> Bool {
        onStep?(steps.plain)
        return true
    }
    override func accessibilityPerformDecrement() -> Bool {
        onStep?(-steps.plain)
        return true
    }
}
