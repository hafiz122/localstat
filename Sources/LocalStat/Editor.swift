import AppKit
import SASCore

final class LineRuler: NSRulerView {
    weak var editor: NSTextView?
    var palette = EditorTheme.native.palette
    var usesStudioStyle = false
    var labelSize: CGFloat = 11

    init(scrollView: NSScrollView, editor: NSTextView) {
        self.editor = editor
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = editor
        ruleThickness = 52
    }
    required init(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        (usesStudioStyle ? StudioStyle.chrome : palette.background).setFill()
        bounds.fill()
        if usesStudioStyle {
            StudioStyle.line.setFill()
            NSRect(x: bounds.maxX - 1, y: bounds.minY, width: 1, height: bounds.height).fill()
        }
        guard let editor, let layout = editor.layoutManager, let container = editor.textContainer else { return }
        let visible = scrollView?.contentView.bounds ?? .zero
        let text = editor.string as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: labelSize, weight: .regular),
            .foregroundColor: usesStudioStyle ? StudioStyle.muted : palette.comment
        ]
        var offset = 0, line = 1
        while offset < text.length {
            let glyph = layout.glyphIndexForCharacter(at: offset)
            let frame = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let y = frame.minY + editor.textContainerInset.height - visible.minY
            if y > bounds.maxY { break }
            if y + frame.height >= 0 {
                let label = "\(line)" as NSString
                label.draw(at: NSPoint(x: ruleThickness - label.size(withAttributes: attrs).width - 10, y: y), withAttributes: attrs)
            }
            offset = NSMaxRange(text.lineRange(for: NSRange(location: offset, length: 0)))
            line += 1
        }
        if text.length == 0 || text.hasSuffix("\n") {
            layout.ensureLayout(for: container)
            let y = layout.extraLineFragmentRect.minY + editor.textContainerInset.height - visible.minY
            let label = "\(line)" as NSString
            label.draw(at: NSPoint(x: ruleThickness - label.size(withAttributes: attrs).width - 10, y: y), withAttributes: attrs)
        }
    }
}

final class CodeTextView: NSTextView {
    var appearanceChanged: (() -> Void)?
    var automaticIndentation = true
    var bracketPairing = true
    var indentWidth = EditorTextEditing.defaultIndentWidth
    var currentLineColor: NSColor?

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        guard bracketPairing, !hasMarkedText(), let text = insertString as? String,
              (text as NSString).length == 1 else {
            super.insertText(insertString, replacementRange: replacementRange)
            return
        }
        let range = effectiveRange(replacementRange)
        if let edit = EditorTextEditing.openingBracket(text, in: string, selection: range) {
            apply(edit)
        } else if let edit = EditorTextEditing.closingBracket(text, in: string, selection: range) {
            apply(edit)
        } else {
            super.insertText(insertString, replacementRange: replacementRange)
        }
    }

    override func insertNewline(_ sender: Any?) {
        guard automaticIndentation, let edit = EditorTextEditing.newline(in: string, selection: selectedRange(), indentWidth: indentWidth) else {
            super.insertNewline(sender)
            return
        }
        apply(edit)
    }

    override func insertTab(_ sender: Any?) {
        guard let edit = EditorTextEditing.indent(in: string, selection: selectedRange(), indentWidth: indentWidth) else {
            super.insertTab(sender)
            return
        }
        apply(edit)
    }

    override func insertBacktab(_ sender: Any?) {
        guard let edit = EditorTextEditing.outdent(in: string, selection: selectedRange(), indentWidth: indentWidth) else {
            return
        }
        apply(edit)
    }

    override func deleteBackward(_ sender: Any?) {
        guard bracketPairing, let edit = EditorTextEditing.deleteBackward(in: string, selection: selectedRange()) else {
            super.deleteBackward(sender)
            return
        }
        apply(edit)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        appearanceChanged?()
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let color = currentLineColor, let layout = layoutManager, let container = textContainer else { return }
        layout.ensureLayout(for: container)
        let offset = min(selectedRange().location, (string as NSString).length)
        let line: NSRect
        if offset == (string as NSString).length && (string.isEmpty || string.hasSuffix("\n")) {
            line = layout.extraLineFragmentRect
        } else {
            let glyph = layout.glyphIndexForCharacter(at: min(offset, max(0, (string as NSString).length - 1)))
            line = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        }
        color.setFill()
        NSRect(x: bounds.minX, y: line.minY + textContainerInset.height, width: bounds.width, height: line.height).intersection(rect).fill()
    }

    private func effectiveRange(_ replacementRange: NSRange) -> NSRange {
        replacementRange.location == NSNotFound ? selectedRange() : replacementRange
    }

    private func apply(_ edit: EditorTextEdit) {
        if edit.replacementRange.length != 0 || !edit.replacement.isEmpty {
            super.insertText(edit.replacement, replacementRange: edit.replacementRange)
        }
        setSelectedRange(edit.selectedRange)
    }
}

final class EditorDocument: NSObject, NSTextViewDelegate {
    let id = UUID()
    var url: URL?
    var savedSource: String
    var changed: (() -> Void)?
    let textView = CodeTextView()
    let scrollView = NSScrollView()
    var ruler: LineRuler!
    private var highlightWork: DispatchWorkItem?
    private var preferences = PreferenceValues()
    var isDirty: Bool { textView.string != savedSource }
    var title: String { (url?.lastPathComponent ?? "Untitled.sas") + (isDirty ? " •" : "") }

    init(url: URL?, source: String) {
        self.url = url
        self.savedSource = source
        super.init()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainerInset = NSSize(width: 10, height: 12)
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.setAccessibilityLabel("SAS source editor")
        textView.string = source
        textView.delegate = self
        textView.appearanceChanged = { [weak self] in
            self?.highlight()
            self?.ruler?.needsDisplay = true
        }
        scrollView.documentView = textView
        ruler = LineRuler(scrollView: scrollView, editor: textView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        highlight()
    }

    @objc private func scrolled() { ruler.needsDisplay = true }

    func textViewDidChangeSelection(_ notification: Notification) { textView.needsDisplay = true }

    func applyPreferences(_ value: PreferenceValues) {
        let undo = textView.undoManager
        let registrationEnabled = undo?.isUndoRegistrationEnabled == true
        if registrationEnabled { undo?.disableUndoRegistration() }
        defer { if registrationEnabled { undo?.enableUndoRegistration() } }
        preferences = value
        let selected = textView.selectedRanges
        let origin = scrollView.contentView.bounds.origin
        let palette = value.theme.palette
        if scrollView.appearance?.name != value.theme.appearance?.name { scrollView.appearance = value.theme.appearance }
        textView.backgroundColor = palette.background
        textView.insertionPointColor = palette.text
        textView.selectedTextAttributes = [.backgroundColor: palette.selection, .foregroundColor: palette.selectedText]
        textView.automaticIndentation = value.automaticIndentation
        textView.bracketPairing = value.bracketPairing
        textView.indentWidth = value.indentWidth
        textView.currentLineColor = value.currentLineHighlight ? palette.currentLine : nil
        textView.layoutManager?.showsInvisibleCharacters = value.invisibleCharacters
        scrollView.rulersVisible = value.lineNumbers
        configureWrapping(textView, in: scrollView, enabled: value.editorWrap)
        ruler.palette = palette
        ruler.usesStudioStyle = value.theme == .sasStudio && value.appearance == .sasStudio
        ruler.labelSize = max(10, CGFloat(value.editorFontSize) - 2)
        highlight()
        textView.selectedRanges = selected
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        ruler.needsDisplay = true
        textView.needsDisplay = true
    }

    func textDidChange(_ notification: Notification) {
        ruler.needsDisplay = true
        changed?()
        highlightWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.highlight() }
        highlightWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    func highlight() {
        guard let storage = textView.textStorage else { return }
        let undo = textView.undoManager
        let registrationEnabled = undo?.isUndoRegistrationEnabled == true
        if registrationEnabled { undo?.disableUndoRegistration() }
        defer { if registrationEnabled { undo?.enableUndoRegistration() } }
        let source = textView.string
        let range = NSRange(source.startIndex..., in: source)
        let palette = preferences.theme.palette
        let font = preferences.editorFont
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = (preferences.lineSpacing - 1) * Double(font.ascender - font.descender + font.leading)
        textView.defaultParagraphStyle = paragraph
        storage.beginEditing()
        storage.addAttributes([.foregroundColor: palette.text, .font: font, .paragraphStyle: paragraph], range: range)
        let patterns: [(String, NSColor)] = [
            (#"(?i)\b(data|proc|run|quit|model|input|datalines|set|merge|by|if|then|else|do|end|output|retain|length|format|libname|filename|where|var|class|tables|keep|drop|rename|options|title|footnote)\b|%[a-zA-Z_]+|&[a-zA-Z_][a-zA-Z_0-9]*"#, palette.keyword),
            (#"'([^']|'')*'|\"([^\"]|\"\")*\""#, palette.string),
            (#"/\*[\s\S]*?\*/|(?m)^\s*\*[^;]*;"#, palette.comment)
        ]
        for (pattern, color) in preferences.syntaxHighlighting ? patterns : [] {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: source, range: range) {
                storage.addAttribute(.foregroundColor, value: color, range: match.range)
            }
        }
        storage.endEditing()
        textView.typingAttributes = [.foregroundColor: palette.text, .font: font, .paragraphStyle: paragraph]
    }

    func goTo(line: Int) {
        guard line > 0 else { return }
        let source = textView.string as NSString
        var offset = 0
        for _ in 1..<line {
            guard offset < source.length else { return }
            offset = NSMaxRange(source.lineRange(for: NSRange(location: offset, length: 0)))
        }
        let range = source.lineRange(for: NSRange(location: offset, length: 0))
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        textView.window?.makeFirstResponder(textView)
    }
}
