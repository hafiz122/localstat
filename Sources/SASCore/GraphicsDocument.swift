import Foundation

public enum GraphicsDocument {
    public static func html(for graphics: [ResultGraphic]) -> String {
        let content: String
        if graphics.isEmpty {
            content = "<p class=empty>Run a plotting procedure to see graphics here.</p>"
        } else {
            content = graphics.map { graphic in
                let name = escaped(graphic.name)
                let procedure = escaped(graphic.procedure)
                let image = graphic.svg.base64EncodedString()
                return "<figure><figcaption>\(name) <small>\(procedure)</small></figcaption><img alt=\"\(name)\" src=\"data:image/svg+xml;base64,\(image)\"></figure>"
            }.joined()
        }
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        :root { color-scheme: light dark; font: 13px -apple-system, BlinkMacSystemFont, sans-serif; }
        body { margin: 0; padding: 18px; color: CanvasText; background: Canvas; }
        figure { margin: 0 0 24px; max-width: 960px; }
        figcaption { font-weight: 600; margin-bottom: 8px; }
        small { color: GrayText; font-weight: normal; margin-left: 8px; }
        img { display: block; width: 100%; height: auto; background: white; }
        .empty { color: GrayText; }
        </style></head><body>\(content)</body></html>
        """
    }

    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
