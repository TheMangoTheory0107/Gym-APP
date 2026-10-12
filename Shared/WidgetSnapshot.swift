import Foundation

/// What the Home Screen widget shows. The app writes it; the widget reads it.
/// Sharing needs the App Group below (see README → "Widget calories"). Without it the widget
/// still shows today's workout from split.json.
struct WidgetSnapshot: Codable {
    static let appGroup = "group.com.themangotheory.ironlog"
    private static let key = "widget.snapshot"

    var date: Date
    var workoutName: String
    var kcalLeft: Int
    var proteinLeft: Int
    var workoutDone: Bool

    static var store: UserDefaults? { UserDefaults(suiteName: appGroup) }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        WidgetSnapshot.store?.set(data, forKey: WidgetSnapshot.key)
    }

    static func load() -> WidgetSnapshot? {
        guard let data = store?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Today's split day name straight from split.json (works without the App Group).
    static func plannedWorkout(on date: Date = .now) -> String {
        struct Day: Decodable { let day: String; let name: String }
        struct File: Decodable { let days: [Day] }
        let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let today = names[Calendar.current.component(.weekday, from: date) - 1].lowercased()
        guard let url = Bundle.main.url(forResource: "split", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return "" }
        return file.days.first { $0.day.lowercased() == today }?.name ?? ""
    }
}
