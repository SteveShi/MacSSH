import SwiftUI

struct InspectorContentView: View {
    let tab: SessionTab
    @Bindable var tabBindable: SessionTab
    
    init(tab: SessionTab) {
        self.tab = tab
        self.tabBindable = tab
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tabBindable.inspectorTab) {
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
                    onRefresh: {
                        tab.terminalModel.forceRefreshMetrics()
                    }
                )
            }
        }
    }
}
