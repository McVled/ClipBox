//
//  HotkeyManager.swift
//  ClipBox
//

import Cocoa
import Carbon

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
    /// It will be called on the main thread whenever ⌘⇧V is pressed.
    var onTrigger: (() -> Void)?

    // MARK: - Private Properties

    /// The actual event tap object registered with the system.
    private var eventTap: CFMachPort?

    /// A run-loop source wrapping the event tap so it integrates with
    /// the main run loop (which drives all macOS event processing).
    private var runLoopSource: CFRunLoopSource?

    // MARK: - Init

    private init() {}

    // MARK: - Lifecycle

    /// Installs the global event tap and starts listening for ⌘⇧V.
    /// Safe to call multiple times — subsequent calls are no-ops if already running.
    func start() {
        // Ask for Accessibility permission. `kAXTrustedCheckOptionPrompt: true`
        // means macOS will show the system prompt if permission hasn't been granted yet.
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted {
            print("ClipBox: Waiting for Accessibility permission. Please allow in System Settings.")
        }

        // We only care about keyDown events, so build a bitmask for just that type.
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)

        // The callback is a C-style function (required by CGEventTap).
        // `refcon` is an untyped pointer we use to pass `self` into the callback,
        // since C functions can't capture Swift variables like closures can.
        let callback: CGEventTapCallBack = { _, type, event, refcon in

            // Only handle actual keyDown events (the tap also gets called for
            // tap-disabled notifications, which we ignore).
            guard type == .keyDown else {
                return Unmanaged.passRetained(event)
            }

            let flags   = event.flags
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

            // Check for ⌘⇧V: Command + Shift + V (keyCode 9)
            let isCommand = flags.contains(.maskCommand)
            let isShift   = flags.contains(.maskShift)
            let isV       = keyCode == 9

            if isCommand && isShift && isV {
                // Recover our HotkeyManager instance from the raw pointer.
                if let ref = refcon {
                    let manager = Unmanaged<HotkeyManager>.fromOpaque(ref).takeUnretainedValue()
                    DispatchQueue.main.async {
                        manager.onTrigger?()
                    }
                }
                // Returning nil *consumes* the event — it won't reach any other app.
                return nil
            }

            // For any other key, pass the event through unchanged.
            return Unmanaged.passRetained(event)
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
    }
}
