import SwiftUI
import SSH2Kit

struct SnippetEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var snippet: Snippet
    var onSave: (Snippet) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(snippet.title.isEmpty ? String(localized: "New Snippet") : String(localized: "Edit Snippet"))
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "Name"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(String(localized: "e.g. Check Docker Containers"), text: $snippet.title)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "Command"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                TextEditor(text: $snippet.command)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 90, maxHeight: 160)
                    .padding(4)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "Category"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(String(localized: "e.g. Docker / System / Network"), text: $snippet.category)
                    .textFieldStyle(.roundedBorder)
            }

            Toggle(String(localized: "Auto-execute on click (press Enter)"), isOn: $snippet.autoExecute)
                .font(.subheadline)

            HStack {
                Button(String(localized: "Cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Button(String(localized: "Save")) {
                    onSave(snippet)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(snippet.title.trimmingCharacters(in: .whitespaces).isEmpty || snippet.command.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 8)
        }
        .padding(20)
        .frame(width: 420)
    }
}
