//
//  ClipBoxApp.swift
//  ClipBox
//

import SwiftUI

/// The entry point of the application.
///
/// `@main` tells Swift this is where execution starts.
/// `@NSApplicationDelegateAdaptor` bridges SwiftUI's App lifecycle to the
/// traditional AppKit `NSApplicationDelegate`, which is where we do our setup
/// (see `AppDelegate.swift`).
///
/// We use a `Settings` scene instead of a `WindowGroup` to suppress the
/// default empty window that SwiftUI would otherwise create on launch.
/// ClipBox is a background agent — it has no persistent main window.
@main
struct ClipBoxApp: App {

    /// Connects our `AppDelegate` to the SwiftUI lifecycle.
    /// SwiftUI will instantiate `AppDelegate` and call its methods at the
    /// appropriate points (launch, terminate, etc.).
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // `Settings` is the lightest-weight Scene type — it doesn't create
        // a visible window on launch. We give it an `EmptyView` because we
        // have no settings UI yet.
        Settings {
            EmptyView()
        }
    }
}
