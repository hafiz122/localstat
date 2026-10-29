import AppKit
import SASCore
import UniformTypeIdentifiers

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate,
    NSTableViewDataSource, NSTableViewDelegate, NSTabViewDelegate, NSMenuItemValidation {
    var window: NSWindow!
    private var compatibilityWindow: NSWindow?
    let fileTable = NSTableView()
    let diagnosticTable = NSTableView()
    let tabs = NSTabView()
    let results = NSTabView()
    let outputView = NSTextView()
    let statusLabel = NSTextField(labelWithString: "Open a program or create a new one.")
    let projectLabel = NSTextField(labelWithString: "Project")
    let projectHint = NSTextField(wrappingLabelWithString: "Double-click a program to open it. Paths are relative to this project folder.")
    let runButton = NSButton(title: "Run Program", target: nil, action: nil)
    let stopButton = NSButton(title: "Stop", target: nil, action: nil)
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

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        let edit = section("Edit")
        item(edit, "Undo", Selector(("undo:")), "z")
        item(edit, "Redo", Selector(("redo:")), "z", modifiers: [.command, .shift])
        edit.addItem(.separator())
        item(edit, "Cut", #selector(NSText.cut(_:)), "x")
        item(edit, "Copy", #selector(NSText.copy(_:)), "c")
        item(edit, "Paste", #selector(NSText.paste(_:)), "v")
        item(edit, "Select All", #selector(NSText.selectAll(_:)), "a")
        let find = NSMenuItem(title: "Find…", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "f")
        find.tag = NSTextFinder.Action.showFindInterface.rawValue
        edit.addItem(find)
        let program = section("Program")
        item(program, "Run Program", #selector(runProgram), "r", target: self)
        item(program, "Stop", #selector(stopProgram), ".", target: self)
        item(program, "Go to Selected Diagnostic", #selector(goToDiagnostic), "l", target: self)
        let help = section("Help")
        item(help, "Compatibility and Limitations", #selector(showCompatibility), target: self)
        NSApp.mainMenu = menu
    }

    func buildWindow() {
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
        let toolbar = NSStackView(views: [folderButton, runButton, stopButton, spacer])
        toolbar.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        toolbar.heightAnchor.constraint(equalToConstant: 44).isActive = true
        root.addArrangedSubview(toolbar)
        let split = NSSplitView()
        split.isVertical = true; split.dividerStyle = .thin
        split.setContentHuggingPriority(.defaultLow, for: .vertical)
        let sidebar = NSStackView()
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
        sidebar.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        let vertical = NSSplitView()
        vertical.isVertical = false; vertical.dividerStyle = .thin
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
        let outItem = NSTabViewItem(identifier: "output"); outItem.label = "Output"; outItem.view = scroll(outputView)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("diagnostic"))
        column.title = "Runtime diagnostics · double-click an original-source line to navigate"
        column.width = 800
        diagnosticTable.addTableColumn(column)
        diagnosticTable.dataSource = self; diagnosticTable.delegate = self
        diagnosticTable.target = self; diagnosticTable.doubleAction = #selector(goToDiagnostic)
        diagnosticTable.setAccessibilityLabel("Runtime diagnostics")
        diagnosticTable.rowHeight = 23
        let diagItem = NSTabViewItem(identifier: "diagnostics"); diagItem.label = "Diagnostics"; diagItem.view = scroll(diagnosticTable)
        results.addTabViewItem(outItem); results.addTabViewItem(diagItem)
        // Native tab bezels extend above their nominal bounds on newer macOS.
        // Reserve that space so the split view doesn't clip their labels.
        let resultContainer = NSView()
        results.translatesAutoresizingMaskIntoConstraints = false
        resultContainer.addSubview(results)
        NSLayoutConstraint.activate([
            results.leadingAnchor.constraint(equalTo: resultContainer.leadingAnchor),
            results.trailingAnchor.constraint(equalTo: resultContainer.trailingAnchor),
            results.topAnchor.constraint(equalTo: resultContainer.topAnchor, constant: 12),
            results.bottomAnchor.constraint(equalTo: resultContainer.bottomAnchor)
        ])
        vertical.addArrangedSubview(resultContainer)
        tabs.heightAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        results.heightAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
        split.addArrangedSubview(sidebar); split.addArrangedSubview(vertical)
        root.addArrangedSubview(split)
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.setAccessibilityLabel("Run status")
        let status = NSStackView(views: [statusLabel])
        status.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        status.heightAnchor.constraint(equalToConstant: 29).isActive = true
        root.addArrangedSubview(status)
        for view in [toolbar, split, status] {
            view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        }
        DispatchQueue.main.async {
            split.setPosition(215, ofDividerAt: 0)
            vertical.setPosition(420, ofDividerAt: 0)
        }
    }

    func scroll(_ view: NSView) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true; scroll.documentView = view
        return scroll
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
        projectHint.stringValue = files.isEmpty
            ? "No SAS programs in this folder. Choose File > New Program to create one."
            : "Double-click a program to open it. Paths are relative to this project folder."
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
        if let compatibilityWindow, NSApp.keyWindow === compatibilityWindow {
            compatibilityWindow.close()
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
        statusLabel.stringValue = "Running \(doc.url?.lastPathComponent ?? "Untitled.sas") · fresh session"
        runButton.isEnabled = false; stopButton.isEnabled = true
        Task {
            let result = await runner.run(request)
            lastResult = result; diagnostics = result.diagnostics
            outputView.string = result.output.isEmpty ? "No text output was produced." : ListingFormatter.aligned(result.output)
            diagnosticTable.reloadData()
            results.tabViewItems[1].label = "Diagnostics (\(diagnostics.count))"
            if result.status != .success { results.selectTabViewItem(at: 1) }
            else { results.selectTabViewItem(at: 0) }
            statusLabel.stringValue = "\(result.status.description) · \(doc.url?.lastPathComponent ?? "Untitled.sas") · fresh session"
            updateControls(); refreshProject()
        }
    }
    @objc func stopProgram() { runner.cancel(); statusLabel.stringValue = "Stopping runtime…" }
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
    func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) { updateControls() }
    func numberOfRows(in tableView: NSTableView) -> Int { tableView === fileTable ? files.count : diagnostics.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let label = NSTextField(labelWithString: tableView === fileTable
            ? String(files[row].path.dropFirst(projectURL.path.count + 1)) : diagnostics[row].message)
        label.font = tableView === fileTable ? .systemFont(ofSize: 12) : .monospacedSystemFont(ofSize: 11, weight: .regular)
        label.lineBreakMode = .byTruncatingTail; label.toolTip = label.stringValue
        if tableView === diagnosticTable, diagnostics[row].message.hasPrefix("ERROR") { label.textColor = .systemRed }
        return label
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(runProgram): return current != nil && !runner.isRunning
        case #selector(stopProgram): return runner.isRunning
        case #selector(saveCurrent), #selector(saveAs): return current != nil
        case #selector(closeCurrent): return current != nil || (compatibilityWindow != nil && NSApp.keyWindow === compatibilityWindow)
        case #selector(exportResult), #selector(exportPDFReport): return lastResult != nil
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
        if let compatibilityWindow {
            compatibilityWindow.makeKeyAndOrderFront(nil)
            return
        }
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("COMPATIBILITY.md") else { return }
        do {
            let source = try String(contentsOf: url, encoding: .utf8)
            let help = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 600),
                                styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            help.title = "Compatibility and Limitations"
            help.minSize = NSSize(width: 520, height: 360)
            help.isReleasedWhenClosed = false
            let text = NSTextView()
            text.isEditable = false
            text.isSelectable = true
            text.isRichText = false
            text.usesFindBar = true
            text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            text.textColor = .textColor
            text.textContainerInset = NSSize(width: 16, height: 16)
            text.isVerticallyResizable = true
            text.autoresizingMask = [.width]
            text.textContainer?.widthTracksTextView = true
            text.string = source
            text.setAccessibilityLabel("Compatibility documentation")
            let scroller = scroll(text)
            scroller.hasHorizontalScroller = false
            help.contentView = scroller
            compatibilityWindow = help
            help.center()
            help.makeKeyAndOrderFront(nil)
        } catch { showError(error) }
    }
}
