import SwiftUI

struct WhatsNewSheetView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
                    .padding(.top, 8)

                Text(String(localized: "What's New in MacSSH 2.2"))
                    .font(.title2.bold())

                Text(String(localized: "Curated terminal color schemes, native shell integration HUD, and enhanced connection resilience."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            // Feature Highlights
            VStack(alignment: .leading, spacing: 18) {
                featureRow(
                    icon: "paintpalette.fill",
                    iconColor: .purple,
                    title: String(localized: "Curated Color Schemes"),
                    subtitle: String(localized: "Rich catalog of terminal themes (Tokyo Night, Catppuccin, Nord, Dracula, and more) with real-time live reloading across all sessions.")
                )

                featureRow(
                    icon: "bell.badge.fill",
                    iconColor: .orange,
                    title: String(localized: "Native Shell Integration & HUD"),
                    subtitle: String(localized: "OSC 7 remote directory auto-sync with SFTP, dynamic window titles, and floating toasts for long-running commands.")
                )

                featureRow(
                    icon: "shield.lefthalf.filled",
                    iconColor: .green,
                    title: String(localized: "Dual-Channel SSH Architecture"),
                    subtitle: String(localized: "Zero-conflict dual-channel architecture isolating terminal interactive PTY from SFTP and host monitoring background telemetry.")
                )
            }
            .padding(.horizontal, 16)

            Spacer()

            // Continue Button
            Button {
                dismiss()
            } label: {
                Text(String(localized: "Get Started"))
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding(24)
        .frame(width: 480, height: 460)
    }

    private func featureRow(icon: String, iconColor: Color, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(iconColor)
                .frame(width: 32, height: 32)
                .background(iconColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
