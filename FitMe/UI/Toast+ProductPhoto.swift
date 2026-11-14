import FitEngine

extension Toast {
    /// Confirms a product photo was applied, says if Claude couldn't re-tag it, and offers Undo.
    static func productPhoto(from page: ProductPage, isRetagged: Bool, undo: @escaping @MainActor () -> Void) -> Toast {
        Toast(
            symbol: isRetagged ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
            message: isRetagged
                ? "Now using the photo from \(page.sourceName)"
                : "New photo in, but Claude couldn't update the tags",
            undo: undo
        )
    }
}

extension Item {
    /// The owner's edits on top of a re-matched item that Claude couldn't re-tag: their tags stay, the colors
    /// follow the new photo, and an empty name takes the shop's.
    func keepingEdits(over matched: Item) -> Item {
        var item = self
        item.colors = matched.colors
        if item.name.trimmingCharacters(in: .whitespaces).isEmpty {
            item.name = matched.name
        }
        return item
    }
}
