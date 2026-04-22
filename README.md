# ClipBox

A lightweight macOS clipboard history manager that runs entirely in the background. Press **⌘⇧V** (or your custom shortcut) from any app to summon a floating popup near your cursor, browse your clipboard history with text and images, pin important items to keep them forever, and paste any of them back with a single keystroke.

---

## Features

- **Text & image history** — Automatically captures everything you copy — plain text and images.
- **Global shortcut** — Press **⌘⇧V** (configurable) from any app to open the popup instantly.
- **Keyboard navigation** — **↑ / ↓** to move through the list, **Enter** to paste, **Esc** to dismiss, **← / →** to switch tabs.
- **Click to paste** — Click any row directly without using the keyboard.
- **Instant paste** — Restores focus to your previous app and pastes the selected item exactly where your cursor was.
- **Persistent history** — Clipboard history survives app restarts. Text is stored in UserDefaults; images are saved as PNG files in Application Support.
- **Pinned items** — Pin any item from History to keep it permanently in the Pinned tab. Pinned items are not affected by the history size limit or Clear All.
- **Sensitive pin** — Pin an item as private: the row displays bullets (••••••••) and a lock icon with a custom label you choose, while still pasting the real content.
- **Delete individual items** — Remove a single entry from history without clearing everything.
- **Configurable shortcut** — Record any modifier+key combo as your global hotkey directly from Settings.
- **Configurable history size** — Choose how many items to keep: 10, 15, 20, 25, or 50.
- **Optional menu bar icon** — Toggle a clipboard icon in the menu bar. Clicking it opens the popup anchored directly below it.
- **Follow Cursor toggle** — When enabled, the popup opens near your cursor. When disabled, it reopens at its last position.
- **Draggable popup** — Click and drag the popup to reposition it anywhere on screen.
- **Smart positioning** — Opens next to your cursor and auto-adjusts to stay within screen bounds.
- **Adaptive appearance** — Follows system Light/Dark mode automatically.

---

## Requirements

| | |
|---|---|
| **macOS** | 12 Monterey or later |
| **Permissions** | Accessibility (required for global hotkey and simulated paste) |

---

## Installation

1. Download the latest `ClipBox.dmg` from the [Releases](../../releases) page.
2. Open the DMG and drag **ClipBox** into the **Applications** folder.
3. Eject the DMG and launch ClipBox from **Applications** or **Spotlight** (⌘Space → "ClipBox").

**First launch — Gatekeeper warning**

Because ClipBox is not notarized, macOS will block it on first open with *"ClipBox cannot be opened because the developer cannot be verified."*

Open **Terminal** (⌘Space → "Terminal") and run this once:

```bash
xattr -cr /Applications/ClipBox.app
```

Then open ClipBox normally. You won't need to do this again.

**First launch — Accessibility permission**

ClipBox will prompt for Accessibility access. This is required for the global shortcut hotkey and the simulated ⌘V paste. Click **Open System Settings** and toggle ClipBox on under Privacy & Security → Accessibility.

---

## Usage

| Action | How |
|--------|-----|
| Open popup | Global shortcut (default **⌘⇧V**) from any app |
| Open popup from menu bar | Click the clipboard icon in the menu bar |
| Switch tabs | **← / →** arrow keys or click **History / Pinned** |
| Navigate list | **↑ / ↓** arrow keys |
| Paste selected item | **Enter** or click the row |
| Dismiss without pasting | **Esc** or click outside |
| Move the popup | Click and drag |
| Pin an item | Hover a history row → click the pin icon → choose Public or Private |
| Unpin an item | In the Pinned tab, click the unpin icon; or hover the already-pinned row in History |
| Delete one item | Hover a history row → click the trash icon |
| Clear all items | **Clear All** button in the popup header (clears the active tab) |
| Open Settings | **Settings** button in the popup header |
| Quit ClipBox | **Quit App** button in the popup header |

### Settings

Open the popup → **Settings** to configure:

| Setting | Description |
|---------|-------------|
| **Show in Menu Bar** | Toggles the clipboard icon in the menu bar |
| **Follow Cursor** | When on, popup opens near the cursor; when off, reopens at its last position |
| **History Size** | Maximum items kept (10 / 15 / 20 / 25 / 50). Oldest are removed when the limit is reached |
| **Global Shortcut** | Click **Record**, press your desired modifier+key combo, then it's saved automatically |
| **Reset to Defaults** | Restores all settings to their factory values |

**Auto-start on login (optional)**

System Settings → General → Login Items → **+** → select `ClipBox.app`.

---

## How It Works

**Clipboard monitoring** — A `Timer` fires every 0.5 seconds and checks `NSPasteboard.changeCount`. When the count changes, ClipBox reads the new content (image first, text fallback) and prepends it to history. Duplicates bubble to the top instead of creating a second entry.

**Image handling** — Images are resized to a maximum of 1024px on the longest edge before being stored, keeping memory usage low. They are saved as PNG files in `~/Library/Application Support/ClipBox/images/` and loaded back on next launch.

**Pinned items** — Pinning copies the item into a separate persistent list stored in UserDefaults alongside the history index. Pinned items are never pruned by the history size limit. A sensitive pin stores a user-supplied description and an `isHidden` flag; the real content is preserved and pasted as-is — hiding is purely visual.

**Global hotkey** — `HotkeyManager` installs a `CGEventTap` at the session level — a low-level hook that sees keypresses before any app does. The active shortcut is saved in UserDefaults as JSON and restored on launch. When recording mode is active, the next valid modifier+key combo replaces the current shortcut immediately.

**Menu bar icon** — `StatusBarController` creates an `NSStatusItem` when enabled. Clicking the icon calls `PopupWindow.toggle(from:)` with the icon's screen frame as an anchor, so the popup appears directly below it.

**Popup panel** — `PopupWindow` uses a custom `NSPanel` subclass (`KeyablePanel`) with `.nonactivatingPanel` so it never steals focus from the previous app, and `canBecomeKey = true` so it receives keyboard input directly — including Escape, which Apple blocks in global event monitors.

**Paste sequence** — Close popup → wait 80ms → re-activate previous app → wait 120ms → write to `NSPasteboard` → send `CGEvent` ⌘V. The delays give macOS time to complete the app switch before the paste event is delivered.

---

## Troubleshooting

**Popup doesn't open on the global shortcut**
→ Grant Accessibility permission: System Settings → Privacy & Security → Accessibility → enable ClipBox.

**Paste lands in the wrong app**
→ Another app may be intercepting your shortcut. Check for conflicts with other clipboard managers or productivity tools. Try recording a different shortcut in Settings.

**History is empty on first launch**
→ Normal — ClipBox only records copies made after it starts. Copy something and try again.

**Images not appearing in history**
→ Some apps copy images in formats ClipBox doesn't recognise (e.g. proprietary types). Standard PNG, TIFF, and JPEG copies are supported.

---

## Project Structure

```
ClipBox/
├── App/
│   ├── ClipBoxApp.swift            # @main entry point
│   ├── AppDelegate.swift           # Wires all components on launch
│   └── StatusBarController.swift   # Optional menu-bar icon; click to toggle popup
├── Clipboard/
│   ├── ClipboardItem.swift         # Data model: text or image, pin metadata, isHidden
│   └── ClipboardManager.swift      # Monitoring, history, pinned items, persistence, paste
├── Hotkey/
│   └── HotkeyManager.swift         # CGEventTap global hotkey; shortcut recording
├── Settings/
│   └── Shortcut.swift              # Codable model for the user-configured key combo
├── UI/
│   ├── PopupWindow.swift           # NSPanel lifecycle and positioning
│   ├── PopupView.swift             # SwiftUI: History/Pinned tabs, keyboard navigation
│   ├── ClipboardRowView.swift      # Row: text preview or image thumbnail; pin/delete actions
│   ├── SettingsView.swift          # Settings slide-over: shortcut, history size, toggles
│   └── PopoverAnchor.swift         # NSViewRepresentable helper for NSPopover anchoring
├── Utils/
│   └── CursorPosition.swift        # Mouse position helper
└── Resources/
    └── Info.plist                  # LSUIElement = YES (no Dock icon)
```

---

## Building from Source

```bash
git clone https://github.com/your-username/ClipBox.git
cd ClipBox
open ClipBox.xcodeproj
```

Select the **ClipBox** target → **Info** tab → confirm `Application is agent (UIElement)` is set to `YES`. Press **⌘R** to build and run.

---

## License

MIT License. See `LICENSE` for details.
