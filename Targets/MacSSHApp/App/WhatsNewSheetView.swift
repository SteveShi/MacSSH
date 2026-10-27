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

                Text(String(localized: "What's New in MacSSH 2.3"))
                    .font(.title2.bold())

                Text(String(localized: "Persistent terminal daemon (macsshd), native CLI tooling, background session detach & reattach, and instant VT screen replay."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            // Feature Highlights
            VStack(alignment: .leading, spacing: 18) {
                featureRow(
                    icon: "bolt.shield.fill",
                    iconColor: .purple,
                    title: String(localized: "Persistent Terminal Daemon (macsshd)"),
                    subtitle: String(localized: "Local terminal sessions run detached in the background. Quitting the app or updating via Sparkle never kills your dev servers, builds, or scripts.")
                )

                featureRow(
                    icon: "terminal.fill",
                    iconColor: .green,
                    title: String(localized: "Native CLI & Automation (macssh)"),
                    subtitle: String(localized: "Control MacSSH from scripts, Raycast, and terminal via macssh list, capture, send, new, and kill with tmux-compatible key vocabulary.")
                )

                featureRow(
                    icon: "square.stack.3d.up.fill",
                    iconColor: .orange,
                    title: String(localized: "Background Sessions & Instant Replay"),
                    subtitle: String(localized: "Detach active local tabs into the background (Cmd+Shift+D) and reattach anytime with full 256 KiB VT screen state restoration.")
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
