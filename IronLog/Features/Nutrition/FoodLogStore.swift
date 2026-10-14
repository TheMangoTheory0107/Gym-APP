import Foundation
import SwiftData

/// Turns parsed items and plan meals into saved FoodEntry rows, and learns your portion sizes.
enum FoodLogStore {
    static let mealNames = ["Pre-workout", "Post-workout", "Breakfast", "Lunch", "Evening snack", "Dinner", "Snack"]

    /// Best guess for which meal you're logging right now.
    static func defaultMeal(at date: Date = .now) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case ..<9: return "Pre-workout"
        case ..<12: return "Post-workout"
        case ..<16: return "Lunch"
        case ..<19: return "Evening snack"
        default: return "Dinner"
        }
    }

    static func learnedMap(_ portions: [LearnedPortion]) -> [String: Double] {
        Dictionary(portions.map { ($0.key, $0.grams) }, uniquingKeysWith: { a, _ in a })
    }

    static func grams(for item: ParsedFood, learned: [String: Double]) -> Double {
        if let g = item.gramsOverride { return g }
        if item.directMacros != nil { return item.qty } // pasted items are always in grams
        return FoodDatabase.shared.grams(qty: item.qty, unit: item.unit, food: item.food, learned: learned)
    }

    static func macros(for item: ParsedFood, learned: [String: Double]) -> Macros {
        let g = grams(for: item, learned: learned)
        if let direct = item.directMacros {
            let base = item.directGrams ?? g
            let k = base > 0 ? g / base : 1
            return Macros(kcal: direct.kcal * k, protein: direct.protein * k, carbs: direct.carbs * k, fat: direct.fat * k,
                          fiber: direct.fiber * k)
        }
        return item.food?.macros(grams: g) ?? Macros()
    }

    /// Saves matched items. When you corrected grams for a household unit (e.g. 1 bowl rice → 180 g),
    /// that becomes your default for that food + unit.
    static func save(_ items: [ParsedFood], meal: String, date: Date = .now, context: ModelContext,
                     learned: [String: Double]) {
        for item in items where item.isMatched {
            let g = grams(for: item, learned: learned)
            let m = macros(for: item, learned: learned)
            context.insert(FoodEntry(date: date, meal: meal, name: item.displayName, foodId: item.food?.id,
                                     grams: g, kcal: m.kcal, protein: m.protein, carbs: m.carbs, fat: m.fat, fiber: m.fiber))

            if let override = item.gramsOverride, let food = item.food, item.qty > 0,
               !["g", "ml", "kg", "l"].contains(item.unit) {
                learn(foodId: food.id, unit: item.unit, grams: override / item.qty, context: context)
            }
        }
        try? context.save()
    }

    static func learn(foodId: String, unit: String, grams: Double, context: ModelContext) {
        let key = LearnedPortion.key(foodId: foodId, unit: unit)
        let existing = try? context.fetch(FetchDescriptor<LearnedPortion>(predicate: #Predicate { $0.key == key }))
        if let p = existing?.first {
            p.grams = grams
            p.updatedAt = .now
        } else {
            context.insert(LearnedPortion(foodId: foodId, unit: unit, grams: grams))
        }
    }

    /// Plan meal as editable parsed items (for "Adjust").
    static func parsedItems(for meal: PlanMeal) -> [ParsedFood] {
        let db = FoodDatabase.shared
        return meal.items.map { item in
            let food = db.food(item.food)
            return ParsedFood(source: food?.name ?? item.food, query: food?.name ?? item.food, qty: item.qty,
                              unit: item.unit, food: food, alternatives: food.map { [$0] } ?? [],
                              gramsOverride: nil, directMacros: nil, directGrams: nil, directName: nil)
        }
    }

    /// Logged entries back as editable items (for "Edit" on a logged meal).
    static func parsedItems(for entries: [FoodEntry], custom: [FoodItem]) -> [ParsedFood] {
        entries.map { e in
            let food = e.foodId.flatMap { FoodDatabase.shared.food($0, custom: custom) }
            let direct = food == nil ? Macros(kcal: e.kcal, protein: e.protein, carbs: e.carbs, fat: e.fat, fiber: e.fiber) : nil
            return ParsedFood(source: e.name, query: e.name, qty: e.grams, unit: "g", food: food,
                              alternatives: food.map { [$0] } ?? [], gramsOverride: nil, directMacros: direct,
                              directGrams: food == nil ? e.grams : nil, directName: food == nil ? e.name : nil)
        }
    }

    static func logPlanMeal(_ meal: PlanMeal, context: ModelContext) {
        save(parsedItems(for: meal), meal: meal.name, context: context, learned: [:])
    }

    /// Sums food entries per calendar day.
    static func dailyTotals(_ entries: [FoodEntry]) -> [String: Macros] {
        var out: [String: Macros] = [:]
        for e in entries {
            out[e.date.dayKey, default: Macros()] = out[e.date.dayKey, default: Macros()]
                + Macros(kcal: e.kcal, protein: e.protein, carbs: e.carbs, fat: e.fat, fiber: e.fiber)
        }
        return out
    }
}
