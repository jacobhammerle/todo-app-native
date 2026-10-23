import SwiftUI

struct DoneView: View {
    @Environment(TodoStore.self) private var store
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if store.completed.isEmpty {
                        Text("Nothing completed yet.")
                    } else {
                        ForEach(store.completed) { todo in
                            TaskRow(todo: todo, showDate: true, onToggle: store.toggle(id:done:))
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
        }
    }
}
