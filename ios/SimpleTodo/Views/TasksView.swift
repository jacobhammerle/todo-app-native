import SwiftUI

struct TasksView: View {
    @Environment(TodoStore.self) private var store
    @Binding var selectedTab: AppTab
    @State private var title = ""
    @State private var sheetOpen = false
    @FocusState private var titleFocused: Bool

    private let installation = Installation.current

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    summaryRow
                }

                Section("Add a task") {
                    TextField("What needs doing?", text: $title)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.done)
                        .focused($titleFocused)
                        .onSubmit(submit)
                        .accessibilityIdentifier("task-title-input")
                    FormAction(label: "Add task", action: submit)
                        .accessibilityIdentifier("add-task")
                    FormAction(label: "Add with details…") { sheetOpen = true }
                        .accessibilityIdentifier("add-with-details")
                }

                Section {
                    if store.active.isEmpty {
                        Text("Nothing left to do.")
                    } else {
                        ForEach(store.active) { todo in
                            TaskRow(
                                todo: todo,
                                onToggle: store.toggle(id:done:),
                                onDelete: store.delete(id:)
                            )
                        }
                    }
                } header: {
                    Text("To do")
                } footer: {
                    if store.completed.isEmpty {
                        summaryFooter
                    }
                }

                if !store.completed.isEmpty {
                    Section {
                        ForEach(store.recentlyDone) { todo in
                            TaskRow(todo: todo, onToggle: store.toggle(id:done:))
                        }
                        FormAction(label: "See all \(store.completed.count) in Done →") {
                            selectedTab = .done
                        }
                        .accessibilityIdentifier("see-all-done")
                    } header: {
                        Text("Recently done")
                    } footer: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Tap a done task to move it back to To do.")
                            summaryFooter
                        }
                    }
                }
            }
            .navigationTitle("Tasks")
            .sheet(isPresented: $sheetOpen) {
                NewTaskSheet { input in
                    store.add(input)
                    sheetOpen = false
                }
            }
        }
    }

    private var headline: String {
        let open = store.active.count
        return open == 0 ? "All caught up" : "\(open) \(taskWord(open)) to do"
    }

    private var summaryRow: some View {
        let done = store.completed.count
        let fraction = store.total == 0 ? 0 : Double(done) / Double(store.total)
        return HStack(spacing: 14) {
            Gauge(value: fraction) { EmptyView() }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(Brand.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.headline)
                Text("\(done) of \(store.total) \(taskWord(store.total)) done")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(store.percent)%")
                .font(.title2.weight(.bold))
                .foregroundStyle(Brand.tint)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("progress-summary")
    }

    /// One line of build facts at the bottom of the list, so a screenshot
    /// shows which build produced it.
    private var summaryFooter: some View {
        Text(installation.summaryLine)
            .font(.caption.monospaced())
            .accessibilityIdentifier("installation-summary")
    }

    private func submit() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.add(NewTodo(title: trimmed))
        title = ""
        titleFocused = false
    }
}
