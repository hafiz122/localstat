import AppKit
import SASCore

enum AppearancePreference: String, Codable, CaseIterable {
    case sasStudio, system, light, dark
    var title: String { self == .sasStudio ? "SAS Studio" : rawValue.capitalized }
    var appearance: NSAppearance? {
        switch self {
        case .sasStudio: NSAppearance(named: .aqua)
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

enum EditorTheme: String, Codable, CaseIterable {
    case sasStudio, native, sasClassic, paper, midnight, contrastLight, contrastDark
    var title: String {
        switch self {
        case .sasStudio: "SAS Studio"
        case .native: "Native"
        case .sasClassic: "SAS Classic"
        case .paper: "Paper"
        case .midnight: "Midnight"
        case .contrastLight: "High Contrast Light"
        case .contrastDark: "High Contrast Dark"
        }
    }
    var appearance: NSAppearance? {
        switch self {
        case .sasStudio, .native: nil
        case .sasClassic, .paper, .contrastLight: NSAppearance(named: .aqua)
        case .midnight, .contrastDark: NSAppearance(named: .darkAqua)
        }
    }
    var palette: EditorPalette {
        switch self {
        case .sasStudio:
            EditorPalette(background: .textBackgroundColor, text: .textColor,
                          keyword: .init(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(srgbRed: 0.67, green: 0.79, blue: 1, alpha: 1) : NSColor(srgbRed: 0, green: 0.24, blue: 0.62, alpha: 1) },
                          string: .init(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(srgbRed: 0.96, green: 0.72, blue: 0.90, alpha: 1) : NSColor(srgbRed: 0.48, green: 0.14, blue: 0.48, alpha: 1) },
                          comment: .init(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(srgbRed: 0.58, green: 0.84, blue: 0.67, alpha: 1) : NSColor(srgbRed: 0.09, green: 0.42, blue: 0.23, alpha: 1) },
                          selection: .selectedTextBackgroundColor, selectedText: .selectedTextColor,
                          currentLine: .controlBackgroundColor)
        case .native:
            EditorPalette(background: .textBackgroundColor, text: .textColor,
                          keyword: .init(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? EditorTheme.midnight.palette.keyword : EditorTheme.paper.palette.keyword },
                          string: .init(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? EditorTheme.midnight.palette.string : EditorTheme.paper.palette.string },
                          comment: .init(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? EditorTheme.midnight.palette.comment : EditorTheme.paper.palette.comment }, selection: .selectedTextBackgroundColor,
                          selectedText: .selectedTextColor, currentLine: .controlBackgroundColor)
        case .sasClassic:
            EditorPalette("FFFFFF", "202020", "003C9E", "7A247A", "176B3A", "C9DEFF", "202020", "F2F6FC")
        case .paper:
            EditorPalette("FAF7F0", "252525", "663399", "814600", "556454", "B7D6FF", "111111", "EFEADF")
        case .midnight:
            EditorPalette("19212B", "E5EDF5", "C6A0FF", "F5C27A", "A4B0BF", "374D70", "FFFFFF", "232F3E")
        case .contrastLight:
            EditorPalette("FFFFFF", "000000", "400080", "703600", "3D3D3D", "004999", "FFFFFF", "F0F0F0")
        case .contrastDark:
            EditorPalette("000000", "FFFFFF", "E5B4FF", "FFD699", "CBCBCB", "004999", "FFFFFF", "202020")
        }
    }
}

struct EditorPalette {
    let background, text, keyword, string, comment, selection, selectedText, currentLine: NSColor
    init(background: NSColor, text: NSColor, keyword: NSColor, string: NSColor, comment: NSColor,
         selection: NSColor, selectedText: NSColor, currentLine: NSColor) {
        self.background = background; self.text = text; self.keyword = keyword; self.string = string
        self.comment = comment; self.selection = selection; self.selectedText = selectedText; self.currentLine = currentLine
    }
    init(_ background: String, _ text: String, _ keyword: String, _ string: String, _ comment: String,
         _ selection: String, _ selectedText: String, _ currentLine: String) {
        func color(_ hex: String) -> NSColor {
            let value = UInt32(hex, radix: 16)!
            return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
        }
        self.init(background: color(background), text: color(text), keyword: color(keyword), string: color(string),
                  comment: color(comment), selection: color(selection), selectedText: color(selectedText), currentLine: color(currentLine))
    }
}

struct PreferenceValues: Codable, Equatable {
    var appearance: AppearancePreference = .sasStudio
    var theme: EditorTheme = .sasStudio
    var editorFontName = ""
    var editorFontSize: Double = 13
    var outputFontName = ""
    var outputFontSize: Double = 12
    var lineSpacing: Double = 1
    var editorWrap = false
    var outputWrap = false
    var lineNumbers = true
    var syntaxHighlighting = true
    var invisibleCharacters = false
    var currentLineHighlight = false
    var tableZoom: Double = 1
    var helpFontSize: Double = 14
    var indentWidth = EditorTextEditing.defaultIndentWidth
    var automaticIndentation = true
    var bracketPairing = true
    var navigatorWidth: Double = 215
    var resultsFraction: Double = 0.30
    var navigatorVisible = true

    mutating func validate() {
        func bounded(_ value: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
            value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
        }
        editorFontSize = bounded(editorFontSize, 8...40, 13)
        outputFontSize = bounded(outputFontSize, 8...40, 12)
        helpFontSize = bounded(helpFontSize, 10...28, 14)
        lineSpacing = bounded(lineSpacing, 1...2, 1)
        tableZoom = bounded(tableZoom, 0.5...2, 1)
        navigatorWidth = bounded(navigatorWidth, 150...2000, 215)
        resultsFraction = bounded(resultsFraction, 0...1, 0.30)
        if ![2, 4, 8].contains(indentWidth) { indentWidth = EditorTextEditing.defaultIndentWidth }
    }

    func font(name: String, size: Double) -> NSFont {
        if !name.isEmpty, let font = NSFont(name: name, size: CGFloat(size)), font.isFixedPitch { return font }
        return .monospacedSystemFont(ofSize: CGFloat(size), weight: .regular)
    }
    var editorFont: NSFont { font(name: editorFontName, size: editorFontSize) }
    var outputFont: NSFont { font(name: outputFontName, size: outputFontSize) }
}

@MainActor final class IDEPreferences {
    private(set) var defaults: UserDefaults
    private(set) var values = PreferenceValues()
    var onChange: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        reload()
    }
    func useDefaults(_ defaults: UserDefaults) { self.defaults = defaults; reload() }
    func reload() {
        values = defaults.data(forKey: "idePreferences").flatMap { try? JSONDecoder().decode(PreferenceValues.self, from: $0) } ?? PreferenceValues()
        if let saved = defaults.string(forKey: "appearancePreference"), let appearance = AppearancePreference(rawValue: saved) { values.appearance = appearance }
        if defaults.object(forKey: "navigatorWidth") != nil { values.navigatorWidth = defaults.double(forKey: "navigatorWidth") }
        if defaults.object(forKey: "resultsFraction") != nil { values.resultsFraction = defaults.double(forKey: "resultsFraction") }
        if defaults.object(forKey: "navigatorVisible") != nil { values.navigatorVisible = defaults.bool(forKey: "navigatorVisible") }
        values.validate()
        if !defaults.bool(forKey: "fourSpaceIndentationDefaultApplied") {
            if values.indentWidth == 2 {
                values.indentWidth = EditorTextEditing.defaultIndentWidth
                if let data = try? JSONEncoder().encode(values) { defaults.set(data, forKey: "idePreferences") }
            }
            defaults.set(true, forKey: "fourSpaceIndentationDefaultApplied")
        }
    }
    func update(persist: Bool = true, notify: Bool = true, _ change: (inout PreferenceValues) -> Void) {
        change(&values)
        values.validate()
        if persist {
            if let data = try? JSONEncoder().encode(values) { defaults.set(data, forKey: "idePreferences") }
            defaults.set(values.appearance.rawValue, forKey: "appearancePreference")
            defaults.set(values.navigatorWidth, forKey: "navigatorWidth")
            defaults.set(values.resultsFraction, forKey: "resultsFraction")
            defaults.set(values.navigatorVisible, forKey: "navigatorVisible")
        }
        if notify { onChange?() }
    }
    func reset(_ section: String) {
        let initial = PreferenceValues()
        update { value in
            switch section {
            case "Appearance": value.appearance = initial.appearance; value.theme = initial.theme; value.helpFontSize = initial.helpFontSize
            case "Editor":
                value.editorFontName = initial.editorFontName; value.editorFontSize = initial.editorFontSize
                value.lineSpacing = initial.lineSpacing; value.editorWrap = initial.editorWrap
                value.lineNumbers = initial.lineNumbers; value.syntaxHighlighting = initial.syntaxHighlighting
                value.invisibleCharacters = initial.invisibleCharacters; value.currentLineHighlight = initial.currentLineHighlight
            case "Output and Tables":
                value.outputFontName = initial.outputFontName; value.outputFontSize = initial.outputFontSize
                value.outputWrap = initial.outputWrap; value.tableZoom = initial.tableZoom
            case "Editing": value.indentWidth = initial.indentWidth; value.automaticIndentation = true; value.bracketPairing = true
            case "Layout": value.navigatorWidth = initial.navigatorWidth; value.resultsFraction = initial.resultsFraction; value.navigatorVisible = true
            default: break
            }
        }
    }
}

func configureWrapping(_ textView: NSTextView, in scroll: NSScrollView, enabled: Bool) {
    textView.isHorizontallyResizable = !enabled
    textView.autoresizingMask = enabled ? [.width] : []
    textView.textContainer?.widthTracksTextView = enabled
    textView.textContainer?.containerSize = NSSize(width: enabled ? max(1, scroll.contentSize.width) : .greatestFiniteMagnitude,
                                                  height: .greatestFiniteMagnitude)
    textView.setFrameSize(NSSize(width: max(1, scroll.contentSize.width), height: textView.frame.height))
    scroll.hasHorizontalScroller = !enabled
}
