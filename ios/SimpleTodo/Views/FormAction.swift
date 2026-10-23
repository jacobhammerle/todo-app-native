import SwiftUI

/// A full-width action row inside a Form, styled like a native button.
struct FormAction: View {
    let label: String
    var destructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .fontWeight(.semibold)
                .foregroundStyle(destructive ? Brand.danger : Brand.tint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
