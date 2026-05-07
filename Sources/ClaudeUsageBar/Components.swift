import SwiftUI

// MARK: - GlassCard

/// A rounded rectangular container filled with `.ultraThinMaterial` and overlaid with a hairline
/// stroke that adapts to light/dark mode. This produces the layered "card on glass on glass" depth
/// of macOS Tahoe (Liquid Glass) widgets.
struct GlassCard<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder _ content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
    }
}

// MARK: - UsageBar

/// A horizontal capsule progress bar with a subtle gradient fill. The fill color is derived from
/// the Apple-system tint returned by `Formatting.tintColor(forPercent:)`. Animates on value
/// changes.
struct UsageBar: View {
    let percent: Double

    private var clamped: Double {
        max(0.0, min(100.0, percent))
    }

    private var fillColor: Color {
        Color(nsColor: Formatting.tintColor(forPercent: clamped))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.08))

                Capsule(style: .continuous)
                    .fill(fillColor.gradient)
                    .frame(width: max(2, geo.size.width * (clamped / 100.0)))
            }
        }
        .frame(height: 6)
    }
}

// MARK: - StatChip

/// A small pill displaying a label + percentage. Used for per-model rows where every entry needs
/// a tinted indicator that follows the same color logic as the main usage bars.
struct StatChip: View {
    let label: String
    let percent: Double?

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize()

            Spacer(minLength: 8)

            if let pct = percent {
                Text(Formatting.percent(pct))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(nsColor: Formatting.tintColor(forPercent: pct)))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            } else {
                Text("—")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
    }
}

// MARK: - IconButton

/// A small circular button with an SF Symbol glyph. Used in the toolbar at the bottom of the
/// popover (refresh, quit). Uses `.borderless` style so the chrome stays minimal — the popover
/// itself provides the visual frame.
struct IconButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(
                    Circle().fill(.ultraThinMaterial)
                )
                .overlay(
                    Circle().strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
                )
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - PrimaryButton

/// A wider pill-shaped action button used between the icon buttons (e.g. "Open Claude").
struct PrimaryButton: View {
    let title: String
    let systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(
                Capsule(style: .continuous).fill(.ultraThinMaterial)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
            )
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - SectionHeader

/// A small uppercased section label, slightly muted, used at the top of each card.
struct SectionHeader: View {
    let title: String
    let trailing: String?

    init(_ title: String, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.4)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}
