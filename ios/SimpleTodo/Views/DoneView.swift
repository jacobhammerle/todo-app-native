import SwiftUI

struct DoneView: View {
    @Environment(TodoStore.self) private var store
    @State private var confirmClear = false
    @State private var taskToRestore: Todo?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if store.completed.isEmpty {
                        Text("Nothing completed yet.")
                    } else {
                        ForEach(store.completed) { todo in
                            TaskRow(todo: todo, showDate: true, onToggle: { id, done in
                                taskToRestore = todo
                            })
                        }
                    }
                } header: {
                    Text("Completed")
                } footer: {
                    Text("Every task you check appears here, newest first. Uncheck one to move it back to To do.")
                }

                if !store.completed.isEmpty {
                    Section {
                        FormAction(label: "Clear history", destructive: true) {
                            confirmClear = true
                        }
                        .accessibilityIdentifier("clear-history")
                    } footer: {
                        Text("Clearing history removes completed tasks for good.")
                    }
                }
            }
            .navigationTitle("Done")
            .alert("Clear history?", isPresented: $confirmClear) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) { store.clearCompleted() }
            } message: {
                let count = store.completed.count
                Text("This removes \(count) completed \(taskWord(count)) for good.")
            }
            .alert("Move back to To do?", isPresented: Binding(
                get: { taskToRestore != nil },
                set: { if !$0 { taskToRestore = nil } }
            )) {
                Button("Cancel", role: .cancel) {}
                Button("Move") {
                    if let todo = taskToRestore {
                        store.toggle(id: todo.id, done: false)
                    }
                }
            } message: {
                if let todo = taskToRestore {
                    Text("\"\(todo.title)\" moves back to To do.")
                }
            }
        }
    }
}
