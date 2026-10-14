import Foundation
import SwiftData

/// Exports / imports everything you've logged as one JSON file, so you never lose history.
enum BackupService {
    static let currentVersion = 1

    struct Backup: Codable {
        var version: Int
        var exportedAt: Date
        var settings: [String: Double]
        var sessions: [Session]
        var bodyMetrics: [Metric]
        var food: [Food]
        var customFoods: [Custom]
        var learnedPortions: [Portion]
        var supplements: [Supplement]
        /// Added later; older backups don't have it.
        var customExercises: [Exercise]?
    }

    struct Session: Codable {
        var id: UUID; var startedAt: Date; var finishedAt: Date?; var dayName: String
        var splitWeekday: Int; var notes: String; var sets: [Set_]
    }
    struct Set_: Codable {
        var exerciseId: String; var setIndex: Int; var weightKg: Double; var reps: Int; var seconds: Int; var completedAt: Date
    }
    struct Metric: Codable { var date: Date; var weightKg: Double; var bodyFatPercent: Double?; var source: String }
    struct Food: Codable {
        var date: Date; var meal: String; var name: String; var foodId: String?; var grams: Double
        var kcal: Double; var protein: Double; var carbs: Double; var fat: Double
    }
    struct Custom: Codable {
        var id: String; var name: String; var aliases: [String]
        var kcal: Double; var protein: Double; var carbs: Double; var fat: Double
    }
    struct Portion: Codable { var foodId: String; var unit: String; var grams: Double }
    struct Supplement: Codable { var dayKey: String; var supplementId: String; var takenAt: Date }
    struct Exercise: Codable {
        var id: String; var name: String; var logType: String; var equipment: String
        var primary: [String]; var secondary: [String]
    }

    private static let settingKeys = [ProfileKey.heightCm, ProfileKey.kcalTarget, ProfileKey.proteinTarget,
                                      ProfileKey.carbsTarget, ProfileKey.fatTarget, ProfileKey.restSeconds]

    static func export(context: ModelContext) throws -> URL {
        let defaults = UserDefaults.standard
        var settings: [String: Double] = [:]
        for k in settingKeys where defaults.object(forKey: k) != nil { settings[k] = defaults.double(forKey: k) }

        let backup = Backup(
            version: currentVersion,
            exportedAt: .now,
            settings: settings,
            sessions: try context.fetch(FetchDescriptor<WorkoutSession>()).map { s in
                Session(id: s.id, startedAt: s.startedAt, finishedAt: s.finishedAt, dayName: s.dayName,
                        splitWeekday: s.splitWeekday, notes: s.notes,
                        sets: s.sets.map { Set_(exerciseId: $0.exerciseId, setIndex: $0.setIndex, weightKg: $0.weightKg,
                                                reps: $0.reps, seconds: $0.seconds, completedAt: $0.completedAt) })
            },
            bodyMetrics: try context.fetch(FetchDescriptor<BodyMetric>()).map {
                Metric(date: $0.date, weightKg: $0.weightKg, bodyFatPercent: $0.bodyFatPercent, source: $0.source)
            },
            food: try context.fetch(FetchDescriptor<FoodEntry>()).map {
                Food(date: $0.date, meal: $0.meal, name: $0.name, foodId: $0.foodId, grams: $0.grams,
                     kcal: $0.kcal, protein: $0.protein, carbs: $0.carbs, fat: $0.fat)
            },
            customFoods: try context.fetch(FetchDescriptor<CustomFood>()).map {
                Custom(id: $0.id, name: $0.name, aliases: $0.aliases, kcal: $0.kcalPer100g,
                       protein: $0.proteinPer100g, carbs: $0.carbsPer100g, fat: $0.fatPer100g)
            },
            learnedPortions: try context.fetch(FetchDescriptor<LearnedPortion>()).map {
                Portion(foodId: $0.foodId, unit: $0.unit, grams: $0.grams)
            },
            supplements: try context.fetch(FetchDescriptor<SupplementCheck>()).map {
                Supplement(dayKey: $0.dayKey, supplementId: $0.supplementId, takenAt: $0.takenAt)
            },
            customExercises: try context.fetch(FetchDescriptor<CustomExercise>()).map {
                Exercise(id: $0.id, name: $0.name, logType: $0.logType, equipment: $0.equipment,
                         primary: $0.primary, secondary: $0.secondary)
            }
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(backup)
        let name = "IronLog-backup-\(Date.now.dayKey).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: lastBackupKey)
        return url
    }

    static let lastBackupKey = "backup.last"

    static func read(_ url: URL) throws -> Backup {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Backup.self, from: Data(contentsOf: url))
    }

    /// Replaces everything in the app with the backup's contents.
    static func restore(_ b: Backup, context: ModelContext) throws {
        try context.delete(model: SetLog.self)
        try context.delete(model: WorkoutSession.self)
        try context.delete(model: BodyMetric.self)
        try context.delete(model: FoodEntry.self)
        try context.delete(model: CustomFood.self)
        try context.delete(model: LearnedPortion.self)
        try context.delete(model: SupplementCheck.self)
        try context.delete(model: CustomExercise.self)

        for s in b.sessions {
            let session = WorkoutSession(dayName: s.dayName, splitWeekday: s.splitWeekday, startedAt: s.startedAt)
            session.id = s.id
            session.finishedAt = s.finishedAt
            session.notes = s.notes
            context.insert(session)
            for x in s.sets {
                let log = SetLog(exerciseId: x.exerciseId, setIndex: x.setIndex, weightKg: x.weightKg, reps: x.reps,
                                 seconds: x.seconds, completedAt: x.completedAt)
                context.insert(log)
                log.session = session
            }
        }
        for m in b.bodyMetrics {
            context.insert(BodyMetric(date: m.date, weightKg: m.weightKg, bodyFatPercent: m.bodyFatPercent, source: m.source))
        }
        for f in b.food {
            context.insert(FoodEntry(date: f.date, meal: f.meal, name: f.name, foodId: f.foodId, grams: f.grams,
                                     kcal: f.kcal, protein: f.protein, carbs: f.carbs, fat: f.fat))
        }
        for c in b.customFoods {
            context.insert(CustomFood(id: c.id, name: c.name, aliases: c.aliases, kcalPer100g: c.kcal,
                                      proteinPer100g: c.protein, carbsPer100g: c.carbs, fatPer100g: c.fat))
        }
        for p in b.learnedPortions { context.insert(LearnedPortion(foodId: p.foodId, unit: p.unit, grams: p.grams)) }
        for s in b.supplements { context.insert(SupplementCheck(dayKey: s.dayKey, supplementId: s.supplementId, takenAt: s.takenAt)) }
        var customDefs: [ExerciseDef] = []
        for e in b.customExercises ?? [] {
            let c = CustomExercise(id: e.id, name: e.name, logType: e.logType, equipment: e.equipment,
                                   primary: e.primary, secondary: e.secondary)
            context.insert(c)
            customDefs.append(c.definition)
        }
        Catalog.shared.register(custom: customDefs)
        for (k, v) in b.settings {
            if k == ProfileKey.restSeconds { UserDefaults.standard.set(Int(v), forKey: k) } else { UserDefaults.standard.set(v, forKey: k) }
        }
        UserDefaults.standard.set(true, forKey: ProfileKey.didSeed)
        try context.save()
    }

    /// Sunday 8 PM reminder to export a backup.
    static func setWeeklyReminder(_ on: Bool) {
        let id = "backup-weekly"
        if on {
            let content = (title: "BACK UP IRON LOG", body: "Export your data to Files or iCloud Drive (Settings → Backup).")
            NotificationManager.shared.scheduleWeekly(id: id, title: content.title, body: content.body, weekday: 1, hour: 20, minute: 0)
        } else {
            NotificationManager.shared.cancel(id: id)
        }
    }
}
