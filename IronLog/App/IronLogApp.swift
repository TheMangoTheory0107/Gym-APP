import SwiftData
import SwiftUI

@main
struct IronLogApp: App {
    init() {
        FontRegistrar.registerAll()
        Appearance.configure()
        NotificationManager.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        .modelContainer(for: AppSchema.models)
    }
}
