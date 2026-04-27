//
//  ClipboardItem.swift
//  ClipBox
//

import Foundation
import AppKit

enum ClipboardContent {
    case text(String)
    case image(NSImage)
}

struct ClipboardItem: Identifiable {

    let id: UUID

    let content: ClipboardContent

    let date: Date

    let description: String?

    let isHidden: Bool

    /// The tag this pinned item belongs to, or nil if untagged.
    let tagID: UUID?

    // MARK: - Convenience inits

    init(text: String, description: String? = nil, isHidden: Bool = false, tagID: UUID? = nil) {
        self.id          = UUID()
        self.content     = .text(text)
        self.date        = Date()
        self.description = description
        self.isHidden    = isHidden
        self.tagID       = tagID
    }

    init(image: NSImage, description: String? = nil, isHidden: Bool = false, tagID: UUID? = nil) {
        self.id          = UUID()
        self.content     = .image(image)
        self.date        = Date()
        self.description = description
        self.isHidden    = isHidden
        self.tagID       = tagID
    }

    init(content: ClipboardContent, date: Date, description: String? = nil, isHidden: Bool = false, tagID: UUID? = nil) {
        self.id          = UUID()
        self.content     = content
        self.date        = date
        self.description = description
        self.isHidden    = isHidden
        self.tagID       = tagID
    }

    /// Internal init that preserves a given id — used only by `withTagID(_:)`.
    private init(preservingID id: UUID, content: ClipboardContent, date: Date,
                 description: String?, isHidden: Bool, tagID: UUID?) {
        self.id          = id
        self.content     = content
        self.date        = date
        self.description = description
        self.isHidden    = isHidden
        self.tagID       = tagID
    }

    /// Returns a copy of this item with the given tagID, keeping the same identity.
    func withTagID(_ tagID: UUID?) -> ClipboardItem {
        ClipboardItem(
            preservingID: id,
            content:      content,
            date:         date,
            description:  description,
            isHidden:     isHidden,
            tagID:        tagID
        )
    }

    // MARK: - Helpers

    var text: String? {
        if case .text(let t) = content { return t }
        return nil
    }

    var image: NSImage? {
        if case .image(let img) = content { return img }
        return nil
    }

    var deduplicationKey: String {
        switch content {
        case .text(let t):
            return "text:\(t)"
        case .image(let img):
            let size = img.size
            return "image:\(size.width)x\(size.height)"
        }
    }
}
