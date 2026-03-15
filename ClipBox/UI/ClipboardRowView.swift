//
//  ClipboardRowView.swift
//  ClipBox
//

import SwiftUI

/// A single row in the clipboard history list.
///
/// Displays:
/// - A small index number on the left (1, 2, 3…)
/// - The copied text in the middle, truncated to one line if too long
/// - The time it was copied on the right
///
/// When `isSelected` is true (the user has navigated to this row with the
/// arrow keys), the row gets an accent-colour background to show it's active.
///
/// Tapping the row calls `onSelect`, which triggers a paste in `PopupWindow`.
struct ClipboardRowView: View {

    // MARK: - Properties

    /// The clipboard item this row represents.
    let item: ClipboardItem

    /// This row's position in the list (0-based). Displayed as 1-based to
    /// the user (so index 0 shows "1", index 1 shows "2", etc.).
    let index: Int

    /// Whether this row is currently highlighted by keyboard navigation.
    let isSelected: Bool

    /// Called when the user clicks the row. The parent view handles the paste.
    let onSelect: () -> Void

    // MARK: - Body

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {

                // ── Index badge ───────────────────────────────────────────
                // Shows the position in history (1 = most recent).
                // Monospaced font keeps alignment consistent for 1-digit and
                // 2-digit numbers.
                Text("\(index + 1)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
                    .frame(width: 18) // Fixed width so the text column always starts at the same X

                // ── Copied text preview ───────────────────────────────────
                // `.lineLimit(1)` keeps each row the same height regardless
                // of how long the copied text is. `.truncationMode(.tail)`
                // adds "…" at the end if the text is too wide.
                Text(item.text)
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // ── Timestamp ─────────────────────────────────────────────
                // `.relative` style would show "2 minutes ago", but `.time`
                // shows the actual clock time (e.g. "14:32"), which is more
                // precise and less noisy.
                Text(item.date, style: .time)
                    .font(.system(size: 10))
                    .foregroundColor(isSelected ? .white.opacity(0.6) : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    // Accent colour when selected, transparent otherwise.
                    // `.accentColor` automatically picks the user's system accent colour.
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            // `.contentShape` makes the entire row (including empty padding areas)
            // clickable, not just the text itself.
            .contentShape(Rectangle())
        }
        // `.plain` removes the default button chrome (background flash, border, etc.)
        .buttonStyle(.plain)
    }
}
