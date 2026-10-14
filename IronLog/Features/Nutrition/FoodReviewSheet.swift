import SwiftData
import SwiftUI
import UIKit

/// Shows what the parser understood so you can fix quantities, units or matches before saving.
struct FoodReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var learnedPortions: [LearnedPortion]
    @Query(sort: \CustomFood.name) private var customFoods: [CustomFood]

    @State var items: [ParsedFood]
    @State var meal: String
    let title: String
    /// Entries this review replaces (editing a meal you already logged).
    var replacing: [FoodEntry] = []

    @State private var addingFor: ParsedFood.ID?
    @State private var searchingFor: ParsedFood.ID?

    private var learned: [String: Double] { FoodLogStore.learnedMap(learnedPortions) }
    private var allFoods: [FoodItem] { FoodDatabase.shared.foods + customFoods.map(FoodItem.init(custom:)) }

    private var total: Macros {
        items.filter(\.isMatched).reduce(Macros()) { $0 + FoodLogStore.macros(for: $1, learned: learned) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Meal", selection: $meal) {
                        ForEach(FoodLogStore.mealNames, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.accent)
                    .cardStyle(padding: 10)

                    ForEach($items) { $item in
                        ParsedRow(item: $item, learned: learned,
                                  onAddFood: { addingFor = item.id },
                                  onSearch: { searchingFor = item.id },
                                  onDelete: { withAnimation { items.removeAll { $0.id == item.id } } })
                    }

                    HStack {
                        StatTile(label: "Kcal", value: "\(Int(total.kcal))", highlight: true)
                        StatTile(label: "Protein", value: "\(Int(total.protein))", unit: "g")
                        StatTile(label: "Carbs", value: "\(Int(total.carbs))", unit: "g")
                        StatTile(label: "Fat", value: "\(Int(total.fat))", unit: "g")
                    }
                    .cardStyle()

                    let unmatched = items.filter { !$0.isMatched }.count
                    if unmatched > 0 {
                        Text("\(unmatched) item\(unmatched == 1 ? "" : "s") not matched. Add or pick a food, or remove it; unmatched items aren't saved.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    Button("Save to \(meal)") { save() }
                    .buttonStyle(.primary)
                    .disabled(!items.contains(where: \.isMatched))
                }
                .padding(Theme.gutter)
            }
            .screenBackground()
            .navigationTitle(title.uppercased())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.bold)
                        .disabled(!items.contains(where: \.isMatched))
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .fontWeight(.bold)
                }
            }
            .sheet(item: Binding(get: { addingFor.map(IDBox.init) }, set: { addingFor = $0?.id })) { box in
                AddFoodSheet(suggestedName: items.first { $0.id == box.id }?.query ?? "") { newFood in
                    if let i = items.firstIndex(where: { $0.id == box.id }) {
                        items[i].food = newFood
                        items[i].unit = "g"
                        if items[i].qty < 5 { items[i].qty = 100 }
                    }
                }
            }
            .sheet(item: Binding(get: { searchingFor.map(IDBox.init) }, set: { searchingFor = $0?.id })) { box in
                FoodSearchSheet(foods: allFoods, initial: items.first { $0.id == box.id }?.query ?? "") { picked in
                    if let i = items.firstIndex(where: { $0.id == box.id }) {
                        items[i].food = picked
                        items[i].gramsOverride = nil
                        if !FoodDatabase.shared.unitOptions(for: picked).contains(items[i].unit) {
                            items[i].unit = FoodParser.defaultUnit(for: picked)
                        }
                    }
                }
            }
        }
    }
}

private struct IDBox: Identifiable { let id: UUID }

extension FoodReviewSheet {
    func save() {
        // Make sure a number still being typed is applied before saving.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        DispatchQueue.main.async {
            for entry in replacing { context.delete(entry) }
            FoodLogStore.save(items, meal: meal, context: context, learned: learned)
            Haptics.success()
            dismiss()
        }
    }
}

private struct ParsedRow: View {
    @Binding var item: ParsedFood
    let learned: [String: Double]
    let onAddFood: () -> Void
    let onSearch: () -> Void
    let onDelete: () -> Void

    @State private var gramsText = ""
    @FocusState private var gramsFocused: Bool

    private var grams: Double { FoodLogStore.grams(for: item, learned: learned) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("“\(item.source)”")
                        .font(.caption)
                        .foregroundStyle(Theme.textFaint)
                    if item.isMatched {
                        Menu {
                            ForEach(item.alternatives.filter { $0.id != item.food?.id }.prefix(5)) { alt in
                                Button(alt.name) {
                                    item.food = alt
                                    item.gramsOverride = nil
                                    if !FoodDatabase.shared.unitOptions(for: alt).contains(item.unit) {
                                        item.unit = FoodParser.defaultUnit(for: alt)
                                    }
                                }
                            }
                            Button("Search all foods…", systemImage: "magnifyingglass", action: onSearch)
                        } label: {
                            HStack(spacing: 4) {
                                Text(item.displayName.uppercased())
                                    .font(.display(22))
                                    .foregroundStyle(Theme.textPrimary)
                                if item.directMacros == nil {
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                        .disabled(item.directMacros != nil)
                    } else {
                        Text("NOT FOUND: \(item.query.uppercased())")
                            .font(.display(20))
                            .foregroundStyle(Theme.accent)
                    }
                }
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(Theme.textFaint)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
            }

            if item.isMatched {
                HStack(spacing: 8) {
                    // Quantity
                    HStack(spacing: 0) {
                        stepButton("minus") { item.qty = max(item.qty - qtyStep, qtyStep); item.gramsOverride = nil }
                        Text(Fmt.weight(item.qty))
                            .font(.display(22))
                            .monospacedDigit()
                            .frame(minWidth: 40)
                        stepButton("plus") { item.qty += qtyStep; item.gramsOverride = nil }
                    }
                    .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 10))

                    if item.directMacros == nil {
                        Menu {
                            ForEach(FoodDatabase.shared.unitOptions(for: item.food), id: \.self) { u in
                                Button(u) { item.unit = u; item.gramsOverride = nil }
                            }
                        } label: {
                            Text(item.unit.uppercased())
                                .font(.display(18))
                                .frame(minWidth: 64, minHeight: 40)
                                .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }

                    Spacer()

                    // Grams (type to correct; remembered for this unit)
                    HStack(spacing: 2) {
                        TextField("g", text: $gramsText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.display(22))
                            .frame(width: 58)
                            .focused($gramsFocused)
                            .onSubmit(commitGrams)
                            .onChange(of: gramsFocused) { _, focused in if !focused { commitGrams(); syncText() } }
                        Text("G").font(.display(16)).foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.horizontal, 8)
                    .frame(minHeight: 40)
                    .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 10))
                }

                let m = FoodLogStore.macros(for: item, learned: learned)
                Text("\(Int(m.kcal)) kcal · P \(Int(m.protein)) · C \(Int(m.carbs)) · F \(Int(m.fat)) · Fib \(Int(m.fiber))"
                     + (item.gramsOverride != nil && !["g", "ml"].contains(item.unit) ? "  · will remember \(Fmt.weight(item.gramsOverride! / max(item.qty, 0.01))) g per \(item.unit)" : ""))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                HStack(spacing: 10) {
                    Button("Pick a food", action: onSearch).buttonStyle(.secondary)
                    Button("Add new food", action: onAddFood).buttonStyle(.primary)
                }
            }
        }
        .cardStyle(padding: 14)
        .onAppear { syncText() }
        .onChange(of: gramsText) { _, _ in if gramsFocused { commitGrams() } }
        .onChange(of: item.qty) { _, _ in if !gramsFocused { syncText() } }
        .onChange(of: item.unit) { _, _ in syncText() }
        .onChange(of: item.food?.id) { _, _ in syncText() }
    }

    private func syncText() { gramsText = Fmt.weight((grams * 10).rounded() / 10) }

    private var qtyStep: Double { ["g", "ml"].contains(item.unit) ? 10 : 0.5 }

    private func commitGrams() {
        guard let g = Double(gramsText.replacingOccurrences(of: ",", with: ".")), g > 0 else { return }
        if abs(g - grams) < 0.05 { return }
        if ["g", "ml"].contains(item.unit) || item.directMacros != nil {
            item.qty = g
        } else {
            item.gramsOverride = g
        }
    }

    private func stepButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .heavy))
                .frame(width: 36, height: 40)
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
    }
}

/// Search the whole food list (built-in + your own).
struct FoodSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    let foods: [FoodItem]
    @State var initial: String
    let onPick: (FoodItem) -> Void

    private var results: [FoodItem] {
        let q = initial.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return foods.sorted { $0.name < $1.name } }
        return FoodParser.rank(query: q, foods: foods).map(\.food)
    }

    var body: some View {
        NavigationStack {
            List(results) { food in
                Button {
                    onPick(food)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(food.name).foregroundStyle(Theme.textPrimary)
                        Text("\(Int(food.kcal)) kcal · P \(Fmt.weight(food.protein)) g per 100 g · \(food.category)")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .searchable(text: $initial, placement: .navigationBarDrawer(displayMode: .always))
            .navigationTitle("PICK FOOD")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

/// Add a food that isn't in the database. It's remembered for next time.
struct AddFoodSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State var suggestedName: String
    let onSaved: (FoodItem) -> Void

    @State private var kcal = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var aliases = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $suggestedName)
                    TextField("Other names (comma separated)", text: $aliases)
                } header: { Text("FOOD") }
                Section {
                    field("Calories (kcal)", $kcal)
                    field("Protein (g)", $protein)
                    field("Carbs (g)", $carbs)
                    field("Fat (g)", $fat)
                } header: { Text("PER 100 G") } footer: {
                    Text("Check the nutrition label on the pack, or use “Copy prompt for Claude” on the Nutrition tab.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("ADD FOOD")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(suggestedName.isEmpty || Double(kcal) == nil)
                }
            }
        }
    }

    private func field(_ label: String, _ text: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: text).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
        }
    }

    private func save() {
        let id = "custom-" + suggestedName.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-")
        let food = CustomFood(id: id, name: suggestedName,
                              aliases: aliases.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
                              kcalPer100g: Double(kcal) ?? 0, proteinPer100g: Double(protein) ?? 0,
                              carbsPer100g: Double(carbs) ?? 0, fatPer100g: Double(fat) ?? 0)
        context.insert(food)
        try? context.save()
        Haptics.success()
        onSaved(FoodItem(custom: food))
        dismiss()
    }
}
