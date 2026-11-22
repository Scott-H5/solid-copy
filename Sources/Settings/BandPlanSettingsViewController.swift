// BandPlanSettingsViewController.swift
//
// Settings > Band Plan (v1.6 items 5 and 6):
//   - License class: a pop-up of the plan's classes, or "Not chosen".
//     Window > Band Plan starts on it, and the warning needs it.
//   - Band plan: the plans in the Band Plans folder (BandPlan.swift), the
//     United States one to start with.
//   - Warn when the radio is outside my privileges (BandWarning.swift).
//   - Show Band Plan Files: the folder in the Finder, to add a country's
//     plan or change one. A file that can't be read is named here, with
//     why.
// Escape closes Settings.

import AppKit

@MainActor
final class BandPlanSettingsViewController: NSViewController {
    var onEscape: (() -> Void)?

    private let classMenu = NSPopUpButton()
    private let planMenu = NSPopUpButton()
    private let warnBox = NSButton(checkboxWithTitle: "Warn when the radio is outside my privileges",
                                   target: nil, action: nil)
    private let filesButton = NSButton(title: "Show Band Plan Files", target: nil, action: nil)
    private let problems = NSTextField(wrappingLabelWithString: "")
    private var plans: [BandPlan] = []

    var firstControl: NSView { classMenu }

    override func loadView() {
        let heading = NSTextField(labelWithString: "Band Plan")
        heading.font = .boldSystemFont(ofSize: NSFont.systemFontSize + 1)
        let note = NSTextField(wrappingLabelWithString:
            "Your license class and the band plan say which frequencies and modes are yours. Window > Band "
            + "Plan (Command-6) shows the plan, and with the warning on, Solid Copy says so when the radio "
            + "settles outside your privileges or in a mode your class can't use there. The United States "
            + "plan comes from the FCC's rules (Part 97, as amended January 2026). A plan is a text file in "
            + "the Band Plans folder, so another country's can be added: Show Band Plan Files, and the "
            + "README there.")
        note.preferredMaxLayoutWidth = 520
        note.isSelectable = true
        problems.preferredMaxLayoutWidth = 520
        problems.isSelectable = true

        classMenu.setAccessibilityLabel("License class")
        planMenu.setAccessibilityLabel("Band plan")
        for menu in [classMenu, planMenu] {
            menu.target = self
            menu.setAccessibilityLinkedUIElements([note])
        }
        classMenu.action = #selector(classChanged(_:))
        planMenu.action = #selector(planChanged(_:))
        warnBox.target = self
        warnBox.action = #selector(warnChanged(_:))
        warnBox.setAccessibilityLinkedUIElements([note])
        filesButton.target = self
        filesButton.action = #selector(showFiles(_:))

        let classRow = NSStackView(views: [FieldLabel("License class"), classMenu])
        classRow.spacing = 8
        let planRow = NSStackView(views: [FieldLabel("Band plan"), planMenu])
        planRow.spacing = 8
        let order: [NSView] = [classMenu, planMenu, warnBox, filesButton]
        for (index, view) in order.enumerated() { view.nextKeyView = order[(index + 1) % order.count] }
        let stack = NSStackView(views: [heading, note, classRow, planRow, warnBox, filesButton, problems])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        view = stack
        refresh()
    }

    // Reads the folder again: plans added or changed show at once.
    func refresh() {
        guard isViewLoaded else { return }
        let loaded = BandPlanList.load()
        plans = loaded.plans
        let current = BandPlanList.current(named: Settings.bandPlanName, in: loaded)
        planMenu.removeAllItems()
        planMenu.addItems(withTitles: plans.isEmpty ? [current.name] : plans.map(\.name))
        planMenu.selectItem(withTitle: current.name)
        classMenu.removeAllItems()
        classMenu.addItems(withTitles: ["Not chosen"] + current.classes)
        if current.classes.contains(Settings.licenseClass) {
            classMenu.selectItem(withTitle: Settings.licenseClass)
        } else {
            classMenu.selectItem(at: 0)
        }
        warnBox.state = Settings.bandWarning ? .on : .off
        warnBox.isEnabled = classMenu.indexOfSelectedItem > 0
        problems.stringValue = loaded.problems.isEmpty ? "" : "Not used: " + loaded.problems.joined(separator: " ")
        problems.isHidden = loaded.problems.isEmpty
    }

    @objc private func classChanged(_ sender: NSPopUpButton) {
        Settings.licenseClass = sender.indexOfSelectedItem > 0 ? (sender.titleOfSelectedItem ?? "") : ""
        warnBox.isEnabled = sender.indexOfSelectedItem > 0
        BandWarning.shared.reloadPlan()
        Speaker.announce(Settings.licenseClass.isEmpty ? "No license class: no band warnings."
                         : "License class: \(Settings.licenseClass).")
    }

    @objc private func planChanged(_ sender: NSPopUpButton) {
        guard let name = sender.titleOfSelectedItem else { return }
        Settings.bandPlanName = name
        refresh()
        BandWarning.shared.reloadPlan()
        Speaker.announce("Band plan: \(name)." + (Settings.licenseClass.isEmpty ? " Choose your license class." : ""))
    }

    @objc private func warnChanged(_ sender: NSButton) {
        Settings.bandWarning = sender.state == .on
    }

    @objc private func showFiles(_ sender: Any?) {
        guard let base = try? LogList.baseFolder() else { return }
        _ = BandPlanList.load()   // makes it, with the United States file, if new
        NSWorkspace.shared.activateFileViewerSelecting(
            [BandPlanList.folder(in: base).appendingPathComponent("README.txt")])
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}
