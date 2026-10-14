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
    @AppStorage(ProfileKey.onboarded) private var onboarded = false

    var body: some View {
        TabView(selection: $tab) {
            HomeView()
                .tabItem { Label("HOME", systemImage: "house") }
                .tag(AppTab.today)

            ExerciseLibraryView()
                .tabItem { Label("EXERCISES", systemImage: "dumbbell") }
                .tag(AppTab.exercises)

            NutritionView()
                .tabItem { Label("FOOD", systemImage: "fork.knife") }
                .tag(AppTab.nutrition)

            ProgressTabView()
                .tabItem { Label("PROGRESS", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(AppTab.progress)
        }
        .onChange(of: tab) { _, _ in Haptics.select() }
        .fullScreenCover(isPresented: Binding(get: { !onboarded }, set: { if !$0 { onboarded = true } })) {
            OnboardingView { onboarded = true }
        }
        .task {
            seedIfNeeded()
            let custom = (try? context.fetch(FetchDescriptor<CustomExercise>())) ?? []
            Catalog.shared.register(custom: custom.map(\.definition))
            WidgetSync.update(context: context)
            PhoneWatchBridge.shared.configure(container: context.container)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { WidgetSync.update(context: context) }
            if phase == .active {
                RestTimer.shared.refresh()
                PhoneWatchBridge.shared.sendPlan()
                Task { await HealthData.shared.refresh() }
            }
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
