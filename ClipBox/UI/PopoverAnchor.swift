//
//  PopoverAnchor.swift
//  ClipBox
//

import SwiftUI
import AppKit

/// Presents a SwiftUI view inside an NSPopover with animations disabled.
/// Attach it as `.background()` on the button you want to anchor to —
/// the popover appears relative to that button's frame, opening instantly.
///
/// Usage:
///   Button { showPopover = true } label: { ... }
///     .background(PopoverAnchor(isPresented: $showPopover) { MyContent() })
struct PopoverAnchor<Content: View>: NSViewRepresentable {

    @Binding var isPresented: Bool
    var preferredEdge: NSRectEdge = .minY

    @ViewBuilder var content: () -> Content

    // MARK: - NSViewRepresentable

    func makeNSView(context: Context) -> NSView {
        context.coordinator.anchorView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.latestContent = content
        if isPresented {
            guard !context.coordinator.popover.isShown else { return }
            // Defer to next run-loop tick so the anchor view's frame is finalised.
            DispatchQueue.main.async { context.coordinator.show(edge: preferredEdge) }
        } else if context.coordinator.popover.isShown {
            context.coordinator.popover.close()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented, content: content)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSPopoverDelegate {

        @Binding var isPresented: Bool
        var latestContent: () -> Content

        /// The invisible NSView used as the popover's anchor point.
        /// It is sized and positioned to match the SwiftUI button via `.background()`.
        let anchorView = NSView()
        let popover    = NSPopover()

        init(isPresented: Binding<Bool>, content: @escaping () -> Content) {
            _isPresented  = isPresented
            latestContent = content
            super.init()
            popover.animates = false
            popover.behavior = .transient
            popover.delegate = self
        }

        func show(edge: NSRectEdge) {
            let vc = NSHostingController(rootView: latestContent())
            popover.contentViewController = vc
            popover.show(
                relativeTo: anchorView.bounds,
                of: anchorView,
                preferredEdge: edge
            )
        }

        // Sync isPresented back when the user clicks outside (transient close).
        func popoverDidClose(_ notification: Notification) {
            DispatchQueue.main.async { [weak self] in
                self?.isPresented = false
            }
        }
    }
}
