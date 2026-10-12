import Foundation

/// A food with macros per 100 g (or 100 ml).
struct FoodItem: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let category: String
    let aliases: [String]
    let kcal: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    /// Grams in one household unit, e.g. ["piece": 40, "bowl": 150]
    let units: [String: Double]
    var isCustom = false

    enum CodingKeys: String, CodingKey { case id, name, category, aliases, kcal, protein, carbs, fat, units }

    init(id: String, name: String, category: String, aliases: [String], kcal: Double, protein: Double,
         carbs: Double, fat: Double, units: [String: Double], isCustom: Bool = false) {
        self.id = id; self.name = name; self.category = category; self.aliases = aliases
        self.kcal = kcal; self.protein = protein; self.carbs = carbs; self.fat = fat
        self.units = units; self.isCustom = isCustom
    }

    init(custom: CustomFood) {
        self.init(id: custom.id, name: custom.name, category: "My foods", aliases: custom.aliases,
                  kcal: custom.kcalPer100g, protein: custom.proteinPer100g, carbs: custom.carbsPer100g,
                  fat: custom.fatPer100g, units: [:], isCustom: true)
    }

    func macros(grams: Double) -> Macros {
        let k = grams / 100
        return Macros(kcal: kcal * k, protein: protein * k, carbs: carbs * k, fat: fat * k)
    }
}

struct Macros: Hashable {
    var kcal: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0

    static func + (a: Macros, b: Macros) -> Macros {
        Macros(kcal: a.kcal + b.kcal, protein: a.protein + b.protein, carbs: a.carbs + b.carbs, fat: a.fat + b.fat)
    }
}

struct PlanItem: Codable, Hashable {
    let food: String
    let qty: Double
    let unit: String
}

struct PlanMeal: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let time: String
    let note: String?
    let items: [PlanItem]
}

struct SupplementDef: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let when: String
    let hour: Int
    let minute: Int
    let trackStreak: Bool?
    let optional: Bool?
}

private struct FoodFile: Codable { let genericUnits: [String: Double]; let foods: [FoodItem] }
private struct PlanFile: Codable { let meals: [PlanMeal] }
private struct SupplementFile: Codable { let supplements: [SupplementDef] }

/// Bundled food database (foods.json), diet plan and supplements.
final class FoodDatabase {
    static let shared = FoodDatabase()

    let foods: [FoodItem]
    let genericUnits: [String: Double]
    let plan: [PlanMeal]
    let supplements: [SupplementDef]
    private(set) var loadErrors: [String] = []
    private let byId: [String: FoodItem]

    private init() {
        var errors: [String] = []
        let file: FoodFile? = FoodDatabase.load("foods", errors: &errors)
        foods = file?.foods ?? []
        genericUnits = file?.genericUnits ?? ["g": 1, "ml": 1]
        plan = (FoodDatabase.load("diet_plan", errors: &errors) as PlanFile?)?.meals ?? []
        supplements = (FoodDatabase.load("supplements", errors: &errors) as SupplementFile?)?.supplements ?? []
        byId = Dictionary(foods.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for meal in plan {
            for item in meal.items where byId[item.food] == nil {
                errors.append("diet_plan.json: \(meal.name) uses unknown food \"\(item.food)\"")
            }
        }
        loadErrors = errors
    }

    func food(_ id: String, custom: [FoodItem] = []) -> FoodItem? {
        byId[id] ?? custom.first { $0.id == id }
    }

    /// Grams for `qty` × `unit` of a food: learned portion → food's own unit → generic unit.
    func grams(qty: Double, unit: String, food: FoodItem?, learned: [String: Double] = [:]) -> Double {
        if unit == "g" || unit == "ml" { return qty }
        if unit == "kg" || unit == "l" { return qty * 1000 }
        if let food, let g = learned[LearnedPortion.key(foodId: food.id, unit: unit)] { return qty * g }
        if let g = food?.units[unit] { return qty * g }
        return qty * (genericUnits[unit] ?? 100)
    }

    /// Units that make sense for a food, for the unit picker.
    func unitOptions(for food: FoodItem?) -> [String] {
        var list = ["g"]
        if let food { list += food.units.keys.sorted() }
        for u in ["piece", "bowl", "katori", "cup", "tbsp", "tsp", "scoop", "slice", "plate", "glass", "ml"] where !list.contains(u) {
            list.append(u)
        }
        return list
    }

    func macros(of meal: PlanMeal) -> Macros {
        meal.items.reduce(Macros()) { total, item in
            guard let f = food(item.food) else { return total }
            return total + f.macros(grams: grams(qty: item.qty, unit: item.unit, food: f))
        }
    }

    var planTotal: Macros { plan.reduce(Macros()) { $0 + macros(of: $1) } }

    private static func load<T: Decodable>(_ name: String, errors: inout [String]) -> T? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            errors.append("\(name).json is missing from the app bundle")
            return nil
        }
        do {
            return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
        } catch {
            errors.append("\(name).json: \(error.localizedDescription)")
            return nil
        }
    }
}
