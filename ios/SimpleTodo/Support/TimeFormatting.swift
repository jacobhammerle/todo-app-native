import Foundation

/// "Today", "Yesterday", "Tomorrow", or a short date such as "Oct 14".
func formatDay(_ date: Date, now: Date = Date()) -> String {
    let calendar = Calendar.current
    let start = calendar.startOfDay(for: date)
    let today = calendar.startOfDay(for: now)
    let days = calendar.dateComponents([.day], from: start, to: today).day ?? 0
    switch days {
    case 0: return "Today"
    case 1: return "Yesterday"
    case -1: return "Tomorrow"
    default: return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

/// "task" or "tasks".
func taskWord(_ count: Int) -> String {
    count == 1 ? "task" : "tasks"
}
