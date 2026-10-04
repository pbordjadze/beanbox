import SwiftUI

/// The app's four tabs: measure the paper, measure the beans, see the pairing, and split
/// look-alike beans.
struct AppShellView: View {
    @Environment(Project.self) private var project
    @State private var tab = Launch.tab

    var body: some View {
        TabView(selection: $tab) {
            Tab("Papers", systemImage: "square.stack", value: AppTab.papers) {
                SamplerView(kind: .paper)
            }
            Tab("Beans", systemImage: "capsule", value: AppTab.beans) {
                SamplerView(kind: .bean)
            }
            Tab("Match", systemImage: "link", value: AppTab.match) {
                MatchView()
            }
            Tab("Sort", systemImage: "circle.grid.3x3", value: AppTab.sort) {
                SortView()
            }
        }
        .alert(
            "Something went wrong", isPresented: Binding(get: { project.problem != nil }, set: { if !$0 { project.problem = nil } }),
            presenting: project.problem
        ) { _ in
            Button("OK") { project.problem = nil }
        } message: { problem in
            Text(problem)
        }
    }
}
