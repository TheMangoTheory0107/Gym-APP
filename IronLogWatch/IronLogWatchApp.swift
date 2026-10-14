import SwiftUI

@main
struct IronLogWatchApp: App {
    @State private var store = WatchStore()
    @State private var workout = WorkoutManager()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(store)
                .environment(workout)
                .onAppear { store.activate() }
        }
    }
}

enum WatchTheme {
    static let accent = Color(red: 0xE0 / 255, green: 0x14 / 255, blue: 0x2F / 255)
    static let ember = Color(red: 1, green: 0x5A / 255, blue: 0x36 / 255)
    static let card = Color(white: 0.11)
    static let faint = Color(white: 0.55)
    static let gradient = LinearGradient(colors: [accent, ember], startPoint: .leading, endPoint: .trailing)
}

extension Font {
    /// Tall, condensed numbers and headings, close to the iPhone app's Bebas look.
    static func heavy(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy) }
}
