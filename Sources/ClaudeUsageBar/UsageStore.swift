import Foundation
import Combine
import os

struct UsageSnapshot: Sendable, Equatable {
    let usage: UsageResponse
    let plan: String?
    let fetchedAt: Date
}

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var error: String?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var claudeIsRunning: Bool = false

    private var refreshTimer: Timer?
    private var cachedPlan: String?
    private let api = ClaudeAPI()
    private let log = Logger(subsystem: "com.irysagency.claudeusagebar", category: "UsageStore")
    private let refreshInterval: TimeInterval = 30
    private let maxBackoff: TimeInterval = 300
    private var inflight: Task<Void, Never>?
    private var consecutiveFailures: Int = 0
    private var pauseUntil: Date?

    func setClaudeRunning(_ running: Bool) {
        claudeIsRunning = running
    }

    func startRefreshing() {
        stopRefreshing()
        let timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
        refresh()
    }

    func stopRefreshing() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        inflight?.cancel()
        inflight = nil
    }

    func refresh(forceImmediate: Bool = false) {
        guard inflight == nil else { return }
        if !forceImmediate, let until = pauseUntil, until > Date() {
            return
        }
        isLoading = true

        let cached = cachedPlan
        inflight = Task { [weak self] in
            guard let self else { return }
            await self.performRefresh(cachedPlan: cached)
            await MainActor.run {
                self.inflight = nil
            }
        }
    }

    private func performRefresh(cachedPlan: String?) async {
        do {
            let jar = try Cookies.load()
            let usage = try await api.fetchUsage(jar: jar)

            var plan = cachedPlan
            if plan == nil {
                if let limits = try? await api.fetchRateLimits(jar: jar),
                   let tier = limits.rate_limit_tier {
                    plan = Formatting.prettyPlanTier(tier)
                }
            }

            await MainActor.run {
                self.cachedPlan = plan ?? self.cachedPlan
                self.snapshot = UsageSnapshot(usage: usage, plan: self.cachedPlan, fetchedAt: Date())
                self.error = nil
                self.isLoading = false
                self.consecutiveFailures = 0
                self.pauseUntil = nil
            }
        } catch {
            let msg = "\(error)"
            log.error("Refresh failed: \(msg, privacy: .public)")
            await MainActor.run {
                self.consecutiveFailures += 1
                let delay = min(self.refreshInterval * pow(2.0, Double(self.consecutiveFailures - 1)), self.maxBackoff)
                self.pauseUntil = Date().addingTimeInterval(delay)
                self.error = msg
                self.isLoading = false
            }
        }
    }
}
