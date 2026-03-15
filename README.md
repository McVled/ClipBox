# ClipBox

A lightweight macOS clipboard history manager that runs entirely in the background. Press **⌘⇧V** from any app to summon a floating popup near your cursor, browse your last 15 copied texts and images, and paste any of them back with a single keystroke.

---

## Features

- **Text & image history** — Automatically captures everything you copy — plain text and images — up to 15 items.
- **Global shortcut** — Press **⌘⇧V** from any app to open the popup instantly.
- **Keyboard navigation** — **↑ / ↓** to move through the list, **Enter** to paste, **Esc** to dismiss.
- **Click to paste** — Click any row directly without using the keyboard.
- **Instant paste** — Restores focus to your previous app and pastes the selected item exactly where your cursor was.
- **Persistent history** — Clipboard history survives app restarts. Text is stored in UserDefaults; images are saved as PNG files in Application Support.
- **Draggable popup** — Click and drag the popup to reposition it anywhere on screen.
- **Smart positioning** — Opens next to your cursor and auto-adjusts to stay within screen bounds.
- **Adaptive appearance** — Follows system Light/Dark mode automatically.
- **Clear & Quit from popup** — No menu bar icon, no Dock entry. Everything is inside the popup itself.

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

ClipBox will prompt for Accessibility access. This is required for the global ⌘⇧V hotkey and the simulated ⌘V paste. Click **Open System Settings** and toggle ClipBox on under Privacy & Security → Accessibility.

---

## Usage

| Action | How |
|--------|-----|
| Open popup | **⌘⇧V** from any app |
| Navigate history | **↑ / ↓** arrow keys |
| Paste selected item | **Enter** or click the row |
| Dismiss without pasting | **Esc** or click outside |
| Move the popup | Click and drag |
| Clear all history | **🗑 Clear** button in the popup header |
| Quit ClipBox | **✕ Quit** button in the popup header |

**Auto-start on login (optional)**

System Settings → General → Login Items → **+** → select `ClipBox.app`.

---

## How It Works

**Clipboard monitoring** — A `Timer` fires every 0.5 seconds and checks `NSPasteboard.changeCount`. When the count changes, ClipBox reads the new content (image first, text fallback) and prepends it to history. Duplicates bubble to the top instead of creating a second entry.

**Image handling** — Images are resized to a maximum of 1024px on the longest edge before being stored, keeping memory usage low. They are saved as PNG files in `~/Library/Application Support/ClipBox/images/` and loaded back on next launch.

**Global hotkey** — `HotkeyManager` installs a `CGEventTap` at the session level — a low-level hook that sees keypresses before any app does. When ⌘⇧V is detected the event is consumed (not forwarded) and the popup is toggled.

**Popup panel** — `PopupWindow` uses a custom `NSPanel` subclass (`KeyablePanel`) with `.nonactivatingPanel` so it never steals focus from the previous app, and `canBecomeKey = true` so it receives keyboard input directly — including Escape, which Apple blocks in global event monitors.

**Paste sequence** — Close popup → wait 80ms → re-activate previous app → wait 120ms → write to `NSPasteboard` → send `CGEvent` ⌘V. The delays give macOS time to complete the app switch before the paste event is delivered.

---

## Troubleshooting

**Popup doesn't open on ⌘⇧V**
→ Grant Accessibility permission: System Settings → Privacy & Security → Accessibility → enable ClipBox.

**Paste lands in the wrong app**
→ Another app may be intercepting ⌘⇧V. Check for conflicts with other clipboard managers or productivity tools.

**History is empty on first launch**
→ Normal — ClipBox only records copies made after it starts. Copy something and try again.

**Images not appearing in history**
→ Some apps copy images in formats ClipBox doesn't recognise (e.g. proprietary types). Standard PNG, TIFF, and JPEG copies are supported.

---

## Project Structure

```
ClipBox/
├── App/
│   ├── ClipBoxApp.swift        # @main entry point
│   └── AppDelegate.swift       # Wires all components on launch
├── Clipboard/
│   ├── ClipboardItem.swift     # Data model: text or image + timestamp
│   └── ClipboardManager.swift  # Monitoring, history, persistence, paste
├── Hotkey/
│   └── HotkeyManager.swift     # CGEventTap global ⌘⇧V hotkey
├── UI/
│   ├── PopupWindow.swift       # NSPanel lifecycle and positioning
│   ├── PopupView.swift         # SwiftUI list with keyboard navigation
│   └── ClipboardRowView.swift  # Row: text preview or image thumbnail
├── Utils/
│   └── CursorPosition.swift    # Mouse position helper
└── Resources/
    └── Info.plist              # LSUIElement = YES (no Dock icon)
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