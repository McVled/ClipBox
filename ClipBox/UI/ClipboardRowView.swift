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
    let isPinned: Bool
    let onSelect: () -> Void
    let onTogglePin: () -> Void
    var onDelete: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            // ── Main row (tappable for paste) ────────────────────────────
            Button(action: onSelect) {
                HStack(spacing: 10) {
                    // ── Index badge ───────────────────────────────────────
                    Text("\(index + 1)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
                        .frame(width: 18)

                    // ── Content preview ───────────────────────────────────
                    switch item.content {
                    case .text(let text):
                        Text(text)
                            .font(.system(size: 13))
                            .foregroundColor(isSelected ? .white : .primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)

                    case .image(let image):
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 44, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                            )

                        Text("\(Int(image.size.width)) × \(Int(image.size.height))")
                            .font(.system(size: 11))
                            .foregroundColor(isSelected ? .white.opacity(0.85) : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // ── Pin/Unpin button ─────────────────────────────────────────
            Button(action: onTogglePin) {
                Image(systemName: isPinned ? "pin.slash.fill" : "pin.fill")
                    .font(.system(size: 10))
                    .foregroundColor(isSelected ? .white.opacity(0.6) : .secondary.opacity(0.6))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // ── Delete button (only shown when onDelete is provided) ─────
            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(isSelected ? .white.opacity(0.6) : .secondary.opacity(0.6))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, item.image != nil ? 8 : 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
    }
}
