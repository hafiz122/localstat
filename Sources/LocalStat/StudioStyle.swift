import AppKit

enum StudioStyle {
    static let blue = NSColor(srgbRed: 0.16, green: 0.36, blue: 0.57, alpha: 1)
    static let ink = NSColor(srgbRed: 0.13, green: 0.20, blue: 0.29, alpha: 1)
    static let muted = NSColor(srgbRed: 0.32, green: 0.38, blue: 0.45, alpha: 1)
    static let chrome = NSColor(srgbRed: 0.96, green: 0.97, blue: 0.98, alpha: 1)
    static let line = NSColor(srgbRed: 0.82, green: 0.85, blue: 0.89, alpha: 1)
    static let selection = NSColor(srgbRed: 0.86, green: 0.92, blue: 0.97, alpha: 1)

    static func background(_ color: NSColor?, on view: NSView) {
        view.wantsLayer = color != nil
        view.layer?.backgroundColor = color?.cgColor
    }
}

final class StudioOutlineRowView: NSTableRowView {
    var usesStudioStyle = false

    override func drawSelection(in dirtyRect: NSRect) {
        guard usesStudioStyle else { super.drawSelection(in: dirtyRect); return }
        StudioStyle.selection.setFill()
        bounds.intersection(dirtyRect).fill()
    }
}
