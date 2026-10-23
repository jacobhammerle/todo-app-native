import SwiftUI

/// A task row. Tapping the row toggles the task. `onDelete`, when provided,
/// adds a swipe-to-delete action.
struct TaskRow: View {
    let todo: Todo
    var showDate = false
    let onToggle: (String, Bool) -> Void
    var onDelete: ((String) -> Void)? = nil

    var body: some View {
        Button {
            onToggle(todo.id, !todo.done)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: todo.done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(todo.done ? Brand.tint : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(todo.title)
                        .foregroundStyle(todo.done ? .secondary : .primary)
                    if let details = todo.details {
                        Text(details)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if showDate, let completedAt = todo.completedAt {
                    Text(formatDay(completedAt))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(todo.title)
        .accessibilityValue(todo.done ? "Done" : "To do")
        .accessibilityHint(todo.done ? "Moves the task back to To do" : "Marks the task done")
        .accessibilityIdentifier("task-\(todo.id)")
        .swipeActions(edge: .trailing) {
            if let onDelete {
                Button(role: .destructive) {
                    onDelete(todo.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}
