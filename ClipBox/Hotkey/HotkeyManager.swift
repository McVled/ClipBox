//
//  HotkeyManager.swift
//  ClipBox
//

import Cocoa

/// Listens globally for the ⌘⇧V keyboard shortcut and fires a callback
/// whenever it is pressed, regardless of which app is currently in focus.
///
/// ## How it works
/// macOS provides `CGEvent.tapCreate` — a low-level hook that sits in the
/// HID (Human Interface Device) event stream and sees *every* keypress system-wide,
/// before it reaches any app. We install a tap that watches for keyDown events,
/// checks whether the key is V with ⌘⇧ held, and if so calls `onTrigger` instead
/// of forwarding the event (returning `nil` consumes it).
///
/// ## Why not `NSEvent.addGlobalMonitorForEvents`?
/// The simpler `NSEvent` API cannot *consume* events — the keypress would still
/// reach the frontmost app (potentially triggering its own paste). `CGEventTap`
/// can suppress the event by returning `nil`.
///
/// ## Accessibility permission
/// `CGEventTap` requires the user to grant Accessibility access to ClipBox in
/// System Settings → Privacy & Security → Accessibility. The app will prompt
/// automatically on first launch.
class HotkeyManager {

    // MARK: - Singleton

    static let shared = HotkeyManager()

    // MARK: - Public Interface

    /// Set this closure before calling `start()`.
    /// It will be called on the main thread whenever the configured shortcut fires.
    var onTrigger: (() -> Void)?

    /// When true, the global tap does NOT fire `onTrigger` and does NOT consume
    /// events. Used while the user is recording a new shortcut in Settings,
    /// so the chosen combination reaches the popup's key handler for capture
    /// instead of being swallowed or re-triggering the popup.
    var isRecording: Bool = false

    /// UserDefaults key for the persisted shortcut.
    private static let shortcutKey = "com.clipbox.shortcut"

    /// In-memory cache of the current shortcut.  The CGEventTap callback reads
    /// `currentShortcut` on EVERY keypress system-wide, so doing a
    /// `JSONDecoder().decode` from UserDefaults each time would burn cycles
    /// in the global keyboard hot path.  We load once on first access and
    /// keep it in sync via the setter.  Both getter and setter run on the
    /// main thread (UI updates + main run-loop event tap), so no locking.
    private var _shortcutCache: Shortcut?

    /// The shortcut currently listened for. Backed by `_shortcutCache` for fast
    /// reads from the event-tap callback; UserDefaults is the persistence layer.
    var currentShortcut: Shortcut {
        get {
            if let cached = _shortcutCache { return cached }
            let loaded: Shortcut
            // A shortcut saved by an older build may be ⇧-only (e.g. ⇧A), which
            // would swallow normal typing — fall back to the default instead.
            if let data = UserDefaults.standard.data(forKey: Self.shortcutKey),
               let s = try? JSONDecoder().decode(Shortcut.self, from: data),
               s.hasModifier {
                loaded = s
            } else {
                loaded = .default
            }
            _shortcutCache = loaded
            return loaded
        }
        set {
            _shortcutCache = newValue
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: Self.shortcutKey)
            }
        }
    }

    // MARK: - Private Properties

    /// The actual event tap object registered with the system.
    /// `fileprivate` so the C callback can re-enable it after a system
    /// `tapDisabledByTimeout` event without going through a getter.
    fileprivate var eventTap: CFMachPort?

    /// A run-loop source wrapping the event tap so it integrates with
    /// the main run loop (which drives all macOS event processing).
    private var runLoopSource: CFRunLoopSource?

    /// Polls `AXIsProcessTrusted()` once a second while we're waiting for the
    /// user to grant Accessibility permission, so we can install the tap as
    /// soon as it's available — no app restart required.
    private var permissionTimer: Timer?

    // MARK: - Init

    private init() {}

    // MARK: - Lifecycle

    /// Installs the global event tap and starts listening for the configured
    /// shortcut.  Safe to call multiple times — subsequent calls are no-ops
    /// if a tap is already running.  If Accessibility permission is missing
    /// we prompt the user, return without creating a tap, and poll until the
    /// permission flips on, then retry automatically.
    func start() {
        guard eventTap == nil else { return }

        // Ask for Accessibility permission. `kAXTrustedCheckOptionPrompt: true`
        // means macOS will show the system prompt if permission hasn't been granted yet.
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted {
            print("ClipBox: Waiting for Accessibility permission. Please allow in System Settings.")
            // The system prompt above is a one-shot — if the user dismisses it
            // the hotkey would silently never fire. Show our own alert with a
            // direct link to the pane so they don't have to hunt for it.
            DispatchQueue.main.async { [weak self] in
                let alert = NSAlert()
                alert.messageText = "Accessibility Permission Required"
                alert.informativeText = "ClipBox needs Accessibility access to listen for its global shortcut. Enable ClipBox in System Settings → Privacy & Security → Accessibility — the shortcut will start working as soon as you do."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Open System Settings")
                alert.addButton(withTitle: "Later")
                if alert.runModal() == .alertFirstButtonReturn,
                   let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
                self?.startPermissionPolling()
            }
            // Don't try to create the tap yet — `tapCreate` will fail without
            // permission and we'd just fall through to the same error path.
            return
        }

        // We only care about keyDown events, so build a bitmask for just that type.
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)

        // The callback is a C-style function (required by CGEventTap).
        // `refcon` is an untyped pointer we use to pass `self` into the callback,
        // since C functions can't capture Swift variables like closures can.
        let callback: CGEventTapCallBack = { _, type, event, refcon in

            // Recover our HotkeyManager instance from the raw pointer so we can
            // read the current shortcut config and the recording flag.
            // Pass-through events are returned with `passUnretained`: the
            // system owns `event`, and an extra retain here would leak one
            // CGEvent for every keystroke typed anywhere on the Mac.
            guard let ref = refcon else {
                return Unmanaged.passUnretained(event)
            }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(ref).takeUnretainedValue()

            // The system disables the tap if our callback ever takes too long
            // (or after sleep/wake on some macOS versions). Without re-enabling,
            // the global shortcut silently stops working until app relaunch.
            // These event types arrive regardless of the events-of-interest mask.
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = manager.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }

            // Only handle actual keyDown events from here on.
            guard type == .keyDown else {
                return Unmanaged.passUnretained(event)
            }

            // While the user is recording a new shortcut in Settings, pass every
            // keypress through untouched — the popup's KeyablePanel will capture
            // the combination locally.
            if manager.isRecording {
                return Unmanaged.passUnretained(event)
            }

            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let sc      = manager.currentShortcut

            // Fast path: most keystrokes aren't our hotkey. Check keyCode first
            // so we bail out before touching flags. Modifiers must match exactly
            // — otherwise ⌘V would also fire a shortcut configured as ⌘⇧V
            // (wrong) because `contains` alone would still match.
            if keyCode == Int64(sc.keyCode) {
                let flags = event.flags
                if flags.contains(.maskCommand)   == sc.command,
                   flags.contains(.maskShift)     == sc.shift,
                   flags.contains(.maskAlternate) == sc.option,
                   flags.contains(.maskControl)   == sc.control {
                    DispatchQueue.main.async {
                        manager.onTrigger?()
                    }
                    // Returning nil *consumes* the event — it won't reach any other app.
                    return nil
                }
            }

            // For any other key, pass the event through unchanged.
            return Unmanaged.passUnretained(event)
        }

        // Convert `self` to an untyped pointer so we can pass it to the C callback.
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        // Create the event tap at the session level (sees all apps' events).
        // `.headInsertEventTap` places our tap at the front of the chain.
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: selfPtr
        )

        guard let tap = eventTap else {
            print("ClipBox: Failed to create event tap. Accessibility permission may be missing.")
            return
        }

        // Wrap the tap in a run-loop source and add it to the main run loop.
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    /// Removes the event tap and stops listening. Called when the app quits.
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil

        permissionTimer?.invalidate()
        permissionTimer = nil
    }

    // MARK: - Permission Polling

    /// Watches for Accessibility permission to flip on, then retries `start()`.
    /// Uses `AXIsProcessTrusted()` (no prompt) so we don't show the system
    /// dialog again on every tick.
    private func startPermissionPolling() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            self?.permissionTimer = nil
            self?.start()
        }
    }
}
