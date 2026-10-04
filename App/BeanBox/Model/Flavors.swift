import Foundation

/// Name suggestions for the Jelly Belly 49-flavour assortment. Only an autocomplete list —
/// any name can be typed, and the flavour guide printed on the tub wins.
nonisolated enum Flavors {
    static let all = [
        "A&W Cream Soda", "A&W Root Beer", "Berry Blue", "Blueberry", "Bubble Gum", "Buttered Popcorn",
        "Cantaloupe", "Cappuccino", "Caramel Corn", "Chocolate Pudding", "Cinnamon", "Coconut",
        "Cotton Candy", "Crushed Pineapple", "Dr Pepper", "French Vanilla", "Green Apple", "Island Punch",
        "Juicy Pear", "Kiwi", "Lemon Drop", "Lemon Lime", "Licorice", "Mango", "Margarita",
        "Mixed Berry Smoothie", "Orange Sherbet", "Peach", "Piña Colada", "Plum", "Pomegranate",
        "Raspberry", "Red Apple", "Sizzling Cinnamon", "Sour Cherry", "Strawberry Cheesecake",
        "Strawberry Daiquiri", "Strawberry Jam", "Sunkist Lemon", "Sunkist Lime", "Sunkist Orange",
        "Sunkist Pink Grapefruit", "Sunkist Tangerine", "Toasted Marshmallow", "Top Banana",
        "Tutti-Fruitti", "Very Cherry", "Watermelon", "Wild Blackberry",
    ]

    /// Suggestions for what has been typed: names starting with it first, then names
    /// containing it; flavours already measured go last.
    static func suggestions(for text: String, measured: Set<String>) -> [String] {
        let query = text.trimmingCharacters(in: .whitespaces).lowercased()
        let matching = all.filter { query.isEmpty || $0.lowercased().contains(query) }
        func rank(_ name: String) -> Int {
            (measured.contains(name.lowercased()) ? 2 : 0) + (name.lowercased().hasPrefix(query) ? 0 : 1)
        }
        return matching.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
    }
}
