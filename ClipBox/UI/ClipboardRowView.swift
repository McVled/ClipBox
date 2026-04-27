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

    /// History tab: called with (description, isHidden, tagID) after user confirms in popover.
    var onPin: ((String?, Bool, UUID?) -> Void)? = nil

    var onUnpin: (() -> Void)? = nil

    var existingPin: ClipboardItem? = nil

    var onDelete: (() -> Void)? = nil

    var tags: [ClipBoxTag] = []

    /// Called to assign (or remove with nil) a tag on this pinned row.
    var onAssignTag: ((UUID?) -> Void)? = nil

    /// Called to assign a brand-new tag to this pinned row. Creates the tag
    /// and returns the new tag's id so callers can update their state.
    var onCreateAndAssignTag: ((String, String) -> Void)? = nil

    /// Called from the PinOptionsPopover to create a new tag while pinning
    /// from History. Returns the new tag's id so the popover can select it.
    var onCreateTag: ((String, String) -> UUID)? = nil

    @State private var isRevealed:      Bool = false
    @State private var showingPinPopup: Bool = false
    @State private var showingTagPopup: Bool = false

    private var showsHiddenLayout: Bool { isPinned && item.isHidden }

    private var currentTag: ClipBoxTag? {
        guard let tagID = item.tagID else { return nil }
        return tags.first(where: { $0.id == tagID })
    }

    var body: some View {
        HStack(spacing: 0) {

            // ── Main content ──────────────────────────────────────────────
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

            // ── Timestamp ─────────────────────────────────────────────────
            Text(item.date.clipBoxDisplay)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(isSelected ? .white.opacity(0.65) : .secondary.opacity(0.7))
                .padding(.horizontal, 4)
                .fixedSize()

            // ── Eye (hidden items only) ───────────────────────────────────
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

            // ── Tag flag (pinned rows only) ───────────────────────────────
            if let onAssignTag {
                let flagColor: Color = currentTag.map { $0.color }
                    ?? (isSelected ? .white.opacity(0.45) : .secondary.opacity(0.45))

                Button { showingTagPopup = true } label: {
                    Image(systemName: currentTag != nil ? "flag.fill" : "flag")
                        .font(.system(size: 12))
                        .foregroundColor(flagColor)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    PopoverAnchor(isPresented: $showingTagPopup, preferredEdge: .minY) {
                        TagAssignPopover(
                            tags:         tags,
                            currentTagID: item.tagID,
                            onSelect: { tagID in
                                showingTagPopup = false
                                onAssignTag(tagID)
                            },
                            onCreate: { name, colorHex in
                                showingTagPopup = false
                                onCreateAndAssignTag?(name, colorHex)
                            },
                            onCancel: { showingTagPopup = false }
                        )
                    }
                )
            }

            // ── Pin / Unpin ───────────────────────────────────────────────
            if let onPin {
                let alreadyPinned = existingPin != nil
                let pinColor: Color = alreadyPinned
                    ? (isSelected ? .white : .accentColor)
                    : (isSelected ? .white.opacity(0.75) : .secondary.opacity(0.75))

                Button { showingPinPopup = true } label: {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 12))
                        .foregroundColor(pinColor)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    PopoverAnchor(isPresented: $showingPinPopup, preferredEdge: .minY) {
                        PinOptionsPopover(
                            existingPin:   existingPin,
                            tags:          tags,
                            onCreateTag:   onCreateTag,
                            onPin: { description, isHidden, tagID in
                                showingPinPopup = false
                                onPin(description, isHidden, tagID)
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
                        .font(.system(size: 12))
                        .foregroundColor(isSelected ? .white.opacity(0.75) : .secondary.opacity(0.75))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            // ── Delete (history only) ─────────────────────────────────────
            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary.opacity(0.55))
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
                Text(item.description?.isEmpty == false ? item.description! : (item.image != nil ? "Private Image" : "Private"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)

                if let image = item.image {
                    if isRevealed {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 44, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                            )
                            .animation(.easeInOut(duration: 0.1), value: isRevealed)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "photo")
                                .font(.system(size: 10))
                            Text("\(Int(image.size.width)) × \(Int(image.size.height))")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                        .animation(.easeInOut(duration: 0.1), value: isRevealed)
                    }
                } else {
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - TagAssignPopover

private struct TagAssignPopover: View {

    let tags:         [ClipBoxTag]
    let currentTagID: UUID?
    let onSelect:     (UUID?) -> Void
    let onCreate:     (String, String) -> Void
    let onCancel:     () -> Void

    @State private var showingNewTag  = false
    @State private var newTagName     = ""
    @State private var newTagColorHex = ClipBoxTag.palette[0]

    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {

            Text("Assign Tag")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.bottom, 2)

            tagRow(icon: "flag.slash", color: .secondary, label: "None",
                   isChecked: currentTagID == nil, action: { onSelect(nil) })

            if !tags.isEmpty {
                Divider()
                ForEach(tags) { tag in
                    tagRow(icon: "flag.fill", color: tag.color, label: tag.name,
                           isChecked: currentTagID == tag.id, action: { onSelect(tag.id) })
                }
            }

            Divider()

            if showingNewTag {
                newTagForm
            } else {
                Button {
                    showingNewTag = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { nameFieldFocused = true }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus.circle").font(.system(size: 11))
                        Text("New tag…").font(.system(size: 12))
                    }
                    .foregroundColor(.accentColor)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(width: 200)
    }

    private func tagRow(icon: String, color: Color, label: String,
                        isChecked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11)).foregroundColor(color).frame(width: 14)
                Text(label).font(.system(size: 12)).foregroundColor(.primary)
                Spacer()
                if isChecked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var newTagForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button(action: { showingNewTag = false; newTagName = "" }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                TextField("Tag name", text: $newTagName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .focused($nameFieldFocused)
                    .onSubmit { confirmCreate() }
            }

            HStack(spacing: 5) {
                ForEach(ClipBoxTag.palette, id: \.self) { hex in
                    let selected = newTagColorHex == hex
                    Circle()
                        .fill(Color(hex: hex) ?? .accentColor)
                        .frame(width: 17, height: 17)
                        .overlay(Circle().strokeBorder(Color.white, lineWidth: selected ? 2 : 0))
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5))
                        .onTapGesture { newTagColorHex = hex }
                }
            }

            HStack {
                Spacer()
                Button("Create & Assign") { confirmCreate() }
                    .controlSize(.small)
                    .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func confirmCreate() {
        let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        onCreate(name, newTagColorHex)
    }
}

// MARK: - PinOptionsPopover

private struct PinOptionsPopover: View {

    enum PinType { case `public`, `private` }

    var existingPin: ClipboardItem? = nil
    var tags: [ClipBoxTag] = []

    /// Creates a new tag and returns its id so the popover can immediately select it.
    var onCreateTag: ((String, String) -> UUID)? = nil

    @State private var selected:         PinType = .public
    @State private var description:      String  = ""
    @State private var selectedTagID:    UUID?   = nil
    @State private var showingNewTagPin: Bool    = false
    @State private var newTagName:       String  = ""
    @State private var newTagColorHex:   String  = ClipBoxTag.palette[0]

    @FocusState private var descriptionFocused:  Bool
    @FocusState private var newTagNameFocused:   Bool

    let onPin:    (String?, Bool, UUID?) -> Void
    let onUnpin:  () -> Void
    let onCancel: () -> Void

    private var canConfirm: Bool {
        let typeOK = selected == .public
            || !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if showingNewTagPin {
            return typeOK && !newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return typeOK
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

    // MARK: Already-pinned mode

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
                    .font(.system(size: 11)).foregroundColor(.secondary).lineLimit(2)
            } else if existing.isHidden {
                Text("Pinned as private.")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            } else {
                Text("This item is already in your pinned list.")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel).controlSize(.small).keyboardShortcut(.cancelAction)
                Button("Unpin",  action: onUnpin).controlSize(.small).keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: Public / Private picker mode

    private var pickerBody: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Public / Private toggle
            HStack(spacing: 4) {
                typeButton(.public,  label: "Public",  icon: "pin.fill")
                typeButton(.private, label: "Private", icon: "eye.slash.fill")
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))

            // Description (private only)
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

            // Tag section — always visible so users can create their first tag
            Divider()
            tagSection

            // Cancel / Pin  (label changes to "Create & Pin" while new-tag form is open)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).controlSize(.small).keyboardShortcut(.cancelAction)
                Button(showingNewTagPin ? "Create & Pin" : "Pin", action: confirm)
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canConfirm)
            }
        }
        .onChange(of: selected) { newValue in
            guard newValue == .private else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { descriptionFocused = true }
        }
    }

    // Tag section: existing tags + inline new-tag form
    @ViewBuilder
    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tag (optional)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)

            // Existing tags as selectable chips
            if !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        // None chip
                        tagChip(id: nil, label: "None", icon: "flag.slash", color: .secondary)
                        // Existing tag chips
                        ForEach(tags) { tag in
                            tagChip(id: tag.id, label: tag.name, icon: "flag.fill", color: tag.color)
                        }
                    }
                }
            }

            // New tag form — "Pin" at the bottom doubles as "Create & Pin"
            if showingNewTagPin {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Button(action: { showingNewTagPin = false; newTagName = "" }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)

                        TextField("Tag name", text: $newTagName)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                            .focused($newTagNameFocused)
                    }

                    HStack(spacing: 5) {
                        ForEach(ClipBoxTag.palette, id: \.self) { hex in
                            let sel = newTagColorHex == hex
                            Circle()
                                .fill(Color(hex: hex) ?? .accentColor)
                                .frame(width: 16, height: 16)
                                .overlay(Circle().strokeBorder(Color.white, lineWidth: sel ? 2 : 0))
                                .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5))
                                .onTapGesture { newTagColorHex = hex }
                        }
                    }
                }
                .padding(.top, 2)
            } else {
                Button {
                    showingNewTagPin = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { newTagNameFocused = true }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle").font(.system(size: 10))
                        Text("New tag…").font(.system(size: 11))
                    }
                    .foregroundColor(.accentColor)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func tagChip(id: UUID?, label: String, icon: String, color: Color) -> some View {
        let isSelected = selectedTagID == id
        return Button { selectedTagID = id } label: {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10)).foregroundColor(isSelected ? .white : color)
                Text(label).font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .white : .primary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? color : Color.primary.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? color : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.12), value: isSelected)
    }

    private func confirm() {
        // If the new-tag form is open, create the tag first and use it.
        var tagID = selectedTagID
        if showingNewTagPin {
            let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty, let creator = onCreateTag {
                tagID = creator(name, newTagColorHex)
            }
        }

        switch selected {
        case .public:
            onPin(nil, false, tagID)
        case .private:
            let desc = description.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !desc.isEmpty else { return }
            onPin(desc, true, tagID)
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

// MARK: - Date display

private extension Date {
    var clipBoxDisplay: String {
        let seconds = Date().timeIntervalSince(self)
        if seconds < 60 {
            return "now"
        } else if seconds < 3600 {
            return "\(Int(seconds / 60))m ago"
        } else if Calendar.current.isDateInToday(self) {
            let f = DateFormatter(); f.dateStyle = .none; f.timeStyle = .short
            return f.string(from: self)
        } else if Calendar.current.isDateInYesterday(self) {
            let f = DateFormatter(); f.dateStyle = .none; f.timeStyle = .short
            return "Yest " + f.string(from: self)
        } else {
            let f = DateFormatter(); f.dateFormat = "d MMM"
            return f.string(from: self)
        }
    }
}
