import SwiftUI

@main
struct BeanBoxApp: App {
    @State private var project = Project.forLaunch()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(project)
                .tint(Theme.ink)
                // A swatch is judged against whatever surrounds it, and a dark or tinted
                // surround shifts how it looks: the app is light and neutral in every appearance.
                .preferredColorScheme(.light)
        }
    }
}
