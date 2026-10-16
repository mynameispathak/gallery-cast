import SwiftUI

/// Root scene: sidebar + detail, with the viewer floating over everything
/// (including the sidebar) while open.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        ZStack {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView()
                    .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
            } detail: {
                if model.currentFolder != nil {
                    PhotoGridView()
                } else {
                    WelcomeView()
                }
            }

            if model.isViewerPresented {
                ViewerView()
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .animation(.easeInOut(duration: Token.Duration.base), value: model.isViewerPresented)
        .tint(Token.Accent.primary)
    }
}
