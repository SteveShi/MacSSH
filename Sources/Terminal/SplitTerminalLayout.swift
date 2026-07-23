import SwiftUI

/// Shared split-pane layout used by both SSH and local terminal views.
struct SplitTerminalLayout<Main: View, Split: View>: View {
    let direction: SessionTab.SplitDirection
    @ViewBuilder let main: Main
    @ViewBuilder let split: Split

    var body: some View {
        switch direction {
        case .right:
            HStack(spacing: 1) { main; split }
                .background(Color.gray.opacity(0.3))
        case .left:
            HStack(spacing: 1) { split; main }
                .background(Color.gray.opacity(0.3))
        case .down:
            VStack(spacing: 1) { main; split }
                .background(Color.gray.opacity(0.3))
        case .up:
            VStack(spacing: 1) { split; main }
                .background(Color.gray.opacity(0.3))
        }
    }
}
