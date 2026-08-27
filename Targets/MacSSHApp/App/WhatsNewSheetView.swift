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

                Text(String(localized: "What's New in MacSSH 2.0"))
                    .font(.title2.bold())

                Text(String(localized: "A completely redesigned terminal experience with modern Liquid Glass UI and productivity workflows."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            // Feature Highlights
            VStack(alignment: .leading, spacing: 18) {
                featureRow(
                    icon: "curlybraces",
                    iconColor: .orange,
                    title: String(localized: "Code Snippets Library"),
                    subtitle: String(localized: "Quickly manage and run frequent shell commands directly from the right Inspector sidebar with single-click execution.")
                )

                featureRow(
                    icon: "macwindow",
                    iconColor: .blue,
                    title: String(localized: "Liquid Glass Titlebar & Tabs"),
                    subtitle: String(localized: "Clean 2-layer session tabs aligned seamlessly with Ghostty terminal background and transparent titlebar.")
                )

                featureRow(
                    icon: "chart.bar.fill",
                    iconColor: .green,
                    title: String(localized: "Modern Metrics & Local Status"),
                    subtitle: String(localized: "Full-width capsule progress rows for memory, disk, and load monitoring, plus floating status bar for local shell sessions.")
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
