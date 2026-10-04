/// How the interface starts. Release builds always start plain; Debug builds launched with
/// `-demo <scenario>` start in the state that scenario shows (see `DemoMode`).
enum Launch {
    static var tab: AppTab {
        #if DEBUG
        if let scenario = DemoMode.scenario {
            for (prefix, tab) in [("beans", AppTab.beans), ("match", .match), ("sort", .sort)] where scenario.hasPrefix(prefix) {
                return tab
            }
        }
        #endif
        return .papers
    }

    /// Whether a scenario asks for the named piece of interface to be showing.
    static func shows(_ word: String) -> Bool {
        #if DEBUG
        return DemoMode.has(word)
        #else
        return false
        #endif
    }
}
