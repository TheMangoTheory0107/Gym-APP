import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case today, exercises, nutrition, progress
}

struct RootTabView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(ProfileKey.didSeed) private var didSeed = false
    @State private var tab: AppTab = .today

    var body: some View {
        TabView(selection: $tab) {
            TodayView()
                .tabItem { Label("TODAY", systemImage: "flame.fill") }
                .tag(AppTab.today)

            ExerciseLibraryView()
                .tabItem { Label("EXERCISES", systemImage: "figure.strengthtraining.traditional") }
                .tag(AppTab.exercises)

            NutritionView()
                .tabItem { Label("NUTRITION", systemImage: "fork.knife") }
                .tag(AppTab.nutrition)

            ProgressTabView()
                .tabItem { Label("PROGRESS", systemImage: "chart.xyaxis.line") }
                .tag(AppTab.progress)
        }
        .onChange(of: tab) { _, _ in Haptics.select() }
        .task {
            seedIfNeeded()
            WidgetSync.update(context: context)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { WidgetSync.update(context: context) }
            if phase == .active { RestTimer.shared.refresh() }
        }
    }

    /// First launch only: store the starting weigh-in from the brief.
    private func seedIfNeeded() {
        guard !didSeed else { return }
        let existing = (try? context.fetchCount(FetchDescriptor<BodyMetric>())) ?? 0
        if existing == 0 {
            context.insert(BodyMetric(weightKg: ProfileDefault.startWeightKg,
                                      bodyFatPercent: ProfileDefault.startBodyFat))
            try? context.save()
        }
        didSeed = true
    }
}
