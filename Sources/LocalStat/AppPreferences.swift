import AppKit
import SASCore

extension AppDelegate {
    var activeAuxiliaryWindow: NSWindow? {
        [helpController?.window, settingsController?.window].compactMap { $0 }.first { $0 === NSApp.keyWindow }
    }

    func applyPreferences() {
        let value = preferences.values
        NSApp?.appearance = value.appearance.appearance
        appearancePopup.selectItem(withTitle: value.appearance.title)
        documents.forEach { $0.applyPreferences(value) }
        applyOutputPreferences()
        (tableScroll.documentView as? TableDocumentView)?.setScreenZoom(CGFloat(value.tableZoom))
        helpController?.applyPreferences()
        settingsController?.refresh()
    }

    func applyOutputPreferences() {
        let value = preferences.values
        let origin = outputView.enclosingScrollView?.contentView.bounds.origin
        outputView.font = value.outputFont
        outputView.textColor = .textColor
        outputView.backgroundColor = .textBackgroundColor
        if let scroll = outputView.enclosingScrollView {
            configureWrapping(outputView, in: scroll, enabled: value.outputWrap)
            if let origin { scroll.contentView.scroll(to: origin); scroll.reflectScrolledClipView(scroll.contentView) }
        }
        diagnosticTable.rowHeight = max(23, value.outputFontSize + 8)
        diagnosticTable.reloadData()
    }

    @objc func showSettings() {
        if settingsController == nil { settingsController = SettingsWindowController(app: self) }
        settingsController?.refresh()
        settingsController?.showWindow(nil)
        settingsController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc func showHelp() { showHelpArticle(nil) }

    func showHelpArticle(_ id: String?) {
        do {
            if helpController == nil {
                let controller = try HelpWindowController(preferences: preferences)
                controller.openExample = { [weak self] source in
                    let document = EditorDocument(url: nil, source: source)
                    document.savedSource = ""
                    self?.addDocument(document)
                    self?.window.makeKeyAndOrderFront(nil)
                }
                helpController = controller
            }
            if let id { helpController?.showArticle(id) }
            helpController?.showWindow(nil)
            helpController?.window?.makeKeyAndOrderFront(nil)
        } catch { showError(error) }
    }

    @objc func findInActiveWindow(_ sender: NSMenuItem) {
        if NSApp.keyWindow === helpController?.window { helpController?.showFind(); return }
        NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: sender)
    }

    @objc func toggleWordWrap() { preferences.update { $0.editorWrap.toggle() } }
    @objc func toggleOutputWrap() { preferences.update { $0.outputWrap.toggle() } }
    @objc func toggleLineNumbers() { preferences.update { $0.lineNumbers.toggle() } }
    @objc func toggleWhitespace() { preferences.update { $0.invisibleCharacters.toggle() } }
    @objc func toggleCurrentLine() { preferences.update { $0.currentLineHighlight.toggle() } }
    @objc func toggleSyntax() { preferences.update { $0.syntaxHighlighting.toggle() } }

    enum SizeTarget { case editor, output, table, help }
    var activeSizeTarget: SizeTarget {
        if NSApp.keyWindow === helpController?.window, helpController != nil { return .help }
        if let responder = window?.firstResponder as? NSView {
            if responder === outputView || responder.isDescendant(of: diagnosticTable) { return .output }
            if responder.isDescendant(of: tableScroll) { return .table }
        }
        return .editor
    }
    @objc func increaseSize() { changeSize(by: 1) }
    @objc func decreaseSize() { changeSize(by: -1) }
    @objc func resetSize() { changeSize(by: 0) }
    func changeSize(by delta: Double) {
        let target = activeSizeTarget
        preferences.update {
            switch target {
            case .editor: $0.editorFontSize = delta == 0 ? 13 : $0.editorFontSize + delta
            case .output: $0.outputFontSize = delta == 0 ? 12 : $0.outputFontSize + delta
            case .table: $0.tableZoom = delta == 0 ? 1 : $0.tableZoom + delta * 0.1
            case .help: $0.helpFontSize = delta == 0 ? 14 : $0.helpFontSize + delta
            }
        }
    }
}
