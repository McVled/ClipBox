//
//  ClipboardRowView.swift
//  ClipBox
//

import SwiftUI

struct ClipboardRowView: View {

    let item:       ClipboardItem
    let index:      Int
    let isSelected: Bool
    let isPinned:   Bool
    let onSelect:   () -> Void

    /// History tab: called with (description, isHidden) after user confirms in popover.
    /// Pinned tab: nil — pin button becomes unpin.
    var onPin: ((String?, Bool) -> Void)? = nil

    /// Pinned tab: called when the user taps the unpin button.
    /// History tab: called from the "Already pinned" popover when the user
    /// decides to unpin the existing copy.
    var onUnpin: (() -> Void)? = nil

    /// Non-nil when a history row mirrors an item already present in the
    /// pinned list. The pin icon tints accent and the popover shows the
    /// "Already pinned — Unpin" layout instead of the Public/Private picker.
    var existingPin: ClipboardItem? = nil

    var onDelete: (() -> Void)? = nil

    @State private var isRevealed:      Bool   = false
    @State private var showingPinPopup: Bool   = false

    private var showsHiddenLayout: Bool { isPinned && item.isHidden }

    var body: some View {
        HStack(spacing: 0) {

            // ── Main content (tappable → paste) ───────────────────────────
            Button(action: onSelect) {
                HStack(spacing: 10) {
                    Text("\(index + 1)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
                        .frame(width: 18)

                    if showsHiddenLayout { hiddenContent } else { normalContent }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // ── Eye — press-and-hold to reveal (hidden items only) ────────
            if showsHiddenLayout {
                Image(systemName: isRevealed ? "eye.fill" : "eye")
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary.opacity(0.7))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in isRevealed = true  }
                            .onEnded   { _ in isRevealed = false }
                    )
            }

            // ── Pin / Unpin ───────────────────────────────────────────────
            // History, not yet pinned: pin.fill (dim) → Public/Private popover.
            // History, already pinned: pin.fill (accent) → "Already pinned — Unpin".
            // Pinned:  pin.slash.fill → unpins directly.
            if let onPin {
                let alreadyPinned = existingPin != nil
                let pinColor: Color = alreadyPinned
                    ? (isSelected ? .white : .accentColor)
                    : (isSelected ? .white.opacity(0.6) : .secondary.opacity(0.6))

                Button { showingPinPopup = true } label: {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundColor(pinColor)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    PopoverAnchor(isPresented: $showingPinPopup, preferredEdge: .minY) {
                        PinOptionsPopover(
                            existingPin: existingPin,
                            onPin: { description, isHidden in
                                showingPinPopup = false
                                onPin(description, isHidden)
                            },
                            onUnpin: {
                                showingPinPopup = false
                                onUnpin?()
                            },
                            onCancel: { showingPinPopup = false }
                        )
                    }
                )

            } else if let onUnpin {
                Button(action: onUnpin) {
                    Image(systemName: "pin.slash.fill")
                        .font(.system(size: 10))
                        .foregroundColor(isSelected ? .white.opacity(0.6) : .secondary.opacity(0.6))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            // ── Delete (history only) ─────────────────────────────────────
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
        .padding(.vertical, item.image != nil && !showsHiddenLayout ? 8 : 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
    }

    // MARK: - Content variants

    @ViewBuilder
    private var normalContent: some View {
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

    private var hiddenContent: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11))
                .foregroundColor(isSelected ? .white.opacity(0.85) : .secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.description?.isEmpty == false ? item.description! : "Private")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)

                Text(isRevealed ? (item.text ?? "") : "••••••••••")
                    .font(.system(
                        size: 11,
                        design: isRevealed ? .default : .monospaced
                    ))
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .animation(.easeInOut(duration: 0.1), value: isRevealed)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - PinOptionsPopover

private struct PinOptionsPopover: View {

    enum PinType { case `public`, `private` }

    /// When set, the popover renders in "already pinned" mode and offers Unpin
    /// instead of the Public/Private picker.
    var existingPin: ClipboardItem? = nil

    @State private var selected:    PinType = .public
    @State private var description: String  = ""

    @FocusState private var descriptionFocused: Bool

    let onPin:    (String?, Bool) -> Void
    let onUnpin:  () -> Void
    let onCancel: () -> Void

    private var canConfirm: Bool {
        selected == .public ||
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Group {
            if let existing = existingPin {
                alreadyPinnedBody(existing: existing)
            } else {
                pickerBody
            }
        }
        .padding(12)
        .frame(width: 240)
    }

    // MARK: - Already-pinned mode

    private func alreadyPinnedBody(existing: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: existing.isHidden ? "eye.slash.fill" : "pin.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.accentColor)
                Text("Already pinned")
                    .font(.system(size: 12, weight: .semibold))
            }

            if existing.isHidden, let d = existing.description, !d.isEmpty {
                Text("As private: \(d)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            } else if existing.isHidden {
                Text("Pinned as private.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                Text("This item is already in your pinned list.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
                Button("Unpin", action: onUnpin)
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - Public / Private picker mode

    private var pickerBody: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Public / Private toggle
            HStack(spacing: 4) {
                typeButton(.public,  label: "Public",  icon: "pin.fill")
                typeButton(.private, label: "Private", icon: "eye.slash.fill")
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.06))
            )

            // Description field — only shown for Private
            if selected == .private {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Description (e.g. Gmail password)", text: $description)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .focused($descriptionFocused)
                        .onSubmit { if canConfirm { confirm() } }

                    Text("Content is masked in the list but pasted as usual.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Cancel / Pin
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)

                Button("Pin", action: confirm)
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canConfirm)
            }
        }
        .onChange(of: selected) { newValue in
            guard newValue == .private else { return }
            // Delay long enough for the TextField to be inserted into the
            // view hierarchy before we try to focus it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                descriptionFocused = true
            }
        }
    }

    private func confirm() {
        switch selected {
        case .public:
            onPin(nil, false)
        case .private:
            let desc = description.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !desc.isEmpty else { return }
            onPin(desc, true)
        }
    }

    @ViewBuilder
    private func typeButton(_ type: PinType, label: String, icon: String) -> some View {
        let active = selected == type
        Button { selected = type } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11))
                Text(label).font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(active ? .white : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(active ? Color.accentColor : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
