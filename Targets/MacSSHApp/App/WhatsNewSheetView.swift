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

                Text(String(localized: "What's New in MacSSH 2.4"))
                    .font(.title2.bold())

                Text(String(localized: "Ghostty 1.4.0 terminal engine, OSC 7501 Program Status & AI agent tracking, and background tab GPU memory optimization."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            // Feature Highlights
            VStack(alignment: .leading, spacing: 18) {
                featureRow(
                    icon: "exclamationmark.bubble.fill",
                    iconColor: .orange,
                    title: String(localized: "Program Status Protocol (OSC 7501 & OSC 9;4)"),
                    subtitle: String(localized: "Real-time sidebar badges, progress indicators, and native Toast alerts when CLI tools or AI coding agents finish, error, or wait for input.")
                )

                featureRow(
                    icon: "bolt.horizontal.fill",
                    iconColor: .cyan,
                    title: String(localized: "Ghostty 1.4.0 Engine & Scrollback Compression"),
                    subtitle: String(localized: "Upgraded to Ghostty 1.4.0 with lossless scrollback compression, OSC 8 hover link previews, and Kitty multi-MIME clipboard support.")
                )

                featureRow(
                    icon: "memorychip.fill",
                    iconColor: .green,
                    title: String(localized: "Background Tab GPU Resource Release"),
                    subtitle: String(localized: "Inactive terminal tabs automatically release Metal textures and framebuffers, restoring rendering in under 1ms when switched back.")
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
