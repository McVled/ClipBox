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

    /// Cached dedup key — generating it for images regenerates the TIFF
    /// representation and hashes 64 KB, which is far too expensive to do on
    /// every comparison.  We compute it once at construction.
    let deduplicationKey: String

    // MARK: - Convenience inits

    init(text: String, description: String? = nil, isHidden: Bool = false, tagID: UUID? = nil) {
        self.id          = UUID()
        self.content     = .text(text)
        self.date        = Date()
        self.description = description
        self.isHidden    = isHidden
        self.tagID       = tagID
        self.deduplicationKey = Self.computeKey(for: self.content)
    }

    init(image: NSImage, description: String? = nil, isHidden: Bool = false, tagID: UUID? = nil) {
        self.id          = UUID()
        self.content     = .image(image)
        self.date        = Date()
        self.description = description
        self.isHidden    = isHidden
        self.tagID       = tagID
        self.deduplicationKey = Self.computeKey(for: self.content)
    }

    init(content: ClipboardContent, date: Date, description: String? = nil, isHidden: Bool = false, tagID: UUID? = nil) {
        self.id          = UUID()
        self.content     = content
        self.date        = date
        self.description = description
        self.isHidden    = isHidden
        self.tagID       = tagID
        self.deduplicationKey = Self.computeKey(for: self.content)
    }

    /// Internal init that preserves a given id AND the cached dedup key.
    /// Used by `withTagID(_:)` so we don't recompute the key (content hasn't
    /// changed, only metadata has).
    private init(preservingID id: UUID, content: ClipboardContent, date: Date,
                 description: String?, isHidden: Bool, tagID: UUID?,
                 deduplicationKey: String) {
        self.id               = id
        self.content          = content
        self.date             = date
        self.description      = description
        self.isHidden         = isHidden
        self.tagID            = tagID
        self.deduplicationKey = deduplicationKey
    }

    /// Returns a copy of this item with the given tagID, keeping the same identity
    /// and reusing the cached dedup key (content is unchanged).
    func withTagID(_ tagID: UUID?) -> ClipboardItem {
        ClipboardItem(
            preservingID:     id,
            content:          content,
            date:             date,
            description:      description,
            isHidden:         isHidden,
            tagID:            tagID,
            deduplicationKey: deduplicationKey
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

    private static func computeKey(for content: ClipboardContent) -> String {
        switch content {
        case .text(let t):
            return "text:\(t)"
        case .image(let img):
            guard let tiff = img.tiffRepresentation else {
                return "image:fallback:\(img.size.width)x\(img.size.height)"
            }
            // FNV-1a-style hash of first 64 KB + total byte count.
            // Sampling the header region alone risks TIFF metadata differences,
            // but 64 KB of pixel data is both fast and practically collision-free.
            var h: UInt64 = UInt64(tiff.count) &* 1099511628211
            tiff.prefix(65536).withUnsafeBytes { buffer in
                for byte in buffer { h = (h ^ UInt64(byte)) &* 1099511628211 }
            }
            return "image:\(tiff.count):\(h)"
        }
    }
}
