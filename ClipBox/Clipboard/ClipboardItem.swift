//
//  ClipboardItem.swift
//  ClipBox
//

import Foundation

/// A single entry in the clipboard history.
///
/// Every time the user copies something new, a `ClipboardItem` is created
/// and stored in `ClipboardManager.history`. It holds the copied text and
/// the exact time it was copied, so we can display a timestamp in the UI.
///
/// `Identifiable` lets SwiftUI's `ForEach` uniquely track each row without
/// needing an explicit `id:` parameter.
///
/// `Equatable` lets us compare two items by their text content, which is
/// used to avoid adding duplicates to the history list.
struct ClipboardItem: Identifiable, Equatable {

    /// A unique ID generated automatically when the item is created.
    /// UUID guarantees no two items ever share the same ID, even if
    /// they contain identical text.
    let id = UUID()

    /// The actual text that was copied to the clipboard.
    let text: String

    /// The moment this item was copied. Used to render the time label
    /// in `ClipboardRowView`.
    let date: Date

    /// Creates a new clipboard item with the given text.
    /// The date is automatically set to right now.
    init(text: String) {
        self.text = text
        self.date = Date()
    }

    /// Two items are considered equal if they contain the same text.
    /// We intentionally ignore `id` and `date` here — this is only used
    /// to detect duplicates before inserting into the history array.
    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.text == rhs.text
    }
}
