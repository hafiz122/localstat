import AppKit
import WebKit

struct HelpArticle: Decodable, Equatable {
    let id: String
    let title: String
    let section: String
    let file: String
    let example: String?
}

struct DocumentationLibrary {
    let root: URL
    let articles: [HelpArticle]
    private let searchableText: [String: String]

    init(root: URL) throws {
        self.root = root.standardizedFileURL
        articles = try JSONDecoder().decode([HelpArticle].self, from: Data(contentsOf: root.appendingPathComponent("contents.json")))
        var seen = Set<String>()
        var text: [String: String] = [:]
        for article in articles {
            guard seen.insert(article.id).inserted, article.file == (article.file as NSString).lastPathComponent,
                  article.file.hasSuffix(".html") else { throw CocoaError(.fileReadCorruptFile) }
            let html = try String(contentsOf: root.appendingPathComponent(article.file), encoding: .utf8)
            text[article.id] = Self.normalized(article.title + " " + article.section + " " + html
                .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\""))
            if let example = article.example {
                guard example == (example as NSString).lastPathComponent else { throw CocoaError(.fileReadCorruptFile) }
                _ = try String(contentsOf: root.appendingPathComponent("Examples/\(example)"), encoding: .utf8)
            }
        }
        searchableText = text
    }
    static func bundled() throws -> DocumentationLibrary {
        let main = Bundle.main.resourceURL?.appendingPathComponent("Help")
        let root = main.flatMap { FileManager.default.fileExists(atPath: $0.appendingPathComponent("contents.json").path) ? $0 : nil }
            ?? Bundle.module.url(forResource: "Help", withExtension: nil)
        guard let root else { throw CocoaError(.fileNoSuchFile) }
        return try DocumentationLibrary(root: root)
    }
    static func normalized(_ text: String) -> String { text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) }
    func search(_ query: String) -> [HelpArticle] {
        let words = Self.normalized(query).split(whereSeparator: \.isWhitespace)
        return articles.filter { article in words.allSatisfy { searchableText[article.id, default: ""].contains($0) } }
    }
    func example(for article: HelpArticle) -> String? {
        article.example.flatMap { try? String(contentsOf: root.appendingPathComponent("Examples/\($0)"), encoding: .utf8) }
    }
}

private final class HelpWebView: WKWebView {
    var appearanceChanged: (() -> Void)?
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); appearanceChanged?() }
}

@MainActor final class HelpWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, WKNavigationDelegate {
    let library: DocumentationLibrary
    let searchField = NSSearchField()
    let contents = NSTableView()
    let findField = NSSearchField()
    let webView: WKWebView
    private let preferences: IDEPreferences
    private let backButton = NSButton(title: "Back", target: nil, action: nil)
    private let forwardButton = NSButton(title: "Forward", target: nil, action: nil)
    private let copyButton = NSButton(title: "Copy Code", target: nil, action: nil)
    private let exampleButton = NSButton(title: "Open Example", target: nil, action: nil)
    private let readingSize = NSPopUpButton()
    private let findStatus = NSTextField(labelWithString: "")
    private let loadingLabel = NSTextField(labelWithString: "Loading article…")
    private let findBar = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: "No matching articles.")
    private var filtered: [HelpArticle]
    private var history: [String] = []
    private var historyIndex = -1
    private var selecting = false
    private(set) var currentArticle: HelpArticle?
    private(set) var loadedArticleID: String?
    var openExample: ((String) -> Void)?

    init(preferences: IDEPreferences, library: DocumentationLibrary? = nil) throws {
        self.preferences = preferences
        self.library = try library ?? DocumentationLibrary.bundled()
        filtered = self.library.articles
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = HelpWebView(frame: .zero, configuration: configuration)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 700),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "LocalStat Help"; window.minSize = NSSize(width: 680, height: 480)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        webView.navigationDelegate = self
        (webView as? HelpWebView)?.appearanceChanged = { [weak self] in self?.applyPreferences() }
        let root = NSStackView(); root.orientation = .vertical; root.spacing = 0
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor), root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            root.topAnchor.constraint(equalTo: window.contentView!.topAnchor), root.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor)
        ])
        for (button, action) in [(backButton, #selector(goBack)), (forwardButton, #selector(goForward)),
                                  (copyButton, #selector(copyCode)), (exampleButton, #selector(openCode))] {
            button.target = self; button.action = action; button.bezelStyle = .rounded
        }
        readingSize.addItems(withTitles: (10...28).map { "\($0) pt" })
        readingSize.selectItem(at: Int(preferences.values.helpFontSize) - 10)
        readingSize.setAccessibilityLabel("Help reading size")
        readingSize.target = self; readingSize.action = #selector(changeReadingSize)
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let toolbar = NSStackView(views: [backButton, forwardButton, copyButton, exampleButton, spacer, readingSize])
        toolbar.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        root.addArrangedSubview(toolbar)
        let split = NSSplitView(); split.isVertical = true; split.dividerStyle = .thin
        let sidebar = NSStackView(); sidebar.orientation = .vertical; sidebar.spacing = 8
        sidebar.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        searchField.placeholderString = "Search Help"
        searchField.setAccessibilityLabel("Search all documentation")
        searchField.delegate = self
        contents.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("article")))
        contents.headerView = nil; contents.dataSource = self; contents.delegate = self; contents.rowHeight = 42
        contents.setAccessibilityLabel("Documentation contents")
        let scroller = NSScrollView(); scroller.hasVerticalScroller = true; scroller.documentView = contents
        sidebar.addArrangedSubview(searchField); sidebar.addArrangedSubview(scroller); sidebar.addArrangedSubview(emptyLabel)
        for view in [searchField, scroller] { view.widthAnchor.constraint(equalTo: sidebar.widthAnchor, constant: -16).isActive = true }
        sidebar.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        emptyLabel.font = .systemFont(ofSize: 12); emptyLabel.isHidden = true
        let reader = NSStackView(); reader.orientation = .vertical; reader.spacing = 0
        findField.placeholderString = "Find in this article"
        findField.delegate = self; findField.target = self; findField.action = #selector(findNext)
        findField.setAccessibilityLabel("Find in this article")
        let closeFind = NSButton(title: "Done", target: self, action: #selector(hideFind))
        closeFind.bezelStyle = .rounded
        findBar.addArrangedSubview(findField); findBar.addArrangedSubview(findStatus); findBar.addArrangedSubview(closeFind)
        findBar.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        findBar.isHidden = true
        reader.addArrangedSubview(findBar); reader.addArrangedSubview(loadingLabel); reader.addArrangedSubview(webView)
        findBar.widthAnchor.constraint(equalTo: reader.widthAnchor).isActive = true
        webView.widthAnchor.constraint(equalTo: reader.widthAnchor).isActive = true
        reader.widthAnchor.constraint(greaterThanOrEqualToConstant: 360).isActive = true
        split.addArrangedSubview(sidebar); split.addArrangedSubview(reader)
        root.addArrangedSubview(split)
        toolbar.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        split.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        split.setContentHuggingPriority(.defaultLow, for: .vertical)
        window.contentView?.layoutSubtreeIfNeeded()
        split.setPosition(240, ofDividerAt: 0)
        window.center()
        if let first = self.library.articles.first { showArticle(first.id) }
    }
    required init?(coder: NSCoder) { nil }

    func showArticle(_ id: String, recordHistory: Bool = true) {
        guard let article = library.articles.first(where: { $0.id == id }) else { return }
        if recordHistory, currentArticle?.id != id {
            history = Array(history.prefix(historyIndex + 1)); history.append(id); historyIndex = history.count - 1
        }
        currentArticle = article
        loadedArticleID = nil
        loadingLabel.stringValue = "Loading article…"; loadingLabel.isHidden = false
        findField.stringValue = ""; findStatus.stringValue = ""; findBar.isHidden = true
        if !filtered.contains(article) { searchField.stringValue = ""; filtered = library.articles; contents.reloadData() }
        selecting = true
        if let index = filtered.firstIndex(of: article) { contents.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
        selecting = false
        webView.loadFileURL(library.root.appendingPathComponent(article.file), allowingReadAccessTo: library.root)
        window?.title = "\(article.title) | LocalStat Help"
        backButton.isEnabled = historyIndex > 0; forwardButton.isEnabled = historyIndex + 1 < history.count
        let hasExample = library.example(for: article) != nil
        copyButton.isEnabled = hasExample; exampleButton.isEnabled = hasExample
    }
    func applyPreferences() {
        readingSize.selectItem(at: Int(preferences.values.helpFontSize) - 10)
        let dark = window?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let script = "document.documentElement.dataset.appearance='\(dark ? "dark" : "light")';document.documentElement.style.setProperty('--reading-size','\(preferences.values.helpFontSize)px');"
        webView.evaluateJavaScript(script, completionHandler: nil)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadedArticleID = library.articles.first { $0.file == webView.url?.lastPathComponent }?.id
        loadingLabel.isHidden = true
        applyPreferences()
        if !searchField.stringValue.isEmpty {
            let config = WKFindConfiguration(); config.wraps = true
            webView.find(searchField.stringValue, configuration: config) { _ in }
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { showLoadError(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { showLoadError(error) }
    }
    private func showLoadError(_ error: Error) {
        loadingLabel.stringValue = "Could not load this article: \(error.localizedDescription)"
        loadingLabel.isHidden = false
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if url.scheme == "localstat-help" {
            decisionHandler(.cancel); showArticle(String(url.absoluteString.dropFirst("localstat-help:".count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))); return
        }
        if url.isFileURL, url.standardizedFileURL.path.hasPrefix(library.root.path + "/") { decisionHandler(.allow); return }
        if url.absoluteString == "about:blank" { decisionHandler(.allow); return }
        decisionHandler(.cancel)
        if action.navigationType == .linkActivated, ["https", "http"].contains(url.scheme) { NSWorkspace.shared.open(url) }
    }
    func controlTextDidChange(_ notification: Notification) {
        if notification.object as? NSSearchField === searchField {
            filtered = library.search(searchField.stringValue)
            selecting = true; contents.reloadData(); selecting = false
            emptyLabel.isHidden = !filtered.isEmpty
        } else { findNext() }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let article = filtered[row]
        let title = NSTextField(labelWithString: article.title); title.font = .systemFont(ofSize: 12, weight: .medium)
        title.lineBreakMode = .byTruncatingTail
        let section = NSTextField(labelWithString: article.section); section.font = .systemFont(ofSize: 10); section.textColor = .labelColor
        let cell = NSStackView(views: [title, section]); cell.orientation = .vertical; cell.alignment = .leading; cell.spacing = 2
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !selecting, filtered.indices.contains(contents.selectedRow) else { return }
        let id = filtered[contents.selectedRow].id
        if currentArticle?.id != id { showArticle(id) }
    }
    @objc private func goBack() { guard historyIndex > 0 else { return }; historyIndex -= 1; showArticle(history[historyIndex], recordHistory: false) }
    @objc private func goForward() { guard historyIndex + 1 < history.count else { return }; historyIndex += 1; showArticle(history[historyIndex], recordHistory: false) }
    @objc func copyCode() {
        guard let article = currentArticle, let source = library.example(for: article) else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(source, forType: .string)
    }
    @objc func openCode() {
        guard let article = currentArticle, let source = library.example(for: article) else { return }
        openExample?(source)
    }
    @objc private func changeReadingSize() { preferences.update { $0.helpFontSize = Double(readingSize.indexOfSelectedItem + 10) } }
    func showFind() { findBar.isHidden = false; window?.makeFirstResponder(findField) }
    @objc private func hideFind() { findBar.isHidden = true; window?.makeFirstResponder(webView) }
    @objc private func findNext() {
        guard !findField.stringValue.isEmpty else { findStatus.stringValue = ""; return }
        let config = WKFindConfiguration(); config.wraps = true
        webView.find(findField.stringValue, configuration: config) { [weak self] result in self?.findStatus.stringValue = result.matchFound ? "" : "No matches" }
    }
}
