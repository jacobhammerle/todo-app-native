import Foundation

enum Priority: String, CaseIterable, Identifiable {
    case low, medium, high

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

struct Todo: Identifiable, Equatable {
    let id: String
    var title: String
    var done: Bool
    var notes: String?
    var priority: Priority
    var dueAt: Date?
    /// When the task was checked.
    var completedAt: Date?

    /// The one-line summary under a title: due date, priority, notes.
    var details: String? {
        let parts: [String?] = [
            dueAt.map { "Due \(formatDay($0))" },
            priority == .high ? "High priority" : nil,
            priority == .low ? "Low priority" : nil,
            notes,
        ]
        let text = parts.compactMap { $0 }.joined(separator: " · ")
        return text.isEmpty ? nil : text
    }
}

struct NewTodo {
    var title: String
    var notes: String? = nil
    var priority: Priority = .medium
    var dueAt: Date? = nil
}
