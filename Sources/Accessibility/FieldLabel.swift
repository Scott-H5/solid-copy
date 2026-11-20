// FieldLabel.swift
//
// The visible label beside a field ("Callsign:"), hidden from VoiceOver.
//
// Why hide it? Each field already has the same name as its spoken label,
// so VoiceOver says "Callsign, W1AW, edit text" when you reach the field.
// If the visible label were also readable, moving with VO-arrows would
// stop on "Callsign:" first and then on the field, saying the name twice.
// Hiding the label gives one stop per field (accessibility contract,
// rule 16). Sighted users see no difference.
//
// Why draw the text instead of using an ordinary text label? An ordinary
// label (NSTextField) hands VoiceOver an inner "cell" object, and that
// cell stays visible to VoiceOver even when the label itself says it
// shouldn't be. (Scott heard the labels with the first version of this
// file.) A plain view that draws its own text has nothing inside it for
// VoiceOver to find.

import AppKit

final class FieldLabel: NSView {
    private let text: NSAttributedString

    // A label showing `text` followed by a colon.
    init(_ text: String) {
        self.text = NSAttributedString(string: text + ":", attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            // labelColor follows light and dark mode.
            .foregroundColor: NSColor.labelColor,
        ])
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("Not used") }

    // The size the text needs, so layout gives it the right space.
    override var intrinsicContentSize: NSSize {
        let size = text.size()
        return NSSize(width: ceil(size.width), height: ceil(size.height))
    }

    // Where the text's baseline is, so the label lines up with the text in
    // its field (the grid aligns rows by their first baseline).
    override var firstBaselineOffsetFromTop: CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        return ceil(font.ascender)
    }

    // Flipped means y counts down from the top, like the baseline above.
    override var isFlipped: Bool { true }

    // Right-aligned, so labels sit next to their fields.
    override func draw(_ dirtyRect: NSRect) {
        let size = text.size()
        text.draw(at: NSPoint(x: bounds.width - size.width, y: 0))
    }

    // Redraw in the new colours when you switch between light and dark.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    // Belt and braces: tell VoiceOver there's nothing here.
    override func isAccessibilityElement() -> Bool { false }
    override func accessibilityChildren() -> [Any]? { [] }
}
