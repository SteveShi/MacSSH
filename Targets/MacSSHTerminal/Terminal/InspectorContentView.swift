import SwiftUI

enum InspectorTarget {
    case ssh(SessionTab)
    case local(LocalTerminalTab)

    var isLocal: Bool {
        if case .local = self { return true }
        return false
    }
}

struct InspectorContentView: View {
    let target: InspectorTarget
    @Bindable var appModel: AppModel
    @Binding var selectedTab: InspectorTab
    @Namespace private var segmentNamespace

    init(tab: SessionTab, appModel: AppModel) {
        self.target = .ssh(tab)
        self.appModel = appModel
        self._selectedTab = Binding(
            get: { tab.inspectorTab },
            set: { tab.inspectorTab = $0 }
        )
    }

    init(localTab: LocalTerminalTab, appModel: AppModel) {
        self.target = .local(localTab)
        self.appModel = appModel
        self._selectedTab = Binding(
            get: { localTab.inspectorTab },
            set: { localTab.inspectorTab = $0 }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Pure Icon Segmented Pill for Inspector (Berth InspectorRail Parity)
            HStack(spacing: 2) {
                ForEach(InspectorTab.allCases) { item in
                    let isCurrentSelected = selectedTab == item
                    let isDisabled = target.isLocal && item != .snippets

                    Button {
                        guard !isDisabled else { return }
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                            selectedTab = item
                        }
                    } label: {
                        Image(systemName: iconName(for: item))
                            .font(.system(size: 12, weight: isCurrentSelected ? .medium : .regular))
                            .foregroundStyle(isCurrentSelected ? Color.primary : (isDisabled ? Color.secondary.opacity(0.3) : Color.secondary))
                            .frame(maxWidth: .infinity, minHeight: 24)
                            .background {
                                if isCurrentSelected {
                                    RaisedCapsule()
                                        .matchedGeometryEffect(id: "rail-segment", in: segmentNamespace)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isDisabled)
                    .help(isDisabled ? String(localized: "仅远程连接支持") : item.title)
                }
            }
            .padding(3)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(0.05))
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider()
                .opacity(0.3)

            switch selectedTab {
            case .sftp:
                if case .ssh(let tab) = target {
                    SFTPPanelView(model: tab.terminalModel.sftpViewModel)
                } else {
                    snippetsView
                }
            case .monitor:
                if case .ssh(let tab) = target {
                    SystemInfoPanelView(
                        connection: tab.connection,
                        metrics: tab.terminalModel.metrics,
                        status: tab.terminalModel.status,
                        lastErrorMessage: tab.terminalModel.lastErrorMessage,
                        onRefresh: {
                            tab.terminalModel.forceRefreshMetrics()
                        }
                    )
                } else {
                    snippetsView
                }
            case .snippets:
                snippetsView
            }
        }
    }

    @ViewBuilder
    private var snippetsView: some View {
        SnippetsInspectorView(appModel: appModel) { snippet, autoExecute in
            let text = autoExecute ? "\(snippet.command)\n" : snippet.command
            switch target {
            case .ssh(let tab):
                tab.cachedSurface?.writeText(text)
            case .local(let tab):
                tab.surfaceView.writeText(text)
            }
        }
    }

    private func iconName(for tab: InspectorTab) -> String {
        switch tab {
        case .sftp: return "folder"
        case .monitor: return "chart.bar"
        case .snippets: return "curlybraces"
        }
    }
}
