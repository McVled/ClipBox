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

            // Capture mouse position NOW — the user just clicked this button so
            // the cursor is reliably on it.  We use this instead of computing the
            // anchor from anchorView.frame because SwiftUI's LazyVStack places
            // NSViewRepresentable views at their absolute document-space offset,
            // not their scroll-adjusted visible position.  Any frame-based
            // coordinate conversion therefore produces a wrong Y when the list
            // has been scrolled.
            let mouseLocation = NSEvent.mouseLocation

            // Defer long enough for any in-flight SwiftUI layout pass to settle
            // before we ask AppKit for the window reference.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                context.coordinator.show(near: mouseLocation, edge: preferredEdge)
            }
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

        /// Invisible NSView whose sole job is to give us a reference to the
        /// hosting window.  Positioning is done via the captured mouse location,
        /// not via this view's frame.
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

        deinit {
            popover.delegate = nil
        }

        func show(near screenLocation: NSPoint, edge: NSRectEdge) {
            guard let window = anchorView.window,
                  let contentView = window.contentView else { return }

            // Convert the captured screen point to the window's contentView space,
            // then build a button-sized rect centred on it as the popover anchor.
            let windowPoint  = window.convertPoint(fromScreen: screenLocation)
            let point        = contentView.convert(windowPoint, from: nil)
            let w: CGFloat   = anchorView.bounds.width  > 1 ? anchorView.bounds.width  : 24
            let h: CGFloat   = anchorView.bounds.height > 1 ? anchorView.bounds.height : 24
            let anchorRect   = NSRect(x: point.x - w / 2, y: point.y - h / 2, width: w, height: h)

            let vc = NSHostingController(rootView: latestContent())
            popover.contentViewController = vc
            popover.show(relativeTo: anchorRect, of: contentView, preferredEdge: edge)
        }

        // Sync isPresented back when the user clicks outside (transient close).
        func popoverDidClose(_ notification: Notification) {
            DispatchQueue.main.async { [weak self] in
                self?.isPresented = false
            }
        }
    }
}
