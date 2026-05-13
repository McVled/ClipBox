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

    // MARK: - Recently Deleted metadata (nil on live items)

    /// When the item was moved to Recently Deleted.
    let deletedAt: Date?

    /// Tag name snapshot at deletion time — used to recreate the tag on recovery
    /// if the original tag was deleted in the meantime.
    let deletedTagName: String?

    /// Tag color snapshot at deletion time (companion to deletedTagName).
    let deletedTagColor: String?

    /// True when item came from pinnedItems; false when from history.
    /// Controls where recovery sends the item.
    let deletedFromPinned: Bool

    // MARK: - Convenience inits (live items — deletion fields are always nil/false)

    init(text: String, description: String? = nil, isHidden: Bool = false, tagID: UUID? = nil) {
        self.id               = UUID()
        self.content          = .text(text)
        self.date             = Date()
        self.description      = description
        self.isHidden         = isHidden
        self.tagID            = tagID
        self.deduplicationKey = Self.computeKey(for: .text(text))
        self.deletedAt        = nil
        self.deletedTagName   = nil
        self.deletedTagColor  = nil
        self.deletedFromPinned = false
    }

    init(image: NSImage, description: String? = nil, isHidden: Bool = false, tagID: UUID? = nil) {
        self.id               = UUID()
        self.content          = .image(image)
        self.date             = Date()
        self.description      = description
        self.isHidden         = isHidden
        self.tagID            = tagID
        self.deduplicationKey = Self.computeKey(for: .image(image))
        self.deletedAt        = nil
        self.deletedTagName   = nil
        self.deletedTagColor  = nil
        self.deletedFromPinned = false
    }

    init(content: ClipboardContent, date: Date, description: String? = nil, isHidden: Bool = false, tagID: UUID? = nil) {
        self.id               = UUID()
        self.content          = content
        self.date             = date
        self.description      = description
        self.isHidden         = isHidden
        self.tagID            = tagID
        self.deduplicationKey = Self.computeKey(for: content)
        self.deletedAt        = nil
        self.deletedTagName   = nil
        self.deletedTagColor  = nil
        self.deletedFromPinned = false
    }

    /// Used by the persistence layer to restore items with their original UUID.
    /// All deletion-related fields default to nil/false for normal items.
    init(loadedWithID id: UUID, content: ClipboardContent, date: Date,
         description: String? = nil, isHidden: Bool = false, tagID: UUID? = nil,
         deletedAt: Date? = nil, deletedTagName: String? = nil,
         deletedTagColor: String? = nil, deletedFromPinned: Bool = false) {
        self.id               = id
        self.content          = content
        self.date             = date
        self.description      = description
        self.isHidden         = isHidden
        self.tagID            = tagID
        self.deduplicationKey = Self.computeKey(for: content)
        self.deletedAt        = deletedAt
        self.deletedTagName   = deletedTagName
        self.deletedTagColor  = deletedTagColor
        self.deletedFromPinned = deletedFromPinned
    }

    // MARK: - Private full-fidelity init (preserves all fields including dedup key)

    private init(preservingID id: UUID, content: ClipboardContent, date: Date,
                 description: String?, isHidden: Bool, tagID: UUID?,
                 deduplicationKey: String,
                 deletedAt: Date? = nil, deletedTagName: String? = nil,
                 deletedTagColor: String? = nil, deletedFromPinned: Bool = false) {
        self.id               = id
        self.content          = content
        self.date             = date
        self.description      = description
        self.isHidden         = isHidden
        self.tagID            = tagID
        self.deduplicationKey = deduplicationKey
        self.deletedAt        = deletedAt
        self.deletedTagName   = deletedTagName
        self.deletedTagColor  = deletedTagColor
        self.deletedFromPinned = deletedFromPinned
    }

    // MARK: - Mutation helpers (return new copies, preserve identity and dedup key)

    /// Returns a copy with a different tagID; all other fields unchanged.
    func withTagID(_ tagID: UUID?) -> ClipboardItem {
        ClipboardItem(
            preservingID:      id,
            content:           content,
            date:              date,
            description:       description,
            isHidden:          isHidden,
            tagID:             tagID,
            deduplicationKey:  deduplicationKey,
            deletedAt:         deletedAt,
            deletedTagName:    deletedTagName,
            deletedTagColor:   deletedTagColor,
            deletedFromPinned: deletedFromPinned
        )
    }

    /// Returns a copy with updated privacy; all other fields unchanged.
    func withPrivacy(isHidden: Bool, description: String?) -> ClipboardItem {
        ClipboardItem(
            preservingID:      id,
            content:           content,
            date:              date,
            description:       description,
            isHidden:          isHidden,
            tagID:             tagID,
            deduplicationKey:  deduplicationKey,
            deletedAt:         deletedAt,
            deletedTagName:    deletedTagName,
            deletedTagColor:   deletedTagColor,
            deletedFromPinned: deletedFromPinned
        )
    }

    /// Returns a soft-deleted copy with deletion metadata attached.
    /// Call with the tag's current name/color so recovery can recreate it
    /// even if the tag is deleted before the item is recovered.
    func withDeletion(tagName: String?, tagColor: String?, fromPinned: Bool = false) -> ClipboardItem {
        ClipboardItem(
            preservingID:      id,
            content:           content,
            date:              date,
            description:       description,
            isHidden:          isHidden,
            tagID:             tagID,
            deduplicationKey:  deduplicationKey,
            deletedAt:         Date(),
            deletedTagName:    tagName,
            deletedTagColor:   tagColor,
            deletedFromPinned: fromPinned
        )
    }

    /// Returns a live copy stripped of all deletion metadata.
    func withRecovery() -> ClipboardItem {
        ClipboardItem(
            preservingID:      id,
            content:           content,
            date:              date,
            description:       description,
            isHidden:          isHidden,
            tagID:             tagID,
            deduplicationKey:  deduplicationKey,
            deletedAt:         nil,
            deletedTagName:    nil,
            deletedTagColor:   nil,
            deletedFromPinned: false
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
            var h: UInt64 = UInt64(tiff.count) &* 1099511628211
            tiff.prefix(65536).withUnsafeBytes { buffer in
                for byte in buffer { h = (h ^ UInt64(byte)) &* 1099511628211 }
            }
            return "image:\(tiff.count):\(h)"
        }
    }
}
