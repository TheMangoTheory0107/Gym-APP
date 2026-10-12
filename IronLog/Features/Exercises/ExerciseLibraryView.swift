import SwiftUI

struct ExerciseLibraryView: View {
    private let catalog = Catalog.shared
    @State private var search = ""

    private struct LibrarySection: Identifiable {
        let group: String
        let exercises: [ExerciseDef]
        var id: String { group }
    }

    /// Exercises grouped by the muscle group of their first primary muscle.
    private var sections: [LibrarySection] {
        let filtered = catalog.exercises.filter { ex in
            search.isEmpty
                || ex.name.localizedCaseInsensitiveContains(search)
                || catalog.muscleNames(ex.primary + ex.secondary).contains { $0.localizedCaseInsensitiveContains(search) }
        }
        let grouped = Dictionary(grouping: filtered) { ex in
            ex.primary.first.flatMap { catalog.muscle($0)?.group } ?? "Cardio"
        }
        let order = ["Chest", "Back", "Shoulders", "Arms", "Legs", "Core", "Cardio"]
        return grouped
            .map { key, value in LibrarySection(group: key, exercises: value.sorted { $0.name < $1.name }) }
            .sorted { (order.firstIndex(of: $0.group) ?? 99) < (order.firstIndex(of: $1.group) ?? 99) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ScreenTitle(title: "Exercises", kicker: "\(catalog.exercises.count) movements")
                        .padding(.bottom, 6)

                    ForEach(sections) { section in
                        SectionLabel(text: section.group, accent: true)
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
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name.uppercased())
                    .font(.display(21, relativeTo: .headline))
                    .foregroundStyle(Theme.textPrimary)
                Text(Catalog.shared.muscleNames(exercise.primary + exercise.secondary).joined(separator: " · "))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.textFaint)
        }
        .cardStyle(padding: 14)
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
