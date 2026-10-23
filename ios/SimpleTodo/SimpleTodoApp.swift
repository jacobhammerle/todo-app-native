import SwiftUI

/// The three tabs. `TasksView` switches to `.done` from its "See all" row.
enum AppTab: Hashable {
    case tasks, done, admin
}

@main
struct SimpleTodoApp: App {
    @State private var store = TodoStore()
    @State private var tab: AppTab = .tasks

    var body: some Scene {
        WindowGroup {
            RootTabs(tab: $tab)
                .environment(store)
                .tint(Brand.tint)
        }
    }
}

struct RootTabs: View {
    @Binding var tab: AppTab

    var body: some View {
        TabView(selection: $tab) {
            TasksView(selectedTab: $tab)
                .tabItem { Label("Tasks", systemImage: "checklist") }
                .tag(AppTab.tasks)
            DoneView()
                .tabItem { Label("Done", systemImage: "checkmark.circle.fill") }
                .tag(AppTab.done)
            AdminView()
                .tabItem { Label("Admin", systemImage: "gearshape.fill") }
                .tag(AppTab.admin)
        }
    }
}
