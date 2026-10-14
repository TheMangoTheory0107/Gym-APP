import SwiftData
import SwiftUI

/// Create your own exercise. It's saved on the phone and works like any library exercise.
struct AddExerciseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    var onSaved: (ExerciseDef) -> Void

    @State private var name = ""
    @State private var logType: LogType = .weightReps
    @State private var equipment = "dumbbell"
    @State private var primary: Set<String> = []
    @State private var secondary: Set<String> = []

    private let equipmentChoices = ["barbell", "dumbbell", "cable", "machine", "kettlebell", "ez-bar", "bands",
                                    "bodyweight", "other"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, e.g. Landmine Press", text: $name)
                    Picker("Logged as", selection: $logType) {
                        Text("Weight × reps").tag(LogType.weightReps)
                        Text("Reps only").tag(LogType.reps)
                        Text("Seconds held").tag(LogType.seconds)
                        Text("Minutes").tag(LogType.minutes)
                    }
                    Picker("Equipment", selection: $equipment) {
                        ForEach(equipmentChoices, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                } header: { Text("EXERCISE") }

                Section {
                    muscleGrid(selection: $primary, other: $secondary)
                } header: { Text("MAIN MUSCLES (BRIGHT RED)") }

                Section {
                    muscleGrid(selection: $secondary, other: $primary)
                } header: { Text("HELPER MUSCLES (DARK RED)") }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("NEW EXERCISE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || primary.isEmpty)
                }
            }
        }
    }

    private func muscleGrid(selection: Binding<Set<String>>, other: Binding<Set<String>>) -> some View {
        WrapLayout(spacing: 6) {
            ForEach(Catalog.shared.muscles) { m in
                let on = selection.wrappedValue.contains(m.id)
                Button {
                    Haptics.select()
                    if on { selection.wrappedValue.remove(m.id) } else {
                        selection.wrappedValue.insert(m.id)
                        other.wrappedValue.remove(m.id)
                    }
                } label: {
                    Text(m.name.uppercased())
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .foregroundStyle(on ? Color.white : Theme.textSecondary)
                        .background(on ? Theme.accent : Theme.cardRaised, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private func save() {
        let clean = name.trimmingCharacters(in: .whitespaces)
        let slug = clean.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: "-")
        let id = "custom-\(slug)-\(Int(Date.now.timeIntervalSince1970) % 100_000)"
        let order = Catalog.shared.muscles.map(\.id)
        let custom = CustomExercise(id: id, name: clean, logType: logType.rawValue, equipment: equipment,
                                    primary: order.filter(primary.contains), secondary: order.filter(secondary.contains))
        context.insert(custom)
        try? context.save()
        let all = (try? context.fetch(FetchDescriptor<CustomExercise>())) ?? [custom]
        Catalog.shared.register(custom: all.map(\.definition))
        Haptics.success()
        onSaved(custom.definition)
        dismiss()
    }
}

/// Pick any exercise (library + yours), e.g. to add it to today's workout.
struct ExercisePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (ExerciseDef) -> Void
    @State private var search = ""
    @State private var group: LibraryGroup = .all
    @State private var showAdd = false

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
                    Button {
                        showAdd = true
                    } label: {
                        Label("Create my own exercise", systemImage: "plus.circle.fill")
                    }
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
            .sheet(isPresented: $showAdd) {
                AddExerciseSheet { ex in
                    onPick(ex)
                    dismiss()
                }
            }
        }
    }
}
