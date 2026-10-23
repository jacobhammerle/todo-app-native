import Foundation
import Observation

/// The task store: an in-memory list. There is no backend on purpose; the
/// repo is about the EAS workflows around the app. Launch data comes from
/// `Seed.swift`.
@Observable
final class TodoStore {
    /// How many completed tasks the Tasks screen shows before linking to Done.
    static let recentDoneLimit = 3

    private(set) var todos: [Todo]
    /// The seed preset most recently loaded (at launch or by `reset`).
    private(set) var loadedPreset: SeedPreset
    private var nextId = 0

    init(preset: SeedPreset = .active) {
        todos = buildSeedTodos(preset)
        loadedPreset = preset
    }

    var active: [Todo] { todos.filter { !$0.done } }

    /// Newest first, so the Tasks screen can show the most recent ones.
    var completed: [Todo] {
        todos.filter(\.done).sorted {
            ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast)
        }
    }

    var recentlyDone: [Todo] { Array(completed.prefix(Self.recentDoneLimit)) }
    var total: Int { todos.count }

    var percent: Int {
        total == 0 ? 0 : Int((Double(completed.count) / Double(total) * 100).rounded())
    }

    func add(_ input: NewTodo) {
        let title = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let notes = input.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        // Time plus a counter, so two adds in one millisecond stay distinct.
        let id = "\(Int(Date().timeIntervalSince1970 * 1000))-\(nextId)"
        nextId += 1
        todos.insert(
            Todo(
                id: id,
                title: title,
                done: false,
                notes: (notes?.isEmpty ?? true) ? nil : notes,
                priority: input.priority,
                dueAt: input.dueAt
            ),
            at: 0
        )
    }

    /// Checks or unchecks a task. Both screens call this.
    func toggle(id: String, done: Bool) {
        guard let index = todos.firstIndex(where: { $0.id == id }), todos[index].done != done else {
            return
        }
        todos[index].done = done
        todos[index].completedAt = done ? Date() : nil
    }

    /// Removes a single task for good.
    func delete(id: String) {
        todos.removeAll { $0.id == id }
    }

    /// Removes every completed task for good.
    func clearCompleted() {
        todos.removeAll(where: \.done)
    }

    /// Replaces every task with a seed preset. See `Seed.swift`.
    func reset(to preset: SeedPreset) {
        loadedPreset = preset
        todos = buildSeedTodos(preset)
    }
}
