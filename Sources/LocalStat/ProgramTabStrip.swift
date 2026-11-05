import AppKit

@MainActor final class ProgramTabStrip: NSScrollView {
    static let stripHeight: CGFloat = 34
    var selectDocument: ((UUID) -> Void)?
    var closeDocument: ((UUID) -> Void)?
    private let content = NSView()
    private var orderedTabs: [ProgramTabView] = []
    private var selectedID: UUID?
    private var revealSelection = false
    private var previousSize = NSSize.zero
    var usesStudioStyle = false {
        didSet {
            drawsBackground = usesStudioStyle
            backgroundColor = usesStudioStyle ? StudioStyle.chrome : .clear
            orderedTabs.forEach { $0.usesStudioStyle = usesStudioStyle }
            needsDisplay = true
        }
    }

    init() {
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("programTabs")
        setAccessibilityLabel("Open programs")
        borderType = .noBorder
        drawsBackground = false
        hasHorizontalScroller = true
        hasVerticalScroller = false
        autohidesScrollers = true
        scrollerStyle = .overlay
        verticalScrollElasticity = .none
        documentView = content
        heightAnchor.constraint(equalToConstant: Self.stripHeight).isActive = true
    }
    required init?(coder: NSCoder) { nil }

    func synchronize(documents: [EditorDocument], selectedID: UUID?) {
        let existing = Dictionary(uniqueKeysWithValues: orderedTabs.map { ($0.documentID, $0) })
        let retainedIDs = Set(documents.map(\.id))
        orderedTabs.filter { !retainedIDs.contains($0.documentID) }.forEach { $0.removeFromSuperview() }
        orderedTabs = documents.map { document in
            let tab = existing[document.id] ?? ProgramTabView(documentID: document.id)
            if tab.superview == nil {
                tab.selectDocument = { [weak self] id in self?.selectDocument?(id) }
                tab.closeDocument = { [weak self] id in self?.closeDocument?(id) }
                content.addSubview(tab)
            }
            tab.update(document: document, selected: document.id == selectedID)
            tab.usesStudioStyle = usesStudioStyle
            return tab
        }
        self.selectedID = selectedID
        revealSelection = true
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    override func layout() {
        super.layout()
        var x: CGFloat = 0
        for tab in orderedTabs {
            tab.frame = NSRect(x: x, y: 0, width: tab.preferredWidth, height: Self.stripHeight)
            x += tab.preferredWidth
        }
        content.setFrameSize(NSSize(width: max(x, contentSize.width), height: contentSize.height))
        if revealSelection || previousSize != contentSize {
            revealSelection = false
            if let selected = orderedTabs.first(where: { $0.documentID == selectedID }) {
                content.scrollToVisible(selected.frame)
            }
        }
        previousSize = contentSize
    }
}

@MainActor private final class ProgramTabView: NSView {
    let documentID: UUID
    var selectDocument: ((UUID) -> Void)?
    var closeDocument: ((UUID) -> Void)?
    private let titleButton = NSButton()
    private let closeButton = NSButton(title: "×", target: nil, action: nil)
    private var selected = false
    private var filename = "Untitled.sas"
    private var isDirty = false
    private var filePath: String?
    var usesStudioStyle = false {
        didSet {
            updateTitle()
            needsDisplay = true
        }
    }
    var preferredWidth: CGFloat {
        min(240, max(130, titleButton.intrinsicContentSize.width + 42))
    }

    init(documentID: UUID) {
        self.documentID = documentID
        super.init(frame: .zero)
        titleButton.setButtonType(.toggle)
        titleButton.bezelStyle = .recessed
        titleButton.isBordered = false
        titleButton.cell?.lineBreakMode = .byTruncatingMiddle
        titleButton.cell?.usesSingleLineMode = true
        titleButton.focusRingType = .exterior
        titleButton.target = self; titleButton.action = #selector(selectTab)
        closeButton.bezelStyle = .recessed
        closeButton.showsBorderOnlyWhileMouseInside = true
        closeButton.font = .systemFont(ofSize: 16)
        closeButton.focusRingType = .exterior
        closeButton.target = self; closeButton.action = #selector(closeTab)
        addSubview(titleButton); addSubview(closeButton)
    }
    required init?(coder: NSCoder) { nil }

    func update(document: EditorDocument, selected: Bool) {
        self.selected = selected
        filename = document.url?.lastPathComponent ?? "Untitled.sas"
        isDirty = document.isDirty
        filePath = document.url?.path
        titleButton.state = selected ? .on : .off
        updateTitle()
        closeButton.setAccessibilityLabel("Close \(filename)")
        closeButton.toolTip = "Close \(filename)"
        needsLayout = true
        needsDisplay = true
    }

    private func updateTitle() {
        let titleText = filename + (isDirty ? " *" : "")
        let title = NSAttributedString(string: titleText, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: selected ? .semibold : .regular),
            .foregroundColor: usesStudioStyle ? (selected ? StudioStyle.ink : StudioStyle.muted) : NSColor.labelColor
        ])
        titleButton.attributedTitle = title
        titleButton.attributedAlternateTitle = title
        titleButton.setAccessibilityLabel("\(filename)\(isDirty ? ", unsaved changes" : ""), \(selected ? "selected" : "not selected")")
        titleButton.toolTip = filePath ?? filename
    }

    override func layout() {
        super.layout()
        titleButton.frame = NSRect(x: 8, y: 5, width: max(0, bounds.width - 40), height: 24)
        closeButton.frame = NSRect(x: bounds.width - 28, y: 5, width: 24, height: 24)
    }

    override func draw(_ dirtyRect: NSRect) {
        (usesStudioStyle ? (selected ? NSColor.white : StudioStyle.chrome) :
            (selected ? NSColor.controlBackgroundColor : NSColor.windowBackgroundColor)).setFill()
        bounds.fill()
        (usesStudioStyle ? StudioStyle.line : NSColor.separatorColor).setFill()
        NSRect(x: bounds.maxX - 1, y: 0, width: 1, height: bounds.height).fill()
        if !selected {
            NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
        }
        if selected {
            (usesStudioStyle ? StudioStyle.blue : NSColor.controlAccentColor).setFill()
            NSRect(x: 0, y: bounds.maxY - 3, width: bounds.width, height: 3).fill()
        }
    }

    @objc private func selectTab() { selectDocument?(documentID) }
    @objc private func closeTab() { closeDocument?(documentID) }
}
