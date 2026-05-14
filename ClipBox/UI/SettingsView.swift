//
//  SettingsView.swift
//  ClipBox
//

import SwiftUI

struct SettingsView: View {

    @Binding var shortcut:       Shortcut
    @Binding var followCursor:   Bool
    @Binding var isRecording:    Bool
    @Binding var historyLimit:   Int
    @Binding var showInMenuBar:  Bool

    let onBack:           () -> Void
    let onReset:          () -> Void
    let onExport:         () -> Void
    let onImport:         () -> Void
    let exportInProgress: Bool
    let importInProgress: Bool

    @State private var resetHovered: Bool = false

    private let limitOptions = [10, 15, 20, 25, 50]

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ────────────────────────────────────────────────────
            ZStack {
                Text("Settings")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.75))

                HStack {
                    Button(action: onBack) {
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Back")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(.secondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    HStack(spacing: 12) {
                        Button(action: onExport) {
                            // ProgressView swaps in for the icon while a backup
                            // is being encoded/written so the user sees the
                            // operation is in flight.
                            if exportInProgress {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.7)
                                    .frame(width: 16, height: 16)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                                    .frame(width: 16, height: 16)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(exportInProgress || importInProgress)
                        .help(exportInProgress ? "Exporting…" : "Export backup")

                        Button(action: onImport) {
                            if importInProgress {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.7)
                                    .frame(width: 16, height: 16)
                            } else {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                                    .frame(width: 16, height: 16)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(exportInProgress || importInProgress)
                        .help(importInProgress ? "Importing…" : "Import backup")
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Divider()

            // ── Content ───────────────────────────────────────────────────
            VStack(spacing: 0) {

                sectionLabel("Behavior")

                settingRow(
                    icon:     "menubar.rectangle",
                    label:    "Show in Menu Bar",
                    subtitle: "Adds a clipboard icon to the menu bar. Click it to open the popup next to the icon."
                ) {
                    Toggle("", isOn: $showInMenuBar)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .onChange(of: showInMenuBar) { newValue in
                            StatusBarController.shared.setVisible(newValue)
                        }
                }

                rowDivider()

                settingRow(
                    icon:     "cursorarrow.motionlines",
                    label:    "Follow Cursor",
                    subtitle: "Popup opens near your cursor. When off, it reopens at its last position."
                ) {
                    Toggle("", isOn: $followCursor)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .onChange(of: followCursor) { newValue in
                            PopupWindow.shared.followCursor = newValue
                        }
                }

                rowDivider()

                settingRow(
                    icon:     "clock.arrow.circlepath",
                    label:    "History Size",
                    subtitle: "Maximum items kept in history. Oldest are removed when the limit is reached."
                ) {
                    Picker("", selection: $historyLimit) {
                        ForEach(limitOptions, id: \.self) { n in
                            Text("\(n)").tag(n)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 58)
                    .onChange(of: historyLimit) { newValue in
                        UserDefaults.standard.set(newValue, forKey: ClipboardManager.historyLimitKey)
                        ClipboardManager.shared.applyHistoryLimit()
                    }
                }

                sectionLabel("Global Shortcut")

                shortcutBlock

                Spacer().frame(height: 14)
                Divider()

                // Pill-styled to match Delete All / Recover All. Orange tint
                // signals "warning, this will undo your settings" without the
                // hard-destructive feel of red.
                Button(action: onReset) {
                    Text("Reset to Defaults")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.orange.opacity(resetHovered ? 0.9 : 0.75))
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 20)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.12)) { resetHovered = hovering }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: - Shortcut block

    private var shortcutBlock: some View {
        VStack(alignment: .leading, spacing: 8) {

            // Key badges (or "Press keys…" while recording)
            ZStack {
                if isRecording {
                    Text("Press keys…")
                        .font(.system(size: 12))
                        .foregroundColor(.accentColor)
                } else {
                    HStack(spacing: 6) {
                        ForEach(shortcut.displayComponents, id: \.self) { key in
                            Text(key)
                                .font(.system(size: 15, weight: .medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.primary.opacity(0.07))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
                                )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isRecording ? Color.accentColor : Color.primary.opacity(0.08),
                        lineWidth: isRecording ? 1 : 0.5
                    )
            )
            .animation(.easeInOut(duration: 0.15), value: isRecording)

            // Subtitle + Record button on the same row
            HStack(alignment: .top) {
                Text("Must include at least one modifier (⌘ ⇧ ⌥ ⌃). Plain ⌘C/V/X/Z/A/H/M/Q/W are reserved. Press Escape to cancel.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: {
                    isRecording.toggle()
                    HotkeyManager.shared.isRecording = isRecording
                }) {
                    Text(isRecording ? "Cancel" : "Record")
                        .font(.system(size: 11))
                        .frame(width: 54)
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    // MARK: - Helpers

    /// A setting row with icon, label, subtitle beneath the label, and a control on the right.
    @ViewBuilder
    private func settingRow<Control: View>(
        icon: String,
        label: String,
        subtitle: String? = nil,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 18, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()
            control()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(.secondary.opacity(0.55))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 3)
    }

    private func rowDivider() -> some View {
        Divider()
            .padding(.leading, 40)
    }
}
