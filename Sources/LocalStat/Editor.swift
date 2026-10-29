import AppKit
import SASCore

final class LineRuler: NSRulerView {
    weak var editor: NSTextView?

    init(scrollView: NSScrollView, editor: NSTextView) {
        self.editor = editor
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = editor
        ruleThickness = 52
    }
    required init(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()
        guard let editor, let layout = editor.layoutManager, let container = editor.textContainer else { return }
        let visible = scrollView?.contentView.bounds ?? .zero
        let text = editor.string as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
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
            ("\(line)" as NSString).draw(at: NSPoint(x: ruleThickness - 24, y: y), withAttributes: attrs)
        }
    }
}

final class CodeTextView: NSTextView {
    var appearanceChanged: (() -> Void)?

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        guard !hasMarkedText(), let text = insertString as? String,
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
        guard let edit = EditorTextEditing.newline(in: string, selection: selectedRange()) else {
            super.insertNewline(sender)
            return
        }
        apply(edit)
    }

    override func insertTab(_ sender: Any?) {
        guard let edit = EditorTextEditing.indent(in: string, selection: selectedRange()) else {
            super.insertTab(sender)
            return
        }
        apply(edit)
    }

    override func insertBacktab(_ sender: Any?) {
        guard let edit = EditorTextEditing.outdent(in: string, selection: selectedRange()) else {
            return
        }
        apply(edit)
    }

    override func deleteBackward(_ sender: Any?) {
        guard let edit = EditorTextEditing.deleteBackward(in: string, selection: selectedRange()) else {
            super.deleteBackward(sender)
            return
        }
        apply(edit)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        appearanceChanged?()
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
        textView.appearanceChanged = { [weak self] in self?.highlight() }
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
        let source = textView.string
        let range = NSRange(source.startIndex..., in: source)
        storage.beginEditing()
        storage.addAttributes([.foregroundColor: NSColor.textColor,
                               .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)], range: range)
        let patterns: [(String, NSColor)] = [
            (#"(?i)\b(data|proc|run|quit|model|input|datalines|set|merge|by|if|then|else|do|end|output|retain|length|format|libname|filename|where|var|class|tables|keep|drop|rename|options|title|footnote)\b|%[a-zA-Z_]+|&[a-zA-Z_][a-zA-Z_0-9]*"#, .systemPurple),
            (#"'([^']|'')*'|\"([^\"]|\"\")*\""#, .systemBrown),
            (#"/\*[\s\S]*?\*/|(?m)^\s*\*[^;]*;"#, .secondaryLabelColor)
        ]
        for (pattern, color) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: source, range: range) {
                storage.addAttribute(.foregroundColor, value: color, range: match.range)
            }
        }
        storage.endEditing()
        textView.typingAttributes = [.foregroundColor: NSColor.textColor,
                                     .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)]
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
