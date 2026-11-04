import AppKit

@MainActor final class SettingsWindowController: NSWindowController {
    private weak var app: AppDelegate?
    private var controls: [String: NSControl] = [:]
    private let fontNames: [String]
    let sections = NSTabView()

    init(app: AppDelegate) {
        self.app = app
        fontNames = (NSFontManager.shared.availableFontNames(with: .fixedPitchFontMask) ?? []).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "LocalStat Settings"
        window.minSize = NSSize(width: 740, height: 540)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        sections.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(sections)
        NSLayoutConstraint.activate([
            sections.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 16),
            sections.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -16),
            sections.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 16),
            sections.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -16)
        ])
        addSection("Appearance", rows: [
            row("App appearance", popup("appearance", AppearancePreference.allCases.map(\.title))),
            row("Editor theme", popup("theme", EditorTheme.allCases.map(\.title))),
            row("Help reading size", popup("helpFontSize", (10...28).map { "\($0) pt" }))
        ], explanation: "App appearance follows your Mac with System. Editor themes set code colors independently. Native follows the app appearance.")
        addSection("Editor", rows: [
            row("Font", popup("editorFontName", ["System Monospaced"] + fontNames)),
            row("Font size", popup("editorFontSize", (8...40).map { "\($0) pt" })),
            row("Line spacing", popup("lineSpacing", ["1", "1.25", "1.5", "1.75", "2"])),
            row("", checkbox("editorWrap", "Wrap long lines")),
            row("", checkbox("lineNumbers", "Show line numbers")),
            row("", checkbox("syntaxHighlighting", "Syntax highlighting")),
            row("", checkbox("invisibleCharacters", "Show whitespace characters")),
            row("", checkbox("currentLineHighlight", "Highlight current line"))
        ], explanation: "Display changes apply to every open source tab. Your source and undo history are preserved.")
        addSection("Output and Tables", rows: [
            row("Output and diagnostics font", popup("outputFontName", ["System Monospaced"] + fontNames)),
            row("Font size", popup("outputFontSize", (8...40).map { "\($0) pt" })),
            row("", checkbox("outputWrap", "Wrap text output")),
            row("Table zoom", popup("tableZoom", stride(from: 50, through: 200, by: 10).map { "\($0)%" }))
        ], explanation: "Wrapping can make plain-text table columns harder to compare. Table zoom affects the screen; printed pages and PDF reports keep their page layout.")
        addSection("Editing", rows: [
            row("Indentation", popup("indentWidth", ["2 spaces", "4 spaces", "8 spaces"])),
            row("", checkbox("automaticIndentation", "Indent automatically on Return")),
            row("", checkbox("bracketPairing", "Pair brackets, skip closers, and delete empty pairs"))
        ], explanation: "Indentation settings affect future edits. Existing source is not reformatted. Indentation assistance is a SAS-aware heuristic.")
        addSection("Layout", rows: [
            row("", checkbox("navigatorVisible", "Show project navigator")),
            row("", checkbox("resultsExpanded", "Expand results"))
        ], explanation: "Drag dividers to resize panes. Command-0 toggles the navigator. Command-2 expands results or restores the editor.")
        refresh()
        window.center()
    }
    required init?(coder: NSCoder) { nil }

    private func row(_ label: String, _ control: NSControl) -> [NSView] {
        let text = NSTextField(labelWithString: label)
        text.alignment = .right
        control.setAccessibilityLabel(label.isEmpty ? (control as? NSButton)?.title ?? "Setting" : label)
        return [text, control]
    }
    private func popup(_ id: String, _ items: [String]) -> NSPopUpButton {
        let control = NSPopUpButton(frame: .zero, pullsDown: false)
        control.addItems(withTitles: items)
        control.identifier = NSUserInterfaceItemIdentifier(id)
        control.target = self; control.action = #selector(changed(_:))
        control.widthAnchor.constraint(equalToConstant: 340).isActive = true
        controls[id] = control
        return control
    }
    private func checkbox(_ id: String, _ title: String) -> NSButton {
        let control = NSButton(checkboxWithTitle: title, target: self, action: #selector(changed(_:)))
        control.identifier = NSUserInterfaceItemIdentifier(id)
        controls[id] = control
        return control
    }
    private func addSection(_ title: String, rows: [[NSView]], explanation: String) {
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 12; grid.columnSpacing = 16
        grid.setContentHuggingPriority(.required, for: .vertical)
        grid.column(at: 0).width = 190
        grid.column(at: 1).xPlacement = .leading
        grid.yPlacement = .center
        let description = NSTextField(wrappingLabelWithString: explanation)
        description.textColor = .labelColor
        description.font = .systemFont(ofSize: 12)
        description.widthAnchor.constraint(equalToConstant: 570).isActive = true
        let reset = NSButton(title: title == "Layout" ? "Restore Default Layout" : "Reset \(title) Defaults", target: self, action: #selector(resetSection(_:)))
        reset.identifier = NSUserInterfaceItemIdentifier(title)
        reset.bezelStyle = .rounded
        let filler = NSView()
        filler.setContentHuggingPriority(.defaultLow, for: .vertical)
        let content = NSStackView(views: [grid, description, reset, filler])
        content.orientation = .vertical; content.alignment = .leading; content.spacing = 22
        content.edgeInsets = NSEdgeInsets(top: 24, left: 20, bottom: 24, right: 20)
        description.setContentHuggingPriority(.required, for: .vertical)
        reset.setContentHuggingPriority(.required, for: .vertical)
        let scroller = NSScrollView()
        scroller.hasVerticalScroller = true
        scroller.documentView = content
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: scroller.contentView.leadingAnchor),
            content.topAnchor.constraint(equalTo: scroller.contentView.topAnchor),
            content.widthAnchor.constraint(equalTo: scroller.contentView.widthAnchor),
            content.heightAnchor.constraint(greaterThanOrEqualTo: scroller.contentView.heightAnchor)
        ])
        let item = NSTabViewItem(identifier: title)
        item.label = title; item.view = scroller
        sections.addTabViewItem(item)
    }

    func refresh() {
        guard let app else { return }
        let value = app.preferences.values
        func choose(_ id: String, _ index: Int) {
            if let popup = controls[id] as? NSPopUpButton { popup.selectItem(at: max(0, min(index, popup.numberOfItems - 1))) }
        }
        choose("appearance", AppearancePreference.allCases.firstIndex(of: value.appearance) ?? 0)
        choose("theme", EditorTheme.allCases.firstIndex(of: value.theme) ?? 0)
        choose("editorFontName", fontNames.firstIndex(of: value.editorFontName).map { $0 + 1 } ?? 0)
        choose("outputFontName", fontNames.firstIndex(of: value.outputFontName).map { $0 + 1 } ?? 0)
        choose("editorFontSize", Int(value.editorFontSize) - 8)
        choose("outputFontSize", Int(value.outputFontSize) - 8)
        choose("helpFontSize", Int(value.helpFontSize) - 10)
        choose("lineSpacing", Int((value.lineSpacing - 1) * 4))
        choose("tableZoom", Int(((value.tableZoom * 100 - 50) / 10).rounded()))
        choose("indentWidth", [2, 4, 8].firstIndex(of: value.indentWidth) ?? 0)
        for (id, state) in ["editorWrap": value.editorWrap, "outputWrap": value.outputWrap,
                            "lineNumbers": value.lineNumbers, "syntaxHighlighting": value.syntaxHighlighting,
                            "invisibleCharacters": value.invisibleCharacters, "currentLineHighlight": value.currentLineHighlight,
                            "automaticIndentation": value.automaticIndentation, "bracketPairing": value.bracketPairing,
                            "navigatorVisible": app.navigatorVisible, "resultsExpanded": app.resultsExpanded] {
            (controls[id] as? NSButton)?.state = state ? .on : .off
        }
    }
    @objc private func changed(_ sender: NSControl) {
        guard let app, let id = sender.identifier?.rawValue else { return }
        let index = (sender as? NSPopUpButton)?.indexOfSelectedItem ?? 0
        let checked = (sender as? NSButton)?.state == .on
        if id == "navigatorVisible" { app.toggleNavigator(); return }
        if id == "resultsExpanded" { app.toggleResultsExpansion(); return }
        app.preferences.update { value in
            switch id {
            case "appearance": value.appearance = AppearancePreference.allCases[index]
            case "theme": value.theme = EditorTheme.allCases[index]
            case "editorFontName": value.editorFontName = index == 0 ? "" : fontNames[index - 1]
            case "outputFontName": value.outputFontName = index == 0 ? "" : fontNames[index - 1]
            case "editorFontSize": value.editorFontSize = Double(index + 8)
            case "outputFontSize": value.outputFontSize = Double(index + 8)
            case "helpFontSize": value.helpFontSize = Double(index + 10)
            case "lineSpacing": value.lineSpacing = 1 + Double(index) / 4
            case "tableZoom": value.tableZoom = Double(50 + index * 10) / 100
            case "indentWidth": value.indentWidth = [2, 4, 8][index]
            case "editorWrap": value.editorWrap = checked
            case "outputWrap": value.outputWrap = checked
            case "lineNumbers": value.lineNumbers = checked
            case "syntaxHighlighting": value.syntaxHighlighting = checked
            case "invisibleCharacters": value.invisibleCharacters = checked
            case "currentLineHighlight": value.currentLineHighlight = checked
            case "automaticIndentation": value.automaticIndentation = checked
            case "bracketPairing": value.bracketPairing = checked
            default: break
            }
        }
    }
    @objc private func resetSection(_ sender: NSButton) {
        guard let section = sender.identifier?.rawValue else { return }
        if section == "Layout" { app?.restoreDefaultLayout() } else { app?.preferences.reset(section) }
    }
}
