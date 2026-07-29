import SwiftUI

/// An always-visible search field pinned above the list.
///
/// Deliberately not `.searchable`: that renders into the window toolbar, which in a
/// narrow single-column window competes with the toolbar buttons for space and can be
/// collapsed away entirely.
struct SearchField: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search accounts", text: $text)
                .textFieldStyle(.plain)
                .focused(isFocused)
                .onSubmit { isFocused.wrappedValue = false }

            if !text.isEmpty {
                Button {
                    text = ""
                    isFocused.wrappedValue = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.secondary.opacity(isFocused.wrappedValue ? 0.6 : 0.25))
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
