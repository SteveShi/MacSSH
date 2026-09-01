import SwiftUI
import AppKit

// MARK: - Pressable Icon Style

struct PressableIconStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Raised Capsule (Single Layer Clean Glass)

/// 浮起材质胶囊:单层通透玻璃，绝不叠厚重黑底
struct RaisedCapsule: View {
    var body: some View {
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: .capsule)
        } else {
            Capsule()
                .fill(Color.white.opacity(0.12))
                .overlay(
                    Capsule().strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.22), .white.opacity(0.04)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
                )
        }
    }
}

// MARK: - Liquid Glass Icon-Only Picker (for Sidebar Mode Switcher)

struct LiquidGlassIconPicker<T: Hashable>: View {
    @Binding var selection: T
    let items: [(tag: T, icon: String, help: String)]
    @Namespace private var segmentNamespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.tag) { item in
                let isSelected = selection == item.tag
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        selection = item.tag
                    }
                } label: {
                    Image(systemName: item.icon)
                        .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .frame(width: 28, height: 22)
                        .background {
                            if isSelected {
                                RaisedCapsule()
                                    .matchedGeometryEffect(id: "icon-segment", in: segmentNamespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(item.help)
            }
        }
        .padding(2.5)
        .background(
            Capsule()
                .fill(Color.primary.opacity(0.05))
        )
    }
}

// MARK: - Titlebar Session Tab Bar (Berth Parity: Exact 2-Layer Structure)

struct TitlebarSessionTabBar: View {
    @Bindable var model: AppModel
    let isLocalMode: Bool
    var onAdd: () -> Void
    @State private var hoveredTabID: UUID?
    @State private var dropTargetTabID: UUID?

    var body: some View {
        HStack(spacing: 2) {
            if isLocalMode {
                ForEach(model.localTabs) { tab in
                    let isSelected = model.selectedLocalTabID == tab.id
                    tabChip(
                        id: tab.id,
                        title: tab.name,
                        isSelected: isSelected,
                        isConnected: true,
                        canClose: model.localTabs.count > 1,
                        onSelect: {
                            model.selectedLocalTabID = tab.id
                            model.sidebarSelection = .localTab(tab.id)
                        },
                        onClose: {
                            model.removeLocalTab(tab.id)
                        },
                        onReorder: { fromID in
                            model.moveLocalTab(fromID: fromID, toID: tab.id)
                        }
                    )
                }
            } else {
                if model.openTabs.isEmpty {
                    if let conn = model.selectedConnection {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.secondary.opacity(0.5))
                                .frame(width: 5.5, height: 5.5)
                            Text(conn.name)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                    }
                } else {
                    ForEach(model.openTabs) { tab in
                        let isSelected = (model.selectedTabID == tab.id) && (model.sidebarSelection == .connection(tab.connection.id))
                        let isConnected = tab.terminalModel.status == .connected
                        tabChip(
                            id: tab.id,
                            title: tab.connection.name,
                            isSelected: isSelected,
                            isConnected: isConnected,
                            canClose: true,
                            onSelect: {
                                model.selectedTabID = tab.id
                                model.sidebarSelection = .connection(tab.connection.id)
                            },
                            onClose: {
                                model.closeTab(tab.id)
                            },
                            onReorder: { fromID in
                                model.moveOpenTab(fromID: fromID, toID: tab.id)
                            }
                        )
                    }
                }
            }

            // Clean Flat Plus (+) Button inside the track
            Button {
                onAdd()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(isLocalMode ? String(localized: "New Terminal Tab") : String(localized: "New Connection"))
        }
        .padding(3)
        .background(
            Capsule()
                .fill(Color.primary.opacity(0.06))
        )
    }

    private func tabChip(
        id: UUID,
        title: String,
        isSelected: Bool,
        isConnected: Bool,
        canClose: Bool,
        onSelect: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onReorder: @escaping (UUID) -> Void
    ) -> some View {
        let isHovered = hoveredTabID == id
        let isDropTarget = dropTargetTabID == id

        return HStack(spacing: 6) {
            Circle()
                .fill(isConnected ? Color(red: 0.2, green: 0.85, blue: 0.4) : Color.secondary.opacity(0.5))
                .frame(width: 5.5, height: 5.5)

            Text(title)
                .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                .lineLimit(1)

            if canClose && (isSelected || isHovered) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 7.5, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(isSelected ? Color.primary.opacity(0.7) : Color.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background {
            if isSelected {
                RaisedCapsule()
            } else if isDropTarget {
                Capsule().fill(Color.accentColor.opacity(0.2))
                    .overlay(Capsule().stroke(Color.accentColor, lineWidth: 1))
            } else if isHovered {
                Capsule().fill(Color.primary.opacity(0.04))
            }
        }
        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        .contentShape(Capsule())
        .onTapGesture { onSelect() }
        .onHover { hovering in
            hoveredTabID = hovering ? id : nil
        }
        .draggable(id.uuidString) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isConnected ? Color(red: 0.2, green: 0.85, blue: 0.4) : Color.secondary.opacity(0.5))
                    .frame(width: 5.5, height: 5.5)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(RaisedCapsule())
        }
        .dropDestination(for: String.self) { items, _ in
            guard let fromIDStr = items.first,
                  let fromID = UUID(uuidString: fromIDStr),
                  fromID != id else { return false }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                onReorder(fromID)
            }
            return true
        } isTargeted: { targeted in
            withAnimation(.easeInOut(duration: 0.15)) {
                dropTargetTabID = targeted ? id : nil
            }
        }
    }
}
