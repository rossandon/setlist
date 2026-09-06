import SwiftUI

/// Asks for the song's name before creating anything.
///
/// Cancelling leaves the library untouched, which is the point: the previous
/// behaviour dropped an "Untitled" row in the list on every stray keypress.
struct NewSongSheet: View {
    @Binding var title: String
    @Binding var artist: String
    @Binding var confirmed: Bool

    @Environment(\.dismiss) private var dismiss
    @FocusState private var titleFocused: Bool

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Song")
                .font(.headline)

            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($titleFocused)
                .onSubmit(submit)

            TextField("Artist (optional)", text: $artist)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)

            Text("Return searches GetSongBPM for the tempo and key.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedTitle.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { titleFocused = true }
    }

    /// Safe to call twice: Return can fire both onSubmit and the default
    /// button. The values are consumed once, on dismissal.
    private func submit() {
        guard !trimmedTitle.isEmpty else { return }
        confirmed = true
        dismiss()
    }
}
