import SwiftData
import SwiftUI

/// Pick any exercise from the library, e.g. to add it to today's workout.
struct ExercisePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (ExerciseDef) -> Void
    @State private var search = ""
    @State private var group: LibraryGroup = .all

    private var results: [ExerciseDef] {
        let q = search.trimmingCharacters(in: .whitespaces)
        return Catalog.shared.exercises
            .filter { group == .all || LibraryGroup.of($0) == group }
            .filter { q.isEmpty || $0.name.localizedCaseInsensitiveContains(q)
                || Catalog.shared.muscleNames($0.primary).contains { $0.localizedCaseInsensitiveContains(q) } }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Group", selection: $group) {
                        ForEach(LibraryGroup.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.accent)
                }
                .listRowBackground(Theme.card)

                Section {
                    ForEach(results) { ex in
                        Button {
                            Haptics.success()
                            onPick(ex)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ex.name).foregroundStyle(Theme.textPrimary)
                                Text(([ex.equipment.capitalized] + Catalog.shared.muscleNames(ex.primary)).joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                } header: { Text("\(results.count) EXERCISES") }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search exercise or muscle")
            .navigationTitle("ADD EXERCISE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
