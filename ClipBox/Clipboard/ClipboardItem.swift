//
//  ClipboardItem.swift
//  ClipBox
//

import Foundation
import AppKit

/// Represents what was copied — either plain text or an image.
///
/// Using an enum means the compiler forces us to handle both cases
/// everywhere we use a `ClipboardItem`, so we can never accidentally
/// treat an image as text or vice versa.
enum ClipboardContent {
    case text(String)
    case image(NSImage)
}

/// A single entry in the clipboard history.
///
/// Holds the copied content (text or image), the time it was copied,
/// and a unique ID so SwiftUI can track each row independently.
struct ClipboardItem: Identifiable {

    /// Auto-generated unique ID. Guarantees no two items share the same ID.
    let id = UUID()

    /// What was copied — either `.text(String)` or `.image(NSImage)`.
    let content: ClipboardContent

    /// When this item was copied. Shown as a timestamp in the UI.
    let date: Date

    /// Optional user-supplied label shown in place of the real content when
    /// the item is pinned as sensitive (e.g. "Yahoo password"). Only used for
    /// pinned items; always `nil` for fresh clipboard captures.
    let description: String?

    /// When `true`, the row renders bullets (••••••••) + a lock icon + the
    /// description instead of the real content. The actual clipboard value is
    /// preserved and pasted as-is — hiding is purely visual.
    let isHidden: Bool

    // MARK: - Convenience inits

    /// Creates a text item with the current date.
    init(text: String, description: String? = nil, isHidden: Bool = false) {
        self.content = .text(text)
        self.date = Date()
        self.description = description
        self.isHidden = isHidden
    }

    /// Creates an image item with the current date.
    init(image: NSImage, description: String? = nil, isHidden: Bool = false) {
        self.content = .image(image)
        self.date = Date()
        self.description = description
        self.isHidden = isHidden
    }

    /// Creates an item with an explicit date — used when restoring from disk.
    init(content: ClipboardContent, date: Date, description: String? = nil, isHidden: Bool = false) {
        self.content = content
        self.date = date
        self.description = description
        self.isHidden = isHidden
    }

    // MARK: - Helpers

    /// Returns the text string if this is a text item, otherwise nil.
    var text: String? {
        if case .text(let t) = content { return t }
        return nil
    }

    /// Returns the image if this is an image item, otherwise nil.
    var image: NSImage? {
        if case .image(let img) = content { return img }
        return nil
    }

    /// A short string used for duplicate detection.
    /// For text: the actual string. For images: a pixel-size fingerprint.
    var deduplicationKey: String {
        switch content {
        case .text(let t):
            return "text:\(t)"
        case .image(let img):
            // Two images are considered duplicates if they have the exact same
            // pixel dimensions. Not perfect but fast and avoids obvious re-adds.
            let size = img.size
            return "image:\(size.width)x\(size.height)"
        }
    }
}
