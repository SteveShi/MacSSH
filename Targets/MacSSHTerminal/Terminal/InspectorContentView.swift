import SwiftUI

struct InspectorContentView: View {
    @Bindable var tab: SessionTab
    
    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab.inspectorTab) {
                ForEach(InspectorTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            Divider()
            
            switch tab.inspectorTab {
            case .sftp:
                SFTPPanelView(model: tab.terminalModel.sftpViewModel)
            case .monitor:
                SystemInfoPanelView(
                    connection: tab.connection,
                    metrics: tab.terminalModel.metrics,
                    status: tab.terminalModel.status,
                    lastErrorMessage: tab.terminalModel.lastErrorMessage,
                    onRefresh: {
                        tab.terminalModel.forceRefreshMetrics()
                    }
                )
            }
        }
    }
}
