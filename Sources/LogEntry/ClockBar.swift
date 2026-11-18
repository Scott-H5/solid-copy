// ClockBar.swift
//
// Two clocks across the top of the window: UTC and your local time,
// each with its date, because the UTC date changes in the evening for
// anyone west of England.
//
// Logs always record UTC. ADIF defines QSO_DATE and TIME_ON as UTC, so
// that's the only time saved. Local time is shown only to help you.
//
// Each clock is its own line of text, so VoiceOver reads them separately
// (VO-arrow through the window to hear them). They wake only when the
// minute changes, and they never move focus or announce anything.

import AppKit

@MainActor
final class ClockBar: NSStackView {
    private let utcLabel = NSTextField(labelWithString: "")
    private let localLabel = NSTextField(labelWithString: "")
    private var timer: Timer?

    // "14:32 UTC, Sat 14 Nov 2026". Fixed format, so it reads the same on
    // every Mac.
    private let utcFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "HH:mm 'UTC', EEE d MMM yyyy"
        return formatter
    }()

    // Local time in your Mac's own style (for example "9:32 AM EST, Sat
    // 14 Nov 2026"), following your region and 12- or 24-hour settings.
    private let localFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("jmm z EEE d MMM yyyy")
        // Follow the Mac's time zone if it changes (travelling, say).
        formatter.timeZone = .autoupdatingCurrent
        return formatter
    }()

    init() {
        super.init(frame: .zero)
        orientation = .horizontal
        spacing = 32
        for label in [utcLabel, localLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize + 2, weight: .semibold)
            addArrangedSubview(label)
        }
        update()
        scheduleNextMinute()
    }

    // Wakes once, just after the next minute begins, updates the clocks,
    // and sets itself for the minute after. Waking only when something
    // changes (rather than every second) saves the Mac's energy. The small
    // tolerance lets macOS group this with other wake-ups.
    private func scheduleNextMinute() {
        let now = Date().timeIntervalSinceReferenceDate
        let nextMinute = (now / 60).rounded(.down) * 60 + 60
        let timer = Timer(fire: Date(timeIntervalSinceReferenceDate: nextMinute + 0.05), interval: 0,
                          repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.update()
                self?.scheduleNextMinute()
            }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    required init?(coder: NSCoder) { fatalError("Not used") }

    private func update() {
        let now = Date()
        let utc = "UTC: " + utcFormatter.string(from: now)
        let local = "Local: " + localFormatter.string(from: now)
        // Only touch the labels when the text changes, so VoiceOver isn't
        // told about a change every second.
        if utcLabel.stringValue != utc { utcLabel.stringValue = utc }
        if localLabel.stringValue != local { localLabel.stringValue = local }
    }
}
