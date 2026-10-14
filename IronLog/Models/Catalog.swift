import Foundation

// Reference data loaded from the JSON files in Resources/Data.
// Edit those files to change exercises, muscles or your split; no Swift changes needed.

enum LogType: String, Codable {
    /// Weight (kg) + reps per set
    case weightReps
    /// Reps only (bodyweight moves, free squats, lunges)
    case reps
    /// Seconds held (plank)
    case seconds
    /// Minutes (cardio)
    case minutes
}

struct ExerciseDef: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let logType: LogType
    /// Overrides the unit shown for reps, e.g. "steps" or "reps each side".
    let repUnit: String?
    let equipment: String
    /// Muscle ids from muscles.json
    let primary: [String]
    let secondary: [String]
    /// Weight step for the +/- buttons, in kg.
    let weightStep: Double?
    /// Folder name in the free-exercise-db dataset, used for form images.
    let imageId: String?
    let cues: [String]?
    let mistakes: [String]?
    /// From the exercise library: "strength", "stretching", "cardio", "plyometrics", ...
    let category: String?
    /// "beginner", "intermediate", "expert"
    let level: String?
    /// "split" (your routine), "library" (free-exercise-db) or "custom" (added by you)
    let source: String?
    /// Step-by-step instructions (library exercises)
    let instructions: [String]?

    init(id: String, name: String, logType: LogType, repUnit: String? = nil, equipment: String,
         primary: [String], secondary: [String], weightStep: Double? = nil, imageId: String? = nil,
         cues: [String]? = nil, mistakes: [String]? = nil, category: String? = nil, level: String? = nil,
         source: String? = nil, instructions: [String]? = nil) {
        self.id = id; self.name = name; self.logType = logType; self.repUnit = repUnit
        self.equipment = equipment; self.primary = primary; self.secondary = secondary
        self.weightStep = weightStep; self.imageId = imageId; self.cues = cues; self.mistakes = mistakes
        self.category = category; self.level = level; self.source = source; self.instructions = instructions
    }

    var isCustom: Bool { source == "custom" }

    var unitLabel: String {
        switch logType {
        case .weightReps, .reps: return repUnit ?? "reps"
        case .seconds: return "sec"
        case .minutes: return "min"
        }
    }

    var youtubeSearchURL: URL? {
        var c = URLComponents(string: "https://www.youtube.com/results")
        c?.queryItems = [URLQueryItem(name: "search_query", value: "\(name) proper form")]
        return c?.url
    }
}

struct MuscleDef: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    /// Group used for weekly volume, e.g. "Chest", "Back", "Legs".
    let group: String
}

struct SplitItem: Codable, Hashable {
    let exercise: String
    let scheme: String
    let note: String?
}

struct SplitDay: Codable, Identifiable, Hashable {
    /// Weekday name, e.g. "Monday"
    let day: String
    let name: String
    let items: [SplitItem]

    var id: String { day }
    var isRest: Bool { items.isEmpty }
}

private struct ExerciseFile: Codable { let exercises: [ExerciseDef] }
private struct MuscleFile: Codable { let muscles: [MuscleDef] }
private struct SplitFile: Codable { let days: [SplitDay] }

/// Loads and holds the bundled reference data. If a JSON file has a typo,
/// `loadErrors` explains which file and why instead of crashing.
final class Catalog {
    static let shared = Catalog()

    static let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    private(set) var exercises: [ExerciseDef]
    let muscles: [MuscleDef]
    let split: [SplitDay]
    private(set) var loadErrors: [String] = []

    private var exerciseById: [String: ExerciseDef]
    private let muscleById: [String: MuscleDef]

    private init() {
        var errors: [String] = []
        exercises = Catalog.load(ExerciseFile.self, "exercises", errors: &errors)?.exercises ?? []
        muscles = Catalog.load(MuscleFile.self, "muscles", errors: &errors)?.muscles ?? []
        split = Catalog.load(SplitFile.self, "split", errors: &errors)?.days ?? []
        exerciseById = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        muscleById = Dictionary(muscles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // Catch references to exercises or muscles that don't exist.
        for day in split {
            for item in day.items where exerciseById[item.exercise] == nil {
                errors.append("split.json: \(day.day) uses unknown exercise \"\(item.exercise)\"")
            }
        }
        for ex in exercises {
            for m in ex.primary + ex.secondary where muscleById[m] == nil {
                errors.append("exercises.json: \(ex.id) uses unknown muscle \"\(m)\"")
            }
        }
        loadErrors = errors
    }

    func exercise(_ id: String) -> ExerciseDef? { exerciseById[id] }

    /// Ids of exercises used anywhere in your split.
    var splitExerciseIds: Set<String> { Set(split.flatMap { $0.items.map(\.exercise) }) }

    /// Adds (or refreshes) exercises you created yourself. Call on the main thread.
    func register(custom: [ExerciseDef]) {
        exercises.removeAll { $0.isCustom }
        exercises.append(contentsOf: custom)
        for ex in custom { exerciseById[ex.id] = ex }
    }
    func muscle(_ id: String) -> MuscleDef? { muscleById[id] }

    /// Split day for a calendar weekday (1 = Sunday … 7 = Saturday).
    func splitDay(weekday: Int) -> SplitDay? {
        guard (1...7).contains(weekday) else { return nil }
        let name = Catalog.weekdayNames[weekday - 1].lowercased()
        return split.first { $0.day.lowercased() == name }
    }

    func muscleNames(_ ids: [String]) -> [String] {
        ids.compactMap { muscleById[$0]?.name }
    }

    private static func load<T: Decodable>(_ type: T.Type, _ name: String, errors: inout [String]) -> T? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            errors.append("\(name).json is missing from the app bundle")
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(T.self, from: data)
        } catch let DecodingError.dataCorrupted(context) {
            errors.append("\(name).json is not valid JSON: \(context.debugDescription)")
        } catch let DecodingError.keyNotFound(key, context) {
            errors.append("\(name).json: missing \"\(key.stringValue)\" at \(context.codingPath.map(\.stringValue).joined(separator: "."))")
        } catch let DecodingError.typeMismatch(_, context) {
            errors.append("\(name).json: wrong type at \(context.codingPath.map(\.stringValue).joined(separator: ".")): \(context.debugDescription)")
        } catch {
            errors.append("\(name).json: \(error.localizedDescription)")
        }
        return nil
    }
}
