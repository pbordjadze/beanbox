import SwiftUI

/// Shows the app shell. Debug builds launched with `-demo <name>` first fill the project with
/// that scenario's synthetic photos and measurements (see `DemoMode`).
struct RootView: View {
    @Environment(Project.self) private var project

    var body: some View {
        AppShellView()
        #if DEBUG
            .task { await DemoData.install(into: project) }
        #endif
    }
}
