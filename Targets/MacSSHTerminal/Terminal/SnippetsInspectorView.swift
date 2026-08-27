import SwiftUI
import SSH2Kit

@MainActor
struct SnippetsInspectorView: View {
    @Bindable var appModel: AppModel
    var onExecute: (Snippet, Bool) -> Void
    @State private var searchText: String = ""
    @State private var editingSnippet: Snippet?
    @State private var hoveringSnippetID: UUID?

    private var filteredSnippets: [Snippet] {
        if searchText.isEmpty { return appModel.snippets }
        return appModel.snippets.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.command.localizedCaseInsensitiveContains(searchText) ||
            $0.category.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header: Search field + Add Snippet Button
            HStack(spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    TextField(String(localized: "Search snippets"), text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4.5)
                .background(
                    Capsule()
                        .fill(Color.primary.opacity(0.05))
                )

                // Plus (+) Button
                Button {
                    editingSnippet = Snippet(title: "", command: "", autoExecute: true)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.primary.opacity(0.05)))
                        .contentShape(Circle())
                }
                .buttonStyle(PressableIconStyle())
                .foregroundStyle(.secondary)
                .help(String(localized: "New Snippet"))
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 8)

            Divider()
                .opacity(0.3)

            // Snippets List
            if filteredSnippets.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "curlybraces")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text(searchText.isEmpty ? String(localized: "No Snippets") : String(localized: "没有匹配的代码片段"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredSnippets) { snippet in
                            snippetCard(for: snippet)
                        }
                    }
                    .padding(10)
                }
            }
        }
        .sheet(item: $editingSnippet) { snippet in
            SnippetEditorSheet(snippet: snippet) { saved in
                appModel.upsertSnippet(saved)
            }
        }
    }

    private func snippetCard(for snippet: Snippet) -> some View {
        let isHovered = hoveringSnippetID == snippet.id

        return HStack(spacing: 8) {
            // Amber vertical status indicator
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.orange.opacity(0.8))
                .frame(width: 3, height: 26)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(snippet.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)

                    if !snippet.category.isEmpty {
                        Text(snippet.category)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(Capsule())
                    }
                }

                Text(snippet.command.replacingOccurrences(of: "\n", with: " ↵ "))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 4)

            if isHovered {
                HStack(spacing: 4) {
                    Button {
                        onExecute(snippet, true)
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.green)
                            .padding(4)
                            .background(Circle().fill(Color.green.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Run in Terminal"))

                    Button {
                        copyToPasteboard(snippet.command)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Copy Command"))
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor).opacity(isHovered ? 0.9 : 0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(isHovered ? 0.12 : 0.05), lineWidth: 0.8)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onHover { hovering in
            hoveringSnippetID = hovering ? snippet.id : nil
        }
        .onTapGesture {
            onExecute(snippet, snippet.autoExecute)
        }
        .contextMenu {
            Button {
                onExecute(snippet, true)
            } label: {
                Label(String(localized: "Run in Terminal"), systemImage: "play.fill")
            }

            Button {
                onExecute(snippet, false)
            } label: {
                Label(String(localized: "Insert into Terminal"), systemImage: "arrow.right.doc.on.clipboard")
            }

            Button {
                copyToPasteboard(snippet.command)
            } label: {
                Label(String(localized: "Copy Command"), systemImage: "doc.on.doc")
            }

            Divider()

            Button {
                editingSnippet = snippet
            } label: {
                Label(String(localized: "Edit"), systemImage: "pencil")
            }

            Button(role: .destructive) {
                appModel.removeSnippet(snippet.id)
            } label: {
                Label(String(localized: "Delete"), systemImage: "trash")
            }
        }
    }

    private func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
