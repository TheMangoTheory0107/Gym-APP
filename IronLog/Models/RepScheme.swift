import Foundation

/// Target for one set: a single number ("20") or a range ("8-10").
struct RepTarget: Hashable {
    let low: Int
    let high: Int

    var text: String { low == high ? "\(low)" : "\(low)–\(high)" }
    /// Middle of the range, used as the default value in steppers.
    var suggested: Int { high }
}

/// Parses the `scheme` strings from split.json.
///
/// Supported formats:
/// - `"3x8-12"`             → 3 sets of 8–12
/// - `"20,15,15,15"`        → 4 sets with their own targets
/// - `"20,15,8-10,8-10,8-10"` → mixed
/// The unit (reps, seconds, minutes, steps) comes from the exercise's `logType`.
struct RepScheme: Hashable {
    let sets: [RepTarget]

    init(_ raw: String) {
        let s = raw.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "×", with: "x")
            .replacingOccurrences(of: "–", with: "-")

        if let x = s.firstIndex(of: "x"), let count = Int(s[s.startIndex..<x]),
           let target = RepScheme.parseTarget(String(s[s.index(after: x)...])) {
            sets = Array(repeating: target, count: max(count, 1))
        } else {
            sets = s.split(separator: ",").compactMap { RepScheme.parseTarget(String($0)) }
        }
    }

    private static func parseTarget(_ text: String) -> RepTarget? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        switch parts.count {
        case 1: return RepTarget(low: parts[0], high: parts[0])
        case 2: return RepTarget(low: min(parts[0], parts[1]), high: max(parts[0], parts[1]))
        default: return nil
        }
    }

    var setCount: Int { sets.count }

    /// Human readable summary, e.g. "3 × 8–12 reps" or "20 / 15 / 15 / 15 reps" or "3 × 2 min".
    func summary(for exercise: ExerciseDef) -> String {
        guard let first = sets.first else { return "" }
        let unit = exercise.unitLabel
        if exercise.logType == .seconds, sets.allSatisfy({ $0 == first }), first.low == first.high, first.low % 60 == 0 {
            return "\(sets.count) × \(first.low / 60) min"
        }
        if sets.allSatisfy({ $0 == first }) {
            return sets.count == 1 ? "\(first.text) \(unit)" : "\(sets.count) × \(first.text) \(unit)"
        }
        return sets.map(\.text).joined(separator: " / ") + " \(unit)"
    }
}
