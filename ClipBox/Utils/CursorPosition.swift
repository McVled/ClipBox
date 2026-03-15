//
//  CursorPosition.swift
//  ClipBox
//

import Cocoa

/// A small utility that returns the current mouse cursor position.
///
/// macOS uses a coordinate system where (0, 0) is the **bottom-left** corner
/// of the primary display (unlike most UI frameworks where it's top-left).
/// `NSEvent.mouseLocation` already gives us this value — this wrapper just
/// gives it a cleaner call site.
struct CursorPosition {

    /// Returns the current mouse cursor position in screen coordinates.
    /// The origin (0, 0) is the bottom-left of the primary display.
    static func current() -> CGPoint {
        return NSEvent.mouseLocation
    }
}
