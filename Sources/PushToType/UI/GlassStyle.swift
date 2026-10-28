import SwiftUI
import AppKit

/// Native-feeling liquid glass: materials, hairline specular edge, soft depth.
enum GlassTheme {
    static let cornerLarge: CGFloat = 20
    static let cornerMedium: CGFloat = 14
    static let cornerSmall: CGFloat = 10
    static let panelWidth: CGFloat = 368

    /// Specular rim like macOS HUD / Control Center.
    static var strokeGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.55),
                Color.white.opacity(0.12),
                Color.white.opacity(0.08),
                Color.white.opacity(0.28)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var softShadow: Color { Color.black.opacity(0.28) }
}

// MARK: - Glass chrome

struct GlassBackground: View {
    var cornerRadius: CGFloat = GlassTheme.cornerLarge
    var material: Material = .ultraThinMaterial
    var intense: Bool = false

    var body: some View {
        ZStack {
            // Base vibrancy
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(material)

            // Subtle inner frost lift
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(intense ? 0.14 : 0.10),
                            Color.white.opacity(0.02),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .blendMode(.plusLighter)

            // Hairline glass edge
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(GlassTheme.strokeGradient, lineWidth: 1)
        }
    }
}

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 12
    var cornerRadius: CGFloat = GlassTheme.cornerMedium
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.thinMaterial)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                }
            }
    }
}

struct GlassDivider: View {
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.0),
                        Color.white.opacity(0.22),
                        Color.primary.opacity(0.12),
                        Color.white.opacity(0.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
            .padding(.vertical, 10)
    }
}

struct GlassChip: View {
    let title: String
    let ok: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Circle()
                    .fill(ok ? Color.green.opacity(0.9) : Color.orange.opacity(0.95))
                    .frame(width: 6, height: 6)
                    .shadow(color: (ok ? Color.green : Color.orange).opacity(0.5), radius: 3)
                Text(title)
                    .font(.caption2.weight(.semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                Capsule(style: .continuous)
                    .fill((ok ? Color.green : Color.orange).opacity(0.12))
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
    }
}

struct GlassSectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .tracking(0.6)
    }
}

/// Primary glass CTA.
struct GlassProminentButtonStyle: ButtonStyle {
    var destructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded).weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: destructive
                                ? [Color.red.opacity(0.85), Color.red.opacity(0.65)]
                                : [Color.accentColor.opacity(0.95), Color.accentColor.opacity(0.72)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(configuration.isPressed ? 0.1 : 0.28), lineWidth: 0.8)
            }
            .opacity(configuration.isPressed ? 0.88 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct GlassSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.caption, design: .rounded).weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.1 : 0.05))
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
            }
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
