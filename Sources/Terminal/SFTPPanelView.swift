import SwiftUI
import AppKit
import libssh2_swift

struct SFTPPanelView: View {
    @Bindable var model: SFTPViewModel
    @State private var selection: Set<SFTPItem.ID> = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                HStack {
                    Button { model.goUp() } label: {
                        Image(systemName: "chevron.left.2")
                    }
                    .disabled(model.currentPath == ".")
                    .buttonStyle(.plain)
                    .foregroundStyle(model.currentPath == "." ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.accentColor))
                    
                    Spacer()
                    
                    let displayPath = model.currentPath == "." ? String(localized: "Home") : model.currentPath
                    Text(displayPath)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                    
                    Spacer()
                    
                    Button { model.refresh() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 4)
                
                HStack(spacing: 8) {
                    Button { download(selectedItems) } label: {
                        Label(String(localized: "Download"), systemImage: "arrow.down.circle")
                    }
                    .disabled(selectedItems.isEmpty)
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button { upload() } label: {
                        Label(String(localized: "Upload"), systemImage: "arrow.up.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    if case .loading = model.status {
                        ProgressView().controlSize(.small)
                            .transition(.opacity)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            
            Divider()

            List(selection: $selection) {
                ForEach(model.items) { item in
                    HStack(spacing: 10) {
                        Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                            .foregroundStyle(item.isDirectory ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                            .imageScale(.large)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.system(size: 13, weight: .regular))
                            
                            if !item.isDirectory {
                                if let size = item.size {
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        if item.isDirectory {
                            model.changeDirectory(item)
                        } else {
                            download([item])
                        }
                    }
                }
            }
            .listStyle(.inset)
            
            ZStack {
                if case .transferring(let filename) = model.status {
                    HStack(spacing: 12) {
                        ProgressView().controlSize(.small)
                            .tint(.white)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "Transferring...", comment: "SFTP transfer status"))
                                .font(.system(size: 11, weight: .bold))
                            Text(filename)
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .foregroundStyle(.white)
                        
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.blue.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .shadow(color: Color.black.opacity(0.15), radius: 10, y: 5)
                }
                
                if case .error(let message) = model.status {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(message)
                            .font(.system(size: 11))
                            .lineLimit(2)
                        Spacer()
                        Button { model.status = .idle } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(Color.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: model.status)
        }
        .frame(minWidth: 280)
    }

    private var selectedItems: [SFTPItem] {
        model.items.filter { selection.contains($0.id) }
    }

    private func download(_ items: [SFTPItem]) {
        let files = items.filter { !$0.isDirectory }
        guard !files.isEmpty else { return }

        if files.count == 1 {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = files[0].name
            if panel.runModal() == .OK, let url = panel.url {
                model.download(files[0], to: url)
            }
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Choose")
        if panel.runModal() == .OK, let url = panel.url {
            model.download(files, to: url)
        }
    }

    private func upload() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            model.upload(from: panel.urls)
        }
    }
}
