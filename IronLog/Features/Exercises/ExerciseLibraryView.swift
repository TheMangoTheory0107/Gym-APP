import SwiftData
import SwiftUI

/// Grouping used by the library filters.
enum LibraryGroup: String, CaseIterable, Identifiable {
    case all = "All", chest = "Chest", back = "Back", shoulders = "Shoulders", arms = "Arms",
         legs = "Legs", core = "Core", cardio = "Cardio", stretching = "Stretching"
    var id: String { rawValue }

    static func of(_ ex: ExerciseDef) -> LibraryGroup {
        if ex.category == "stretching" { return .stretching }
        if ex.logType == .minutes || ex.category == "cardio" { return .cardio }
        let group = ex.primary.first.flatMap { Catalog.shared.muscle($0)?.group } ?? ""
        return LibraryGroup(rawValue: group) ?? .core
    }
}

struct ExerciseLibraryView: View {
    @State private var search = ""
    @State private var group: LibraryGroup = .all
    @State private var equipment = "Any"

    private var catalog: Catalog { Catalog.shared }

    private var equipmentOptions: [String] {
        ["Any"] + Set(catalog.exercises.map(\.equipment)).sorted()
    }

    private var filtered: [ExerciseDef] {
        let q = search.trimmingCharacters(in: .whitespaces)
        return catalog.exercises.filter { ex in
            (group == .all || LibraryGroup.of(ex) == group)
                && (equipment == "Any" || ex.equipment == equipment)
                && (q.isEmpty
                    || ex.name.localizedCaseInsensitiveContains(q)
                    || catalog.muscleNames(ex.primary + ex.secondary).contains { $0.localizedCaseInsensitiveContains(q) })
        }
    }

    private struct LibrarySection: Identifiable {
        let title: String
        let exercises: [ExerciseDef]
        var id: String { title }
    }

    /// Your routine and your own exercises first, then everything else A–Z by group.
    private var sections: [LibrarySection] {
        let list = filtered
        let mine = catalog.splitExerciseIds
        var out: [LibrarySection] = []
        let routine = list.filter { mine.contains($0.id) }.sorted { $0.name < $1.name }
        if !routine.isEmpty { out.append(LibrarySection(title: "Your routine", exercises: routine)) }
        let custom = list.filter(\.isCustom).sorted { $0.name < $1.name }
        if !custom.isEmpty { out.append(LibrarySection(title: "Your exercises", exercises: custom)) }
        let others = list.filter { !mine.contains($0.id) && !$0.isCustom }
        let grouped = Dictionary(grouping: others, by: LibraryGroup.of)
        for g in LibraryGroup.allCases where g != .all {
            if let items = grouped[g], !items.isEmpty {
                out.append(LibrarySection(title: g.rawValue, exercises: items.sorted { $0.name < $1.name }))
            }
        }
        return out
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10, pinnedViews: []) {
                    ScreenTitle(title: "Exercises", kicker: "\(filtered.count) of \(catalog.exercises.count) movements")
                        .padding(.bottom, 2)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(LibraryGroup.allCases) { g in
                                Button {
                                    Haptics.select()
                                    group = g
                                } label: {
                                    Text(g.rawValue.uppercased())
                                        .font(.display(17))
                                        .padding(.horizontal, 12)
                                        .frame(minHeight: 36)
                                        .foregroundStyle(group == g ? Color.white : Theme.textSecondary)
                                        .background(group == g ? Theme.accent : Theme.card, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Menu {
                        Picker("Equipment", selection: $equipment) {
                            ForEach(equipmentOptions, id: \.self) { Text($0.capitalized).tag($0) }
                        }
                    } label: {
                        Label("Equipment: \(equipment.capitalized)", systemImage: "line.3.horizontal.decrease.circle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(equipment == "Any" ? Theme.textSecondary : Theme.accent)
                    }
                    .padding(.vertical, 4)

                    if filtered.isEmpty {
                        EmptyStateCard(icon: "magnifyingglass", title: "Nothing found",
                                       message: "Try another name, or clear the filters.")
                    }

                    ForEach(sections) { section in
                        SectionLabel(text: "\(section.title) · \(section.exercises.count)", accent: true)
                            .padding(.top, 10)
                        ForEach(section.exercises) { ex in
                            NavigationLink(value: ex) { LibraryRow(exercise: ex) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 32)
            }
            .screenBackground()
            .searchable(text: $search, prompt: "Search exercise or muscle")
            .navigationDestination(for: ExerciseDef.self) { ExerciseDetailView(exercise: $0) }
        }
    }
}

private struct LibraryRow: View {
    let exercise: ExerciseDef

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let thumb = BundledImage.load("form_\(exercise.id)_0") {
                    Image(uiImage: thumb).resizable().scaledToFill()
                } else {
                    Image(systemName: exercise.isCustom ? "star.fill" : "figure.strengthtraining.traditional")
                        .foregroundStyle(Theme.textFaint)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.cardRaised)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name.uppercased())
                    .font(.display(19, relativeTo: .headline))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(([exercise.equipment.capitalized] + Catalog.shared.muscleNames(exercise.primary)).joined(separator: " · "))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.textFaint)
        }
        .cardStyle(padding: 10)
        .contentShape(Rectangle())
    }
}

struct BulletCard: View {
    let title: String
    let items: [String]
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: title)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 16, alignment: .center)
                        .padding(.top, 2)
                    Text(item)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                }
            }
        }
        .cardStyle()
    }
}

/// Wrapping row of tags.
struct FlowTags: View {
    let names: [String]
    let filled: Bool

    var body: some View {
        WrapLayout(spacing: 6) {
            ForEach(names, id: \.self) { Tag(text: $0, filled: filled) }
        }
    }
}

/// Minimal flow layout: places views left-to-right and wraps to new lines.
struct WrapLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
