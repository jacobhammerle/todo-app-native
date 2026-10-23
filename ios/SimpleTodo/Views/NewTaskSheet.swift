import SwiftUI

private func tomorrowAtNine() -> Date {
    let calendar = Calendar.current
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
}

/// Sheet for adding a task with notes, a priority, and a due date.
struct NewTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (NewTodo) -> Void

    @State private var title = ""
    @State private var notes = ""
    @State private var priority: Priority = .medium
    @State private var hasDue = false
    @State private var due = tomorrowAtNine()

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .textInputAutocapitalization(.sentences)
                        .accessibilityIdentifier("new-task-title")
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityIdentifier("new-task-notes")
                }

                Section {
                    Picker("Priority", selection: $priority) {
                        ForEach(Priority.allCases) { priority in
                            Text(priority.label).tag(priority)
                        }
                    }
                    .accessibilityIdentifier("new-task-priority")
                    Toggle("Due date", isOn: $hasDue)
                        .accessibilityIdentifier("new-task-has-due")
                    if hasDue {
                        DatePicker(
                            "Due",
                            selection: $due,
                            in: Date()...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                } header: {
                    Text("Details")
                } footer: {
                    Text("Notes, priority, and the due date show under the task in the list.")
                }
            }
            .navigationTitle("New task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("new-task-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { add() }
                        .disabled(trimmedTitle.isEmpty)
                        .accessibilityIdentifier("new-task-add")
                }
            }
        }
    }

    private func add() {
        guard !trimmedTitle.isEmpty else { return }
        onAdd(
            NewTodo(
                title: trimmedTitle,
                notes: notes,
                priority: priority,
                dueAt: hasDue ? due : nil
            )
        )
    }
}
