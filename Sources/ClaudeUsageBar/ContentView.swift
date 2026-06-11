import SwiftUI

/// Top-level SwiftUI tree hosted in the menu bar `NSPopover`. The view subscribes to
/// `UsageStore` (an `ObservableObject`) and renders the entire glass-style layout. All string,
/// color, and date formatting is delegated to `Formatting` to keep behavior aligned with the
/// status bar item.
struct ContentView: View {
    @ObservedObject var store: UsageStore

    let onRefresh: () -> Void
    let onLaunchClaude: () -> Void
    let onQuit: () -> Void

    /// A monotonically increasing tick used to refresh "Xs ago" labels every second.
    @State private var clockTick: Int = 0
    private let clockTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        // Reading `clockTick` here ensures `body` re-evaluates each second so the
        // "Updated Xs ago" footer label stays current.
        let _ = clockTick

        return VStack(alignment: .leading, spacing: 14) {
            header

            content
                .animation(.easeInOut(duration: 0.35), value: store.snapshot)
                .animation(.easeInOut(duration: 0.25), value: store.error)

            footer
            toolbar
        }
        .padding(16)
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(clockTimer) { _ in
            clockTick &+= 1
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Claude Usage")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 8)
            if let plan = store.snapshot?.plan {
                Text(plan)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous).fill(.ultraThinMaterial)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
                    )
            }
        }
    }

    // MARK: - Content router

    @ViewBuilder
    private var content: some View {
        if !store.claudeIsRunning {
            claudeNotRunningCard
        } else if let snapshot = store.snapshot {
            VStack(alignment: .leading, spacing: 12) {
                fiveHourCard(snapshot: snapshot)
                weeklyCard(snapshot: snapshot)
                if let extra = snapshot.usage.extra_usage,
                   extra.is_enabled,
                   extra.used_credits != nil || extra.monthly_limit != nil {
                    overageCard(extra: extra)
                }
                if let err = store.error {
                    inlineWarning(message: err)
                }
            }
        } else if let err = store.error {
            errorCard(message: err)
        } else {
            loadingCard
        }
    }

    // MARK: - 5-hour card

    private func fiveHourCard(snapshot: UsageSnapshot) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("5-hour session")

                HStack(alignment: .firstTextBaseline) {
                    if let pct = snapshot.usage.five_hour?.utilization {
                        Text(Formatting.percent(pct))
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                    } else {
                        Text("—")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                if let pct = snapshot.usage.five_hour?.utilization {
                    UsageBar(percent: pct)
                } else {
                    UsageBar(percent: 0)
                        .opacity(0.5)
                }

                resetFooter(date: snapshot.usage.five_hour?.resetsAtDate)
            }
        }
    }

    // MARK: - Weekly card

    /// Pretty labels for the per-feature buckets. Anthropic uses internal code names in the
    /// API; we map the well-known ones to user-facing labels (e.g. `omelette` → Claude Design).
    /// Buckets that come back `null` or with a nil utilization are hidden entirely so the popover
    /// only shows what the user actually consumed this week.
    private static let modelLabels: [(label: String, key: (UsageResponse) -> UsageBucket?)] = [
        ("Sonnet",        { $0.seven_day_sonnet }),
        ("Opus",          { $0.seven_day_opus }),
        ("Cowork",        { $0.seven_day_cowork }),
        ("Claude Design", { $0.seven_day_omelette }),
        ("OAuth Apps",    { $0.seven_day_oauth_apps }),
    ]

    private func activeModelEntries(_ usage: UsageResponse) -> [(label: String, percent: Double)] {
        Self.modelLabels.compactMap { entry in
            guard let bucket = entry.key(usage), let pct = bucket.utilization else { return nil }
            return (entry.label, pct)
        }
    }

    private func weeklyCard(snapshot: UsageSnapshot) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                let weekly = snapshot.usage.seven_day
                let entries = activeModelEntries(snapshot.usage)
                SectionHeader(
                    "Weekly",
                    trailing: weekly?.utilization.map { Formatting.percent($0) }
                )

                if let pct = weekly?.utilization {
                    UsageBar(percent: pct)
                } else {
                    UsageBar(percent: 0)
                        .opacity(0.5)
                }

                if !entries.isEmpty {
                    Divider()
                        .opacity(0.4)
                        .padding(.vertical, 2)

                    // Wider spacing between rows now that each one carries its own progress bar.
                    VStack(spacing: 10) {
                        ForEach(entries, id: \.label) { entry in
                            StatChip(label: entry.label, percent: entry.percent)
                        }
                    }
                }

                resetFooter(date: weekly?.resetsAtDate)
            }
        }
    }

    // MARK: - Reset footer

    /// Small footer line below a usage card showing when the bucket resets. With per-model
    /// progress bars now visible inside the weekly card, the user already understands at a glance
    /// that everything in the card shares the same reset window — no need for a second clarifier.
    private func resetFooter(date: Date?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: "clock")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.secondary)
            Text(Formatting.resetLine(from: date))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
        }
        .padding(.top, 2)
    }

    // MARK: - Overage card

    private func overageCard(extra: ExtraUsage) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("Overage credits")

                // Anthropic returns these in the smallest currency unit (e.g. cents for EUR/USD).
                // Convert to the major unit before formatting so 40 → 0,40 € and 1700 → 17 €.
                let used = Formatting.minorToMajor(extra.used_credits ?? 0, currency: extra.currency)
                let limit = Formatting.minorToMajor(extra.monthly_limit ?? 0, currency: extra.currency)
                let usedStr = Formatting.formatMoney(used, currency: extra.currency)
                let limitStr = Formatting.formatInt(limit, currency: extra.currency)
                let pctStr: String? = extra.utilization.map { Formatting.percent($0) }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(usedStr) / \(limitStr)")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if let pctStr {
                        Text("· \(pctStr)")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                }

                if let pct = extra.utilization {
                    UsageBar(percent: pct)
                }
            }
        }
    }

    // MARK: - State cards

    private var loadingCard: some View {
        GlassCard {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private func errorCard(message: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .systemRed))
                    Text("Error")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                }
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var claudeNotRunningCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Claude Desktop isn't running")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                    Spacer()
                }
                Text("The widget sleeps until Claude is launched.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Spacer()
                    PrimaryButton(title: "Launch Claude", systemImage: "play.fill", action: onLaunchClaude)
                }
                .padding(.top, 2)
            }
        }
    }

    private func inlineWarning(message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(nsColor: .systemOrange))
            Text(message)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(nsColor: .systemOrange).opacity(0.25), lineWidth: 0.5)
        )
    }

    // MARK: - Footer + toolbar

    private var footer: some View {
        HStack(spacing: 6) {
            Group {
                if let snap = store.snapshot {
                    let age = Date().timeIntervalSince(snap.fetchedAt)
                    Text("Updated " + Formatting.relativeAge(seconds: age))
                } else if store.isLoading {
                    Text("Loading…")
                } else {
                    Text("Waiting for data")
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)

            Spacer(minLength: 4)

            if store.isLoading {
                ProgressView()
                    .controlSize(.mini)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            IconButton(systemImage: "arrow.clockwise", help: "Refresh now", action: onRefresh)
            PrimaryButton(title: "Open Claude", systemImage: "arrow.up.right.square", action: onLaunchClaude)
            Spacer(minLength: 4)
            IconButton(systemImage: "xmark", help: "Quit", action: onQuit)
        }
    }
}
