    private func textHeight(_ text: String, width: CGFloat, font: NSFont) -> CGFloat {
        let key = TextKey(text: text, width: width, fontName: font.fontName, fontSize: font.pointSize)
        if let height = textHeights[key] { return height }
        let height = measureText(text, width, font)
        textHeights[key] = height
        return height
    }
