import Foundation

/// One line of parsed food, editable before saving.
struct ParsedFood: Identifiable, Hashable {
    let id = UUID()
    /// What was typed for this item, e.g. "2 rotis"
    var source: String
    var query: String
    var qty: Double
    var unit: String
    var food: FoodItem?
    /// Other likely matches, best first.
    var alternatives: [FoodItem]
    /// Set when you type grams yourself; saved as your default portion for this unit.
    var gramsOverride: Double?
    /// Macros given directly (e.g. pasted from Claude), bypassing the database.
    var directMacros: Macros?
    var directGrams: Double?
    var directName: String?

    var isMatched: Bool { food != nil || directMacros != nil }
    var displayName: String { food?.name ?? directName ?? query }
}

/// Offline natural-language food parser:
/// "2 rotis, 1 bowl dal, 150g paneer, 1 banana" → items with quantity, unit and best food match.
enum FoodParser {
    // MARK: Vocabulary

    static let unitSynonyms: [String: String] = [
        "g": "g", "gm": "g", "gms": "g", "gram": "g", "grams": "g", "gr": "g", "grm": "g",
        "kg": "kg", "kgs": "kg", "kilo": "kg",
        "ml": "ml", "mls": "ml", "millilitre": "ml", "milliliter": "ml",
        "l": "l", "ltr": "l", "litre": "l", "liter": "l", "litres": "l", "liters": "l",
        "pc": "piece", "pcs": "piece", "piece": "piece", "pieces": "piece", "nos": "piece", "no": "piece",
        "medium": "piece", "small": "piece", "large": "piece", "big": "piece",
        "bowl": "bowl", "bowls": "bowl", "katori": "katori", "katoris": "katori", "katori's": "katori", "vati": "katori",
        "cup": "cup", "cups": "cup", "mug": "cup",
        "glass": "glass", "glasses": "glass",
        "tbsp": "tbsp", "tablespoon": "tbsp", "tablespoons": "tbsp", "tbs": "tbsp", "tbsps": "tbsp", "chamach": "tbsp",
        "tsp": "tsp", "teaspoon": "tsp", "teaspoons": "tsp", "tsps": "tsp", "chammach": "tsp",
        "scoop": "scoop", "scoops": "scoop",
        "slice": "slice", "slices": "slice",
        "plate": "plate", "plates": "plate", "plateful": "plate",
        "handful": "handful", "handfuls": "handful", "mutthi": "handful",
        "can": "can", "cans": "can", "tin": "can",
        "packet": "packet", "packets": "packet", "pack": "packet", "pkt": "packet",
        "bottle": "bottle", "bottles": "bottle",
        "cube": "cube", "cubes": "cube", "bar": "bar", "bars": "bar",
    ]

    static let sizeFactor: [String: Double] = ["small": 0.75, "large": 1.3, "big": 1.3]

    static let numberWords: [String: Double] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
        "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "fifteen": 15, "twenty": 20,
        "half": 0.5, "quarter": 0.25, "dozen": 12, "couple": 2,
        "ek": 1, "do": 2, "teen": 3, "char": 4, "paanch": 5, "aadha": 0.5, "adha": 0.5, "dedh": 1.5, "dhai": 2.5,
    ]

    static let fillerWords: Set<String> = ["of", "some", "x", "with", "the", "about", "around", "approx", "nearly",
                                           "cooked", "plain", "fresh", "homemade", "home", "made", "had", "ate", "i"]

    // MARK: Parsing

    /// Splits text into items and parses each one.
    static func parse(_ text: String, foods: [FoodItem], learned: [String: Double] = [:]) -> [ParsedFood] {
        var normalised = text.lowercased()
            .replacingOccurrences(of: "½", with: " 0.5 ")
            .replacingOccurrences(of: "¼", with: " 0.25 ")
            .replacingOccurrences(of: "\n", with: ",")
            .replacingOccurrences(of: ";", with: ",")
            .replacingOccurrences(of: "+", with: ",")
            .replacingOccurrences(of: "&", with: ",")
        normalised = normalised.replacingOccurrences(of: " and ", with: ",")
            .replacingOccurrences(of: " aur ", with: ",")
            .replacingOccurrences(of: " plus ", with: ",")

        return normalised.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters.subtracting(CharacterSet(charactersIn: "./")))) }
            .filter { !$0.isEmpty }
            .map { parseItem(String($0), foods: foods) }
    }

    static func parseItem(_ raw: String, foods: [FoodItem]) -> ParsedFood {
        // Split "150g" → "150 g", "2x" → "2 x", "1.5kg" → "1.5 kg"
        let spaced = raw.replacingOccurrences(of: #"(\d)([a-z])"#, with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: #"([a-z])(\d)"#, with: "$1 $2", options: .regularExpression)
        let tokens = spaced.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)

        var qty: Double?
        var unit: String?
        var factor = 1.0
        var nameTokens: [String] = []

        var i = 0
        while i < tokens.count {
            let t = tokens[i].trimmingCharacters(in: CharacterSet(charactersIn: "().,"))
            if t.isEmpty { i += 1; continue }
            if let n = number(t) {
                qty = qty.map { $0 * n } ?? n   // "2 x 100 g" multiplies
                i += 1; continue
            }
            if qty == nil, nameTokens.isEmpty, let n = numberWords[t] {
                qty = n; i += 1; continue
            }
            if let f = sizeFactor[t] { factor = f; if unit == nil { unit = "piece" }; i += 1; continue }
            if unit == nil, let u = unitSynonyms[t] {
                unit = u; i += 1; continue
            }
            if fillerWords.contains(t) { i += 1; continue }
            nameTokens.append(t)
            i += 1
        }
        let query = nameTokens.joined(separator: " ")
        let ranked = rank(query: query, foods: foods)
        let best = ranked.first.flatMap { $0.score >= 0.55 ? $0.food : nil }

        let finalUnit = unit ?? defaultUnit(for: best)
        let finalQty = (qty ?? 1) * factor

        return ParsedFood(source: raw, query: query.isEmpty ? raw : query, qty: finalQty, unit: finalUnit,
                          food: best, alternatives: ranked.prefix(6).map(\.food), gramsOverride: nil,
                          directMacros: nil, directGrams: nil, directName: nil)
    }

    /// Unit to assume when none is typed: "2 rotis" → piece, "dal" → bowl, "rice" → bowl.
    static func defaultUnit(for food: FoodItem?) -> String {
        guard let food else { return "g" }
        for u in ["piece", "slice", "bowl", "glass", "scoop", "plate", "cup", "handful", "katori", "tsp"] where food.units[u] != nil {
            return u
        }
        return "g"
    }

    static func number(_ t: String) -> Double? {
        if let d = Double(t) { return d }
        let parts = t.split(separator: "/")
        if parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]), b != 0 { return a / b }
        return nil
    }

    // MARK: Fuzzy matching

    struct Ranked { let food: FoodItem; let score: Double }

    static func rank(query: String, foods: [FoodItem]) -> [Ranked] {
        let q = normalise(query)
        guard !q.isEmpty else { return [] }
        return foods
            .map { food in
                let names = [food.name] + food.aliases
                let best = names.map { similarity(q, normalise($0)) }.max() ?? 0
                // Small boost for your own foods so they win ties.
                return Ranked(food: food, score: best + (food.isCustom ? 0.02 : 0))
            }
            .filter { $0.score > 0.3 }
            .sorted { $0.score > $1.score }
    }

    /// Lowercase, strip punctuation, singularise simple plurals ("rotis" → "roti", "eggs" → "egg").
    static func normalise(_ s: String) -> String {
        s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map(singular)
            .joined(separator: " ")
    }

    static func singular(_ w: String) -> String {
        guard w.count > 3 else { return w }
        if w.hasSuffix("ies") { return String(w.dropLast(3)) + "y" }
        if w.hasSuffix("oes") { return String(w.dropLast(2)) }
        if w.hasSuffix("s"), !w.hasSuffix("ss") { return String(w.dropLast()) }
        return w
    }

    /// 0…1 score combining whole-string edit distance and per-token fuzzy overlap.
    static func similarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        let whole = 1 - Double(levenshtein(a, b)) / Double(max(a.count, b.count, 1))

        let ta = a.split(separator: " ").map(String.init)
        let tb = b.split(separator: " ").map(String.init)
        // Each query token finds its best partner in the candidate.
        var matched = 0.0
        for x in ta {
            let best = tb.map { y -> Double in
                if x == y { return 1 }
                if y.hasPrefix(x) && x.count >= 3 { return 0.9 }
                let r = 1 - Double(levenshtein(x, y)) / Double(max(x.count, y.count))
                return r >= 0.75 ? r : 0
            }.max() ?? 0
            matched += best
        }
        let recall = matched / Double(ta.count)          // how much of what you typed was found
        let precision = matched / Double(max(tb.count, 1)) // how much of the candidate is covered
        let token = 0.7 * recall + 0.3 * precision
        return max(whole, token)
    }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }

    // MARK: Claude prompt round-trip

    static func claudePrompt(for meal: String) -> String {
        """
        Estimate the nutrition for this Indian/gym meal: "\(meal.isEmpty ? "<describe your meal>" : meal)".
        Reply with ONLY a JSON array, no other text. One object per food item, with these keys:
        "name" (string), "grams" (number, cooked weight), "kcal", "protein", "carbs", "fat" (numbers, for that portion, in grams).
        Example: [{"name":"Roti","grams":80,"kcal":224,"protein":6.8,"carbs":38,"fat":4.4}]
        """
    }

    /// Reads the JSON Claude returned (tolerates text around it).
    static func parseClaudeJSON(_ text: String) -> [ParsedFood]? {
        guard let start = text.firstIndex(of: "["), let end = text.lastIndex(of: "]"), start < end else { return nil }
        let slice = String(text[start...end])
        struct Item: Decodable {
            let name: String
            let grams: Double?
            let kcal: Double
            let protein: Double?
            let carbs: Double?
            let fat: Double?
        }
        guard let data = slice.data(using: .utf8),
              let items = try? JSONDecoder().decode([Item].self, from: data), !items.isEmpty else { return nil }
        return items.map { it in
            ParsedFood(source: it.name, query: it.name, qty: it.grams ?? 100, unit: "g", food: nil, alternatives: [],
                       gramsOverride: nil,
                       directMacros: Macros(kcal: it.kcal, protein: it.protein ?? 0, carbs: it.carbs ?? 0, fat: it.fat ?? 0),
                       directGrams: it.grams, directName: it.name)
        }
    }
}
