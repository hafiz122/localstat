import AppKit
import SASCore
import UniformTypeIdentifiers

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate,
    NSTableViewDataSource, NSTableViewDelegate, NSTabViewDelegate, NSSplitViewDelegate, NSMenuItemValidation {
    var window: NSWindow!
    let preferences = IDEPreferences()
    var helpController: HelpWindowController?
    var settingsController: SettingsWindowController?
    let fileTable = NSTableView()
    let diagnosticTable = NSTableView()
    let tabs = NSTabView()
    let results = NSTabView()
    let navigatorSplit = NSSplitView()
    let editorResultsSplit = NSSplitView()
    let navigatorPane = NSStackView()
    let resultsContainer = NSStackView()
    let resultsSelector = NSSegmentedControl()
    let expandResultsButton = NSButton(title: "Expand Results", target: nil, action: nil)
    let outputView = NSTextView()
    let tableScroll = NSScrollView()
    let statusLabel = NSTextField(labelWithString: "Open a program or create a new one.")
    let projectLabel = NSTextField(labelWithString: "Project")
    let projectHint = NSTextField(wrappingLabelWithString: "Double-click a program to open it. Paths are relative to this project folder.")
    let runButton = NSButton(title: "Run Program", target: nil, action: nil)
    let stopButton = NSButton(title: "Stop", target: nil, action: nil)
    let appearancePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    var appearanceDefaults: UserDefaults {
        get { preferences.defaults }
        set { preferences.useDefaults(newValue) }
    }
    var layoutDefaults: UserDefaults {
        get { preferences.defaults }
        set { preferences.useDefaults(newValue) }
    }
    var appearancePreference: AppearancePreference { preferences.values.appearance }
    private(set) var navigatorVisible = true
    private(set) var resultsExpanded = false
    private var navigatorWidth: CGFloat = 215
    private var normalResultsFraction: CGFloat = 0.30
    private var navigatorMinimumWidth: NSLayoutConstraint?
    private var applyingLayout = false
    var documents: [EditorDocument] = []
    var files: [URL] = []
    var diagnostics: [Diagnostic] = []
    var lastResult: RunResult?
    var lastRunDocument: EditorDocument?
    private var pendingOpenURLs: [URL] = []
    var projectURL = FileManager.default.homeDirectoryForCurrentUser
    lazy var runner = LocalRuntimeRunner(executable: Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/opensas"))
    var current: EditorDocument? {
        guard let id = tabs.selectedTabViewItem?.identifier as? UUID else { return nil }
        return documents.first { $0.id == id }
    }

    override init() {
        super.init()
        preferences.onChange = { [weak self] in self?.applyPreferences() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        restoreAppearance()
        buildMenu()
        buildWindow()
        loadProject()
        pendingOpenURLs.forEach { open($0) }
        pendingOpenURLs.removeAll()
        if documents.isEmpty { newDocument(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func buildMenu() {
        let menu = NSMenu()
        func section(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: title)
            item.submenu = submenu
            menu.addItem(item)
            return submenu
        }
        func item(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "", modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
            entry.keyEquivalentModifierMask = modifiers
            entry.target = target
            menu.addItem(entry)
        }
        let app = section("LocalStat")
        item(app, "About LocalStat", #selector(about), target: self)
        item(app, "Settings…", #selector(showSettings), ",", target: self)
        app.addItem(.separator())
        item(app, "Quit LocalStat", #selector(NSApplication.terminate(_:)), "q")
        let file = section("File")
        item(file, "New Program", #selector(newDocument(_:)), "n", target: self)
        item(file, "Open Program…", #selector(openProgram), "o", target: self)
        item(file, "Open Project Folder…", #selector(openProject), "o", modifiers: [.command, .shift], target: self)
        item(file, "Refresh Project", #selector(refreshProject), "r", modifiers: [.command, .shift], target: self)
        file.addItem(.separator())
        item(file, "Save", #selector(saveCurrent), "s", target: self)
        item(file, "Save As…", #selector(saveAs), "s", modifiers: [.command, .shift], target: self)
        item(file, "Close Program", #selector(closeCurrent), "w", target: self)
        file.addItem(.separator())
        item(file, "Export Last Run as Text…", #selector(exportResult), target: self)
        item(file, "Export Report as PDF…", #selector(exportPDFReport), target: self)
        item(file, "Print Tables…", #selector(printTables), "p", target: self)
        let edit = section("Edit")
        item(edit, "Undo", Selector(("undo:")), "z")
        item(edit, "Redo", Selector(("redo:")), "z", modifiers: [.command, .shift])
        edit.addItem(.separator())
        item(edit, "Cut", #selector(NSText.cut(_:)), "x")
        item(edit, "Copy", #selector(NSText.copy(_:)), "c")
        item(edit, "Paste", #selector(NSText.paste(_:)), "v")
        item(edit, "Select All", #selector(NSText.selectAll(_:)), "a")
        let find = NSMenuItem(title: "Find…", action: #selector(findInActiveWindow(_:)), keyEquivalent: "f")
        find.target = self
        find.tag = NSTextFinder.Action.showFindInterface.rawValue
        edit.addItem(find)
        let view = section("View")
        item(view, "Hide Project Navigator", #selector(toggleNavigator), "0", target: self)
        item(view, "Expand Results", #selector(toggleResultsExpansion), "2", target: self)
        item(view, "Restore Default Layout", #selector(restoreDefaultLayout), target: self)
        view.addItem(.separator())
        item(view, "Wrap Source Lines", #selector(toggleWordWrap), target: self)
        item(view, "Wrap Text Output", #selector(toggleOutputWrap), target: self)
        item(view, "Line Numbers", #selector(toggleLineNumbers), target: self)
        item(view, "Visible Whitespace", #selector(toggleWhitespace), target: self)
        item(view, "Highlight Current Line", #selector(toggleCurrentLine), target: self)
        item(view, "Syntax Highlighting", #selector(toggleSyntax), target: self)
        view.addItem(.separator())
        item(view, "Increase Size", #selector(increaseSize), "+", target: self)
        item(view, "Decrease Size", #selector(decreaseSize), "-", target: self)
        item(view, "Reset Size", #selector(resetSize), "0", modifiers: [.command, .shift], target: self)
        let program = section("Program")
        item(program, "Run Program", #selector(runProgram), "r", target: self)
        item(program, "Stop", #selector(stopProgram), ".", target: self)
        item(program, "Go to Selected Diagnostic", #selector(goToDiagnostic), "l", target: self)
        let help = section("Help")
        item(help, "LocalStat Help", #selector(showHelp), target: self)
        item(help, "Compatibility and Limitations", #selector(showCompatibility), target: self)
        NSApp.mainMenu = menu
    }

    func buildWindow() {
        restoreLayoutPreferences()
        applyingLayout = true
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 780),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "LocalStat"
        window.minSize = NSSize(width: 760, height: 540)
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false
        let root = NSStackView()
        root.orientation = .vertical
        root.distribution = .fill
        root.spacing = 0
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            root.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            root.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor)
        ])
        runButton.target = self; runButton.action = #selector(runProgram)
        stopButton.target = self; stopButton.action = #selector(stopProgram); stopButton.isEnabled = false
        for button in [runButton, stopButton] { button.bezelStyle = .rounded }
        runButton.toolTip = "Run the entire editor buffer in a fresh local runtime (Command-R)"
        stopButton.toolTip = "Stop the current runtime (Command-period)"
        let folderButton = NSButton(title: "Open Project…", target: self, action: #selector(openProject))
        folderButton.bezelStyle = .rounded
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let appearanceLabel = NSTextField(labelWithString: "Appearance")
        appearanceLabel.font = .systemFont(ofSize: 12)
        for preference in AppearancePreference.allCases {
            appearancePopup.addItem(withTitle: preference.title)
        }
        appearancePopup.selectItem(withTitle: appearancePreference.title)
        appearancePopup.target = self
        appearancePopup.action = #selector(changeAppearance)
        appearancePopup.setAccessibilityLabel("Appearance")
        appearancePopup.toolTip = "Choose System, Light, or Dark appearance"
        appearancePopup.widthAnchor.constraint(equalToConstant: 100).isActive = true
        let toolbar = NSStackView(views: [folderButton, runButton, stopButton, spacer, appearanceLabel, appearancePopup])
        toolbar.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        toolbar.heightAnchor.constraint(equalToConstant: 44).isActive = true
        root.addArrangedSubview(toolbar)
        navigatorSplit.isVertical = true; navigatorSplit.dividerStyle = .thin
        navigatorSplit.delegate = self
        navigatorSplit.setContentHuggingPriority(.defaultLow, for: .vertical)
        let sidebar = navigatorPane
        sidebar.orientation = .vertical; sidebar.spacing = 8; sidebar.distribution = .fill
        sidebar.edgeInsets = NSEdgeInsets(top: 10, left: 8, bottom: 8, right: 8)
        projectLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        projectLabel.lineBreakMode = .byTruncatingMiddle
        sidebar.addArrangedSubview(projectLabel)
        let fileColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file"))
        fileColumn.title = "SAS Programs"; fileColumn.width = 180
        fileTable.addTableColumn(fileColumn); fileTable.headerView = nil
        fileTable.dataSource = self; fileTable.delegate = self
        fileTable.target = self; fileTable.doubleAction = #selector(openSelectedFile)
        fileTable.setAccessibilityLabel("Project programs")
        let fileScroll = scroll(fileTable)
        fileScroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        sidebar.addArrangedSubview(fileScroll)
        fileScroll.widthAnchor.constraint(equalTo: sidebar.widthAnchor, constant: -16).isActive = true
        projectHint.font = .systemFont(ofSize: 11); projectHint.textColor = .secondaryLabelColor
        sidebar.addArrangedSubview(projectHint)
        projectHint.widthAnchor.constraint(equalTo: sidebar.widthAnchor, constant: -16).isActive = true
        navigatorMinimumWidth = sidebar.widthAnchor.constraint(greaterThanOrEqualToConstant: 150)
        navigatorMinimumWidth?.isActive = true
        let vertical = editorResultsSplit
        vertical.isVertical = false; vertical.dividerStyle = .thin
        vertical.delegate = self
        tabs.delegate = self
        tabs.tabViewType = .topTabsBezelBorder
        tabs.setAccessibilityLabel("Open programs")
        vertical.addArrangedSubview(tabs)
        outputView.isEditable = false
        outputView.isRichText = false
        outputView.isSelectable = true
        outputView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        outputView.textContainerInset = NSSize(width: 10, height: 10)
        outputView.usesFindBar = true
        outputView.isHorizontallyResizable = true
        outputView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        outputView.textContainer?.containerSize = outputView.maxSize
        outputView.textContainer?.widthTracksTextView = false
        outputView.string = "Run a program to see its text output here. Each run starts a fresh session."
        outputView.setAccessibilityLabel("Program output")
        results.tabViewType = .noTabsNoBorder
        results.delegate = self
        let outItem = NSTabViewItem(identifier: "output"); outItem.label = "Output"; outItem.view = scroll(outputView)
        tableScroll.hasVerticalScroller = true
        tableScroll.hasHorizontalScroller = true
        tableScroll.autohidesScrollers = true
        setTableMessage("Run a program to see formatted tables here.")
        let tableItem = NSTabViewItem(identifier: "tables"); tableItem.label = "Tables"; tableItem.view = tableScroll
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("diagnostic"))
        column.title = "Runtime diagnostics · double-click an original-source line to navigate"
        column.width = 800
        diagnosticTable.addTableColumn(column)
        diagnosticTable.dataSource = self; diagnosticTable.delegate = self
        diagnosticTable.target = self; diagnosticTable.doubleAction = #selector(goToDiagnostic)
        diagnosticTable.setAccessibilityLabel("Runtime diagnostics")
        diagnosticTable.rowHeight = 23
        let diagItem = NSTabViewItem(identifier: "diagnostics"); diagItem.label = "Diagnostics"; diagItem.view = scroll(diagnosticTable)
        results.addTabViewItem(outItem); results.addTabViewItem(tableItem); results.addTabViewItem(diagItem)
        resultsSelector.segmentCount = 3
        for (index, title) in ["Output", "Tables (0)", "Diagnostics (0)"].enumerated() {
            resultsSelector.setLabel(title, forSegment: index)
        }
        resultsSelector.trackingMode = .selectOne
        resultsSelector.selectedSegment = 0
        resultsSelector.target = self
        resultsSelector.action = #selector(changeResultsView)
        resultsSelector.setAccessibilityLabel("Results view")
        expandResultsButton.target = self
        expandResultsButton.action = #selector(toggleResultsExpansion)
        expandResultsButton.bezelStyle = .rounded
        let resultsTitle = NSTextField(labelWithString: "Results")
        resultsTitle.font = .systemFont(ofSize: 12, weight: .semibold)
        let headerSpacer = NSView(); headerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let resultsHeader = NSStackView(views: [resultsTitle, resultsSelector, headerSpacer, expandResultsButton])
        resultsHeader.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        resultsHeader.spacing = 8
        resultsHeader.heightAnchor.constraint(equalToConstant: 38).isActive = true
        resultsContainer.orientation = .vertical
        resultsContainer.spacing = 0
        resultsContainer.addArrangedSubview(resultsHeader)
        resultsContainer.addArrangedSubview(results)
        resultsHeader.widthAnchor.constraint(equalTo: resultsContainer.widthAnchor).isActive = true
        results.widthAnchor.constraint(equalTo: resultsContainer.widthAnchor).isActive = true
        vertical.addArrangedSubview(resultsContainer)
        tabs.heightAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        resultsContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
        navigatorSplit.addArrangedSubview(sidebar); navigatorSplit.addArrangedSubview(vertical)
        root.addArrangedSubview(navigatorSplit)
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.setAccessibilityLabel("Run status")
        let status = NSStackView(views: [statusLabel])
        status.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        status.heightAnchor.constraint(equalToConstant: 29).isActive = true
        root.addArrangedSubview(status)
        for view in [toolbar, navigatorSplit, status] {
            view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        }
        window.contentView?.layoutSubtreeIfNeeded()
        applyNavigatorLayout()
        applyResultsLayout()
        applyingLayout = false
        applyPreferences()
    }

    func scroll(_ view: NSView) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true; scroll.documentView = view
        return scroll
    }

    @objc func restoreDefaultLayout() {
        preferences.reset("Layout")
        restoreLayoutPreferences()
        resultsExpanded = false
        expandResultsButton.title = "Expand Results"
        applyingLayout = true
        applyNavigatorLayout()
        applyResultsLayout()
        applyingLayout = false
        settingsController?.refresh()
    }

    private func restoreLayoutPreferences() {
        navigatorWidth = CGFloat(preferences.values.navigatorWidth)
        normalResultsFraction = CGFloat(preferences.values.resultsFraction)
        navigatorVisible = preferences.values.navigatorVisible
    }

    private func applyNavigatorLayout() {
        if navigatorVisible {
            navigatorPane.isHidden = false
            navigatorMinimumWidth?.isActive = true
            navigatorSplit.adjustSubviews()
            let maximum = max(150, navigatorSplit.bounds.width - 400)
            navigatorSplit.setPosition(min(max(navigatorWidth, 150), maximum), ofDividerAt: 0)
        } else {
            navigatorMinimumWidth?.isActive = false
            navigatorPane.isHidden = true
            navigatorSplit.adjustSubviews()
        }
    }

    private func applyResultsLayout() {
        let available = editorResultsSplit.bounds.height - editorResultsSplit.dividerThickness
        guard available >= 300 else { return }
        let fraction = resultsExpanded ? 0.60 : normalResultsFraction
        let resultsHeight = min(max(available * fraction, 140), available - 160)
        editorResultsSplit.setPosition(available - resultsHeight, ofDividerAt: 0)
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard !applyingLayout, let split = notification.object as? NSSplitView else { return }
        if split === navigatorSplit, navigatorVisible, navigatorPane.frame.width >= 150 {
            navigatorWidth = navigatorPane.frame.width
            preferences.update(notify: false) { $0.navigatorWidth = Double(navigatorWidth) }
        } else if split === editorResultsSplit, !resultsExpanded {
            let available = split.bounds.height - split.dividerThickness
            guard available >= 300 else { return }
            normalResultsFraction = resultsContainer.frame.height / available
            preferences.update(notify: false) { $0.resultsFraction = Double(normalResultsFraction) }
        }
    }

    @objc func toggleNavigator() {
        guard window != nil else { return }
        if navigatorVisible, navigatorPane.frame.width >= 150 { navigatorWidth = navigatorPane.frame.width }
        navigatorVisible.toggle()
        preferences.update(notify: false) { $0.navigatorVisible = navigatorVisible }
        applyingLayout = true
        applyNavigatorLayout()
        applyingLayout = false
        settingsController?.refresh()
    }

    @objc func toggleResultsExpansion() {
        guard window != nil else { return }
        if !resultsExpanded {
            let available = editorResultsSplit.bounds.height - editorResultsSplit.dividerThickness
            if available >= 300 { normalResultsFraction = resultsContainer.frame.height / available }
            preferences.update(notify: false) { $0.resultsFraction = Double(normalResultsFraction) }
        }
        resultsExpanded.toggle()
        expandResultsButton.title = resultsExpanded ? "Restore Editor" : "Expand Results"
        applyingLayout = true
        applyResultsLayout()
        applyingLayout = false
        settingsController?.refresh()
    }

    @objc func changeResultsView() {
        let index = resultsSelector.selectedSegment
        guard (0..<results.numberOfTabViewItems).contains(index) else { return }
        results.selectTabViewItem(at: index)
        switch index {
        case 0: window.makeFirstResponder(outputView)
        case 1: window.makeFirstResponder(tableScroll.documentView)
        default: window.makeFirstResponder(diagnosticTable)
        }
    }

    private func selectResults(at index: Int) {
        results.selectTabViewItem(at: index)
        resultsSelector.selectedSegment = index
    }

    func restoreAppearance() {
        preferences.reload()
        applyPreferences()
    }

    func applyAppearance(_ preference: AppearancePreference, persist: Bool = true) {
        preferences.update(persist: persist) { $0.appearance = preference }
    }

    @objc func changeAppearance() {
        guard let title = appearancePopup.selectedItem?.title,
              let preference = AppearancePreference.allCases.first(where: { $0.title == title }) else { return }
        applyAppearance(preference)
    }

    func loadProject() {
        if let path = UserDefaults.standard.string(forKey: "projectFolder"), FileManager.default.fileExists(atPath: path) {
            projectURL = URL(fileURLWithPath: path)
        } else {
            do {
                let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                let examples = support.appendingPathComponent("LocalStat/Examples")
                if !FileManager.default.fileExists(atPath: examples.path), let bundled = Bundle.main.resourceURL?.appendingPathComponent("Examples") {
                    try FileManager.default.createDirectory(at: examples.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: bundled, to: examples)
                }
                projectURL = examples
            } catch { showError(error) }
        }
        refreshProject()
        if let first = files.first { open(first) }
    }

    @objc func refreshProject() {
        files = []
        if let enumerator = FileManager.default.enumerator(at: projectURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let url as URL in enumerator where url.pathExtension.lowercased() == "sas" {
                files.append(url)
            }
        }
        files.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        projectLabel.stringValue = projectURL.lastPathComponent
        projectLabel.toolTip = projectURL.path
        projectHint.stringValue = "No SAS programs in this folder. Choose File > New Program to create one."
        projectHint.isHidden = !files.isEmpty
        fileTable.reloadData()
        updateControls()
    }

    @objc func openProject() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.prompt = "Open Project"
        if panel.runModal() == .OK, let url = panel.url {
            projectURL = url
            UserDefaults.standard.set(url.path, forKey: "projectFolder")
            refreshProject()
        }
    }
    @objc func openProgram() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.directoryURL = projectURL
        if panel.runModal() == .OK { panel.urls.forEach { open($0) } }
    }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        if window == nil {
            pendingOpenURLs.append(contentsOf: urls)
        } else {
            urls.forEach { open($0) }
        }
        sender.reply(toOpenOrPrint: .success)
    }
    @objc func openSelectedFile() {
        let row = fileTable.clickedRow
        if files.indices.contains(row) { open(files[row]) }
    }
    func open(_ url: URL) {
        if let doc = documents.first(where: { $0.url?.standardizedFileURL == url.standardizedFileURL }) {
            tabs.selectTabViewItem(withIdentifier: doc.id); return
        }
        do { addDocument(EditorDocument(url: url, source: try String(contentsOf: url, encoding: .utf8))) }
        catch { showError(error) }
    }
    @objc func newDocument(_ sender: Any?) { addDocument(EditorDocument(url: nil, source: "")) }
    func addDocument(_ doc: EditorDocument) {
        doc.applyPreferences(preferences.values)
        documents.append(doc)
        let item = NSTabViewItem(identifier: doc.id); item.label = doc.title; item.view = doc.scrollView
        doc.changed = { [weak self, weak doc, weak item] in
            guard let doc else { return }; item?.label = doc.title; self?.updateControls()
        }
        tabs.addTabViewItem(item); tabs.selectTabViewItem(item)
        window.makeFirstResponder(doc.textView)
        updateControls()
    }
    @objc func saveCurrent() { if let doc = current { _ = save(doc) } }
    @objc func saveAs() { if let doc = current { _ = save(doc, chooseURL: true) } }
    @discardableResult func save(_ doc: EditorDocument, chooseURL: Bool = false) -> Bool {
        var destination = doc.url
        if destination == nil || chooseURL {
            let panel = NSSavePanel(); panel.directoryURL = doc.url?.deletingLastPathComponent() ?? projectURL
            panel.nameFieldStringValue = doc.url?.lastPathComponent ?? "Untitled.sas"
            guard panel.runModal() == .OK, let url = panel.url else { return false }
            destination = url
        }
        guard let destination else { return false }
        if documents.contains(where: { $0.id != doc.id && $0.url?.standardizedFileURL == destination.standardizedFileURL }) {
            let alert = NSAlert()
            alert.messageText = "That file is already open in another tab."
            alert.informativeText = "Close its existing tab before saving another program to the same file."
            alert.runModal()
            return false
        }
        do {
            try doc.textView.string.write(to: destination, atomically: true, encoding: .utf8)
            doc.url = destination; doc.savedSource = doc.textView.string
            tabs.tabViewItems.first(where: { ($0.identifier as? UUID) == doc.id })?.label = doc.title
            refreshProject(); return true
        } catch { showError(error); return false }
    }
    func confirmClose(_ doc: EditorDocument) -> Bool {
        guard doc.isDirty else { return true }
        tabs.selectTabViewItem(withIdentifier: doc.id)
        let alert = NSAlert(); alert.messageText = "Save changes to \(doc.url?.lastPathComponent ?? "Untitled.sas")?"
        alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Discard Changes")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return save(doc)
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }
    @objc func closeCurrent() {
        closeWindowOrDocument(NSApp.keyWindow)
    }
    func closeWindowOrDocument(_ activeWindow: NSWindow?) {
        if let activeWindow, activeWindow === helpController?.window || activeWindow === settingsController?.window {
            activeWindow.close()
            return
        }
        guard let doc = current, confirmClose(doc), let item = tabs.selectedTabViewItem else { return }
        tabs.removeTabViewItem(item); documents.removeAll { $0.id == doc.id }; updateControls()
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { NSApp.terminate(nil); return false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        for doc in documents where !confirmClose(doc) { return .terminateCancel }
        if runner.isRunning {
            let alert = NSAlert(); alert.messageText = "Stop the running program and quit?"
            alert.addButton(withTitle: "Stop and Quit"); alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
            runner.cancel()
            Task {
                while runner.isRunning { try? await Task.sleep(nanoseconds: 50_000_000) }
                NSApp.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
        return .terminateNow
    }

    @objc func runProgram() {
        guard let doc = current, !runner.isRunning else { return }
        let request = RunRequest(source: doc.textView.string, sourceURL: doc.url, workingDirectory: projectURL)
        lastRunDocument = doc; lastResult = nil; diagnostics = []; diagnosticTable.reloadData()
        outputView.string = "Running locally. Output is buffered by the runtime until execution completes."
        setTableMessage("Running locally…")
        statusLabel.stringValue = "Running \(doc.url?.lastPathComponent ?? "Untitled.sas") · fresh session"
        runButton.isEnabled = false; stopButton.isEnabled = true
        Task {
            let result = await runner.run(request)
            lastResult = result; diagnostics = result.diagnostics
            outputView.string = result.output.isEmpty ? "No text output was produced." : ListingFormatter.aligned(result.output)
            if !result.tables.isEmpty {
                tableScroll.documentView = TableDocumentView(tables: result.tables)
                (tableScroll.documentView as? TableDocumentView)?.setScreenZoom(CGFloat(preferences.values.tableZoom))
            } else {
                setTableMessage(result.tableIssue ?? "This run produced no formatted PRINT, FREQ, or TABULATE tables.")
            }
            diagnosticTable.reloadData()
            applyOutputPreferences()
            resultsSelector.setLabel("Tables (\(result.tables.count))", forSegment: 1)
            resultsSelector.setLabel("Diagnostics (\(diagnostics.count))", forSegment: 2)
            if result.status != .success { selectResults(at: 2) }
            else if !result.tables.isEmpty { selectResults(at: 1) }
            else { selectResults(at: 0) }
            statusLabel.stringValue = "\(result.status.description) · \(doc.url?.lastPathComponent ?? "Untitled.sas") · fresh session"
            updateControls(); refreshProject()
        }
    }
    @objc func stopProgram() { runner.cancel(); statusLabel.stringValue = "Stopping runtime…" }
    private func setTableMessage(_ message: String) {
        let label = NSTextView(frame: NSRect(x: 0, y: 0, width: 612, height: 180))
        label.isEditable = false
        label.isSelectable = true
        label.drawsBackground = false
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.textContainerInset = NSSize(width: 16, height: 16)
        label.string = message
        label.setAccessibilityLabel("Formatted tables status")
        tableScroll.documentView = label
    }
    @objc func goToDiagnostic() {
        let row = diagnosticTable.selectedRow
        guard diagnostics.indices.contains(row), let result = lastResult else { return }
        guard let line = diagnostics[row].sourceLine else {
            statusLabel.stringValue = diagnostics[row].expandedLine == nil ? "This diagnostic has no source position." : "This position refers to macro-expanded code, not an original source line."
            return
        }
        guard let doc = lastRunDocument, documents.contains(where: { $0.id == doc.id }), doc.textView.string == result.request.source else {
            statusLabel.stringValue = "Source has changed or closed since this run. Run again to navigate accurately."
            return
        }
        tabs.selectTabViewItem(withIdentifier: doc.id); doc.goTo(line: line)
    }
    @objc func exportResult() {
        guard let result = lastResult else { return }
        let panel = NSSavePanel()
        panel.directoryURL = projectURL
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "run-results.txt"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try "\(result.status.description)\n\nDIAGNOSTICS\n\(result.diagnosticText)\nOUTPUT\n\(result.output)".write(to: url, atomically: true, encoding: .utf8)
                statusLabel.stringValue = "Exported raw run text to \(url.lastPathComponent)"
            }
            catch { showError(error) }
        }
    }
    @objc func exportPDFReport() {
        guard let result = lastResult else { return }
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let runtimeVersion = Bundle.main.resourceURL
            .flatMap { try? String(contentsOf: $0.appendingPathComponent("runtime-version.txt"), encoding: .utf8) }
            ?? "Runtime version unavailable"
        let report = RunReport(result: result, appVersion: appVersion, runtimeVersion: runtimeVersion)
        let panel = NSSavePanel()
        panel.directoryURL = projectURL
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = report.suggestedPDFName
        panel.title = "Export Run Report"
        panel.prompt = "Export"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try PDFReportRenderer.write(report, to: url)
                statusLabel.stringValue = "Exported PDF report to \(url.lastPathComponent)"
            } catch { showError(error) }
        }
    }
    @objc func printTables() {
        guard let tables = lastResult?.tables, !tables.isEmpty else { return }
        let operation = TablePrintRenderer.operation(for: tables)
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }
    func updateControls() {
        runButton.isEnabled = current != nil && !runner.isRunning
        stopButton.isEnabled = runner.isRunning
        window?.isDocumentEdited = documents.contains { $0.isDirty }
        window?.title = "\(current?.url?.lastPathComponent ?? "LocalStat") · \(projectURL.lastPathComponent)"
        if current == nil && !runner.isRunning {
            statusLabel.stringValue = "No programs open. Choose File > New Program or Open Program."
        } else if current != nil && statusLabel.stringValue.hasPrefix("No programs open.") {
            statusLabel.stringValue = "Ready · fresh session"
        }
    }
    func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        if tabView === results, let tabViewItem {
            resultsSelector.selectedSegment = results.indexOfTabViewItem(tabViewItem)
        } else {
            updateControls()
        }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { tableView === fileTable ? files.count : diagnostics.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let label = NSTextField(labelWithString: tableView === fileTable
            ? String(files[row].path.dropFirst(projectURL.path.count + 1)) : diagnostics[row].message)
        label.font = tableView === fileTable ? .systemFont(ofSize: 12) : preferences.values.outputFont
        label.lineBreakMode = .byTruncatingTail; label.toolTip = label.stringValue
        if tableView === diagnosticTable, diagnostics[row].message.hasPrefix("ERROR") { label.textColor = .systemRed }
        return label
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let value = preferences.values
        let toggles: [Selector: Bool] = [#selector(toggleWordWrap): value.editorWrap, #selector(toggleOutputWrap): value.outputWrap, #selector(toggleLineNumbers): value.lineNumbers,
                                       #selector(toggleWhitespace): value.invisibleCharacters, #selector(toggleCurrentLine): value.currentLineHighlight,
                                       #selector(toggleSyntax): value.syntaxHighlighting]
        if let action = menuItem.action, let state = toggles[action] { menuItem.state = state ? .on : .off; return true }
        switch menuItem.action {
        case #selector(toggleNavigator):
            menuItem.title = navigatorVisible ? "Hide Project Navigator" : "Show Project Navigator"
            return true
        case #selector(toggleResultsExpansion):
            menuItem.title = resultsExpanded ? "Restore Editor" : "Expand Results"
            return true
        case #selector(runProgram): return current != nil && !runner.isRunning
        case #selector(stopProgram): return runner.isRunning
        case #selector(saveCurrent), #selector(saveAs): return current != nil
        case #selector(closeCurrent):
            menuItem.title = activeAuxiliaryWindow == nil ? "Close Program" : "Close Window"
            return current != nil || activeAuxiliaryWindow != nil
        case #selector(increaseSize), #selector(decreaseSize), #selector(resetSize), #selector(findInActiveWindow(_:)):
            return settingsController == nil || NSApp.keyWindow !== settingsController?.window
        case #selector(exportResult), #selector(exportPDFReport): return lastResult != nil
        case #selector(printTables): return !(lastResult?.tables.isEmpty ?? true)
        default: return true
        }
    }
    func showError(_ error: Error) { NSAlert(error: error).runModal() }
    @objc func about() {
        let runtimeVersion = (try? String(contentsOf: Bundle.main.resourceURL!.appendingPathComponent("runtime-version.txt"), encoding: .utf8)) ?? "Runtime version unavailable"
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        let alert = NSAlert(); alert.messageText = "LocalStat \(appVersion) alpha"
        alert.informativeText = "Build \(build)\nNative SAS-language editor\n\(runtimeVersion)\n\nIndependent SAS-language subset. Not affiliated with SAS Institute. See Help for tested coverage and limitations."
        alert.runModal()
    }
    @objc func showCompatibility() {
        showHelpArticle("compatibility")
    }
}
