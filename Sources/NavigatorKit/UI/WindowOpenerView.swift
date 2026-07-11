import SwiftUI

/// Bridges ``AppNavigator``'s window-open requests to the `openWindow`
/// environment action (which only exists inside views). Installed invisibly
/// by `RoutedSceneRoot`; only the active scene processes requests.
///
/// On platforms without multi-window support the parked intent is executed
/// in this scene instead.
struct WindowOpenerView: View {
    let app: AppNavigator
    let navigator: Navigator

    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows

    var body: some View {
        Color.clear
            .onChange(of: app.pendingWindowRequests.map(\.id), initial: true) {
                processRequests()
            }
    }

    private func processRequests() {
        // Only one scene should open windows: the active one (or the first
        // registered, before any activation event).
        let isResponsible =
            app.activeSceneID == navigator.scene.id
            || (app.activeSceneID == nil && app.navigators.first === navigator)
        guard isResponsible else { return }

        for request in app.pendingWindowRequests {
            if supportsMultipleWindows {
                openWindow(id: request.windowID ?? app.defaultWindowID)
                app.consumeWindowRequest(request, openedWindow: true, fallback: nil)
            } else {
                app.consumeWindowRequest(request, openedWindow: false, fallback: navigator)
            }
        }
    }
}
