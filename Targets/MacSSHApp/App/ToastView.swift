import SwiftUI

struct ToastOverlayView: View {
    let toastManager = ToastManager.shared
    @State private var isHovered = false

    var body: some View {
        if let toast = toastManager.currentToast {
            toastCapsule(toast)
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.95)),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
                .zIndex(9999)
        }
    }

    @ViewBuilder
    private func toastCapsule(_ toast: ToastItem) -> some View {
        HStack(spacing: 9) {
            presetIcon(for: toast.preset)

            VStack(alignment: .leading, spacing: 1) {
                Text(toast.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary)

                if let message = toast.message, !message.isEmpty {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Button {
                toastManager.dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(4)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1.0 : 0.0)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 5)
        .padding(.top, 12)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            toastManager.dismiss()
        }
    }

    @ViewBuilder
    private func presetIcon(for preset: ToastPreset) -> some View {
        switch preset {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 16, weight: .semibold))
        case .error:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.system(size: 16, weight: .semibold))
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 16, weight: .semibold))
        case .info:
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.blue)
                .font(.system(size: 16, weight: .semibold))
        case .custom(let systemImage, let tintColor):
            Image(systemName: systemImage)
                .foregroundStyle(tintColor)
                .font(.system(size: 16, weight: .semibold))
        }
    }
}
