import SwiftUI
import AppKit

/// Installs a local key-down monitor while its view is on screen.
/// The handler receives the key code and modifier flags; return true to
/// consume the event, false to pass it on.
struct GlobalKeyMonitor: ViewModifier {
    let handler: (Int, NSEvent.ModifierFlags) -> Bool
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    if handler(Int(event.keyCode), event.modifierFlags) {
                        return nil
                    }
                    return event
                }
            }
            .onDisappear {
                if let monitor {
                    NSEvent.removeMonitor(monitor)
                }
                monitor = nil
            }
    }
}
