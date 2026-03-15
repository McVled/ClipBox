//
//  ClipboardRowView.swift
//  ClipBox
//

import SwiftUI

/// A single row in the clipboard history list.
///
/// Renders differently based on content type:
/// - **Text** — index badge + text preview + timestamp
/// - **Image** — index badge + thumbnail preview + dimensions + timestamp
///
/// When `isSelected` is true the row gets an accent-colour background.
struct ClipboardRowView: View {

    let item: ClipboardItem
    let index: Int
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {

                // ── Index badge ───────────────────────────────────────────
                Text("\(index + 1)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
                    .frame(width: 18)

                // ── Content preview ───────────────────────────────────────
                switch item.content {

                case .text(let text):
                    // Text preview — single line, truncated with "…" if too long.
                    Text(text)
                        .font(.system(size: 13))
                        .foregroundColor(isSelected ? .white : .primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                case .image(let image):
                    // Thumbnail — fixed height, proportional width, clipped to
                    // rounded corners so it fits neatly in the row.
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                        )

                    // Show pixel dimensions next to the thumbnail.
                    // `Int()` drops the decimal so "1024.0 × 768.0" → "1024 × 768".
                    Text("\(Int(image.size.width)) × \(Int(image.size.height))")
                        .font(.system(size: 11))
                        .foregroundColor(isSelected ? .white.opacity(0.85) : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // ── Timestamp ─────────────────────────────────────────────
                Text(item.date, style: .time)
                    .font(.system(size: 10))
                    .foregroundColor(isSelected ? .white.opacity(0.6) : .secondary)
            }
            .padding(.horizontal, 12)
            // Image rows are taller (36px thumbnail + 8px padding each side = 52pt).
            // Text rows keep the original compact height.
            .padding(.vertical, item.image != nil ? 8 : 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
