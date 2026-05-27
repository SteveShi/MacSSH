import SwiftUI
import libssh2_swift

struct ConnectionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SSHConnection
    @State private var password: String = ""
    let onSave: (SSHConnection) -> Void

    init(connection: SSHConnection?, onSave: @escaping (SSHConnection) -> Void) {
        let base = connection ?? SSHConnection(name: "", host: "", port: 22, username: "")
        _draft = State(initialValue: base)
        if let conn = connection {
             _password = State(initialValue: KeychainStore.loadPassword(account: conn.keychainAccount) ?? "")
        }
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Image(systemName: "tag.fill")
                            .foregroundStyle(.blue)
                            .frame(width: 20)
                        TextField(String(localized: "Name"), text: $draft.name)
                    }
                } header: {
                    Text(String(localized: "General Information"))
                } footer: {
                    Text(String(localized: "How this connection appears in your sidebar."))
                }

                Section {
                    HStack {
                        Image(systemName: "server.rack")
                            .foregroundStyle(.blue)
                            .frame(width: 20)
                        TextField(String(localized: "Hostname or IP"), text: $draft.host)
                    }
                    
                    HStack {
                        Image(systemName: "number")
                            .foregroundStyle(.blue)
                            .frame(width: 20)
                        TextField(String(localized: "Port"), value: $draft.port, format: .number)
                            .frame(width: 80)
                    }
                } header: {
                    Text(String(localized: "Server Address"))
                } footer: {
                    Text(String(localized: "The remote address and SSH port (default is 22)."))
                }

                Section {
                    HStack {
                        Image(systemName: "person.fill")
                            .foregroundStyle(.blue)
                            .frame(width: 20)
                        TextField(String(localized: "User"), text: $draft.username)
                    }
                } header: {
                    Text(String(localized: "User Account"))
                } footer: {
                    Text(String(localized: "The username used to log in to the remote server."))
                }

                Section {
                    Toggle(String(localized: "Use Public Key"), isOn: $draft.usePublicKey)
                    
                    if draft.usePublicKey {
                        HStack {
                            Image(systemName: "key.fill")
                                .foregroundStyle(.blue)
                                .frame(width: 20)
                            Text(draft.keyPath ?? String(localized: "Select key..."))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            
                            Spacer()
                            
                            Button(String(localized: "Browse")) {
                                let panel = NSOpenPanel()
                                panel.allowsMultipleSelection = false
                                panel.canChooseDirectories = false
                                panel.canChooseFiles = true
                                if panel.runModal() == .OK {
                                    draft.keyPath = panel.url?.path
                                }
                            }
                        }
                    } else {
                        HStack {
                            Image(systemName: "key.fill")
                                .foregroundStyle(.blue)
                                .frame(width: 20)
                            SecureField(String(localized: "Password"), text: $password)
                        }
                    }
                } header: {
                    Text(String(localized: "Authentication"))
                }
            }
            .formStyle(.grouped)
            .navigationTitle(String(localized: "Connection Settings"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        if !draft.usePublicKey && !password.isEmpty {
                            KeychainStore.savePassword(password, account: draft.keychainAccount)
                        } else if draft.usePublicKey {
                            KeychainStore.deletePassword(account: draft.keychainAccount)
                        }
                        onSave(draft)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.name.isEmpty || draft.host.isEmpty || draft.username.isEmpty)
                }
            }
        }
    }
}
