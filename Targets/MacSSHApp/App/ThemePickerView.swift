import SwiftUI
import AppKit

struct ThemePickerView: View {
    @Binding var selectedThemeName: String
    var isDarkTarget: Bool? = nil
    var onSelected: ((String) -> Void)? = nil

    @State private var searchQuery: String = ""
    @State private var filterMode: FilterMode = .all
    @Environment(\.dismiss) private var dismiss

    private let themeManager = ThemeManager.shared

    enum FilterMode: String, CaseIterable, Identifiable {
        case all = "All"
        case dark = "Dark"
        case light = "Light"

        var id: String { rawValue }

        var localizedTitle: String {
            switch self {
            case .all: return String(localized: "All")
            case .dark: return String(localized: "Dark")
            case .light: return String(localized: "Light")
            }
        }
    }

    private var filteredThemes: [TerminalThemeItem] {
        themeManager.themes.filter { item in
            let matchesFilter: Bool
            switch filterMode {
            case .all:
                matchesFilter = true
            case .dark:
                matchesFilter = item.isDark
            case .light:
                matchesFilter = !item.isDark
            }
            guard matchesFilter else { return false }

            if searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                return true
            }
            return item.name.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header: Search & Filter
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(String(localized: "Search themes..."), text: $searchQuery)
                        .textFieldStyle(.plain)
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(7)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

                Picker("", selection: $filterMode) {
                    ForEach(FilterMode.allCases) { mode in
                        Text(mode.localizedTitle).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 170)

                Button {
                    importCustomTheme()
                } label: {
                    Label(String(localized: "Import..."), systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            // List of themes with palette previews
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(filteredThemes) { theme in
                        themeRow(theme)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
            }
            .frame(maxHeight: .infinity)

            Divider()

            // Footer
            HStack {
                Text("\(filteredThemes.count) \(String(localized: "themes available"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(String(localized: "Done")) {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(12)
        }
        .frame(width: 480, height: 380)
        .preferredColorScheme(isDarkTarget == true ? .dark : (isDarkTarget == false ? .light : nil))
        .onAppear {
            if let isDarkTarget {
                filterMode = isDarkTarget ? .dark : .light
            }
        }
    }

    @ViewBuilder
    private func themeRow(_ theme: TerminalThemeItem) -> some View {
        let isSelected = selectedThemeName.localizedCaseInsensitiveCompare(theme.name) == .orderedSame

        Button {
            selectedThemeName = theme.name
            onSelected?(theme.name)
            ToastManager.shared.show(String(localized: "Theme applied"), message: theme.name, preset: .done, duration: 2.0)
        } label: {
            HStack(spacing: 12) {
                // Background & Foreground badge
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(hex: theme.background))
                        .frame(width: 28, height: 28)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
                        )
                    Text("Aa")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(hex: theme.foreground))
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(theme.name)
                            .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                            .foregroundStyle(.primary)

                        if theme.isCustom {
                            Text(String(localized: "Custom"))
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.blue.opacity(0.15), in: Capsule())
                                .foregroundStyle(.blue)
                        }
                    }

                    // 16 color palette preview bar
                    HStack(spacing: 2) {
                        ForEach(0..<16, id: \.self) { idx in
                            if let hex = theme.palette[idx] {
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(Color(hex: hex))
                                    .frame(width: 12, height: 8)
                            }
                        }
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 15))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func importCustomTheme() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = []

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let imported = try themeManager.importTheme(from: url)
                selectedThemeName = imported.name
                onSelected?(imported.name)
                ToastManager.shared.show(String(localized: "Theme imported"), message: imported.name, preset: .done, duration: 2.5)
            } catch {
                ToastManager.shared.show(String(localized: "Import failed"), message: error.localizedDescription, preset: .error, duration: 3.0)
            }
        }
    }
}

private extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard clean.count == 6, let num = UInt64(clean, radix: 16) else {
            self = .clear
            return
        }
        let r = Double((num >> 16) & 0xFF) / 255.0
        let g = Double((num >> 8) & 0xFF) / 255.0
        let b = Double(num & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
