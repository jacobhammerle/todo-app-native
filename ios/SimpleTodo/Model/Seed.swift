import Foundation

/// Demo seed data.
///
/// This is the only file to edit to change what the app shows on launch.
/// Each preset is a plain list of tasks. Times are relative to "now", so the
/// demo looks fresh on any day:
///
///   SeedTask("Buy groceries")                              an open task
///   SeedTask("Pay the rent", doneAgo: .hours(1))           done one hour ago
///   SeedTask("File taxes", dueIn: .days(3), priority: .high, notes: "…")
///
/// Pick which preset loads at launch with `SeedPreset.active`, or switch
/// presets live from the Admin tab ("Demo data" section).

enum Duration {
    case minutes(Double), hours(Double), days(Double), weeks(Double)

    var seconds: TimeInterval {
        switch self {
        case .minutes(let n): return n * 60
        case .hours(let n): return n * 3_600
        case .days(let n): return n * 86_400
        case .weeks(let n): return n * 604_800
        }
    }
}

struct SeedTask {
    let title: String
    /// How long ago the task was completed. Nil for an open task.
    var doneAgo: Duration? = nil
    /// When the task is due, relative to now. Negative values are overdue.
    var dueIn: Duration? = nil
    var priority: Priority = .medium
    var notes: String? = nil

    init(
        _ title: String,
        doneAgo: Duration? = nil,
        dueIn: Duration? = nil,
        priority: Priority = .medium,
        notes: String? = nil
    ) {
        self.title = title
        self.doneAgo = doneAgo
        self.dueIn = dueIn
        self.priority = priority
        self.notes = notes
    }
}

enum SeedPreset: String, CaseIterable, Identifiable {
    /// The everyday demo: a few open tasks and a short history.
    case `default`
    /// A fresh start: nothing done yet.
    case fresh
    /// Everything checked off: shows the "All caught up" state.
    case allDone
    /// No tasks at all: shows the empty states.
    case empty

    /// The preset the app loads at launch.
    static let active: SeedPreset = .default

    var id: String { rawValue }

    var label: String {
        switch self {
        case .default: return "Default"
        case .fresh: return "Fresh start"
        case .allDone: return "All done"
        case .empty: return "Empty"
        }
    }

    var tasks: [SeedTask] {
        switch self {
        case .default:
            return [
                SeedTask("Buy groceries", dueIn: .days(1), priority: .high),
                SeedTask("Call the dentist", notes: "Ask about the Thursday slot"),
                SeedTask("Water the plants"),
                SeedTask("Pay the rent", doneAgo: .hours(1)),
                SeedTask("Book an oil change", doneAgo: .days(1)),
                SeedTask("Return library books", doneAgo: .days(3)),
                SeedTask("Copy spare keys", doneAgo: .days(5)),
            ]
        case .fresh:
            return [
                SeedTask("Buy groceries"),
                SeedTask("Call the dentist"),
                SeedTask("Water the plants"),
            ]
        case .allDone:
            return [
                SeedTask("Buy groceries", doneAgo: .minutes(10)),
                SeedTask("Call the dentist", doneAgo: .hours(2)),
                SeedTask("Water the plants", doneAgo: .days(1)),
            ]
        case .empty:
            return []
        }
    }
}

private func slug(_ title: String) -> String {
    let lowered = title.lowercased()
    var out = ""
    var lastDash = false
    for scalar in lowered.unicodeScalars {
        if CharacterSet.alphanumerics.contains(scalar), scalar.isASCII {
            out.unicodeScalars.append(scalar)
            lastDash = false
        } else if !lastDash {
            out.append("-")
            lastDash = true
        }
    }
    return out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
}

/// Turns a preset into todos with stable ids and absolute dates.
func buildSeedTodos(_ preset: SeedPreset = .active, now: Date = Date()) -> [Todo] {
    var seen: [String: Int] = [:]
    return preset.tasks.map { task in
        let base = slug(task.title).isEmpty ? "task" : slug(task.title)
        let count = (seen[base] ?? 0) + 1
        seen[base] = count
        let completedAt = task.doneAgo.map { now.addingTimeInterval(-$0.seconds) }
        return Todo(
            id: count == 1 ? base : "\(base)-\(count)",
            title: task.title,
            done: completedAt != nil,
            notes: task.notes,
            priority: task.priority,
            dueAt: task.dueIn.map { now.addingTimeInterval($0.seconds) },
            completedAt: completedAt
        )
    }
}
