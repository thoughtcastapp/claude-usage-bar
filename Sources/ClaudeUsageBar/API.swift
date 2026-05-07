import Foundation

struct UsageBucket: Decodable, Sendable, Equatable {
    let utilization: Double?
    let resets_at: String?

    var resetsAtDate: Date? {
        guard let s = resets_at else { return nil }
        return ISO8601Formatters.parse(s)
    }
}

struct ExtraUsage: Decodable, Sendable, Equatable {
    let is_enabled: Bool
    let monthly_limit: Double?
    let used_credits: Double?
    let utilization: Double?
    let currency: String?
}

struct UsageResponse: Decodable, Sendable, Equatable {
    let five_hour: UsageBucket?
    let seven_day: UsageBucket?
    let seven_day_oauth_apps: UsageBucket?
    let seven_day_opus: UsageBucket?
    let seven_day_sonnet: UsageBucket?
    let seven_day_cowork: UsageBucket?
    let seven_day_omelette: UsageBucket?
    let tangelo: UsageBucket?
    let iguana_necktie: UsageBucket?
    let omelette_promotional: UsageBucket?
    let extra_usage: ExtraUsage?
}

struct RateLimitsResponse: Decodable, Sendable, Equatable {
    let rate_limit_tier: String?
}

enum APIError: Error, CustomStringConvertible {
    case invalidURL
    case nonHTTPResponse
    case http(Int, String?)
    case decoding(Error)
    case transport(Error)

    var description: String {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .nonHTTPResponse: return "Non-HTTP response"
        case .http(let code, _):
            // Body intentionally not surfaced — it could echo cookies/headers from upstream errors.
            return "HTTP \(code)"
        case .decoding(let e): return "Decoding error: \(e.localizedDescription)"
        case .transport(let e): return "Network error: \(e.localizedDescription)"
        }
    }
}

enum ISO8601Formatters {
    nonisolated(unsafe) private static let withFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ s: String) -> Date? {
        if let d = withFractional.date(from: s) { return d }
        return plain.date(from: s)
    }
}

struct ClaudeAPI: Sendable {
    let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    private func makeRequest(_ url: URL, jar: CookieJar) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("https://claude.ai/", forHTTPHeaderField: "Referer")
        req.setValue(jar.headerValue, forHTTPHeaderField: "Cookie")
        return req
    }

    func fetchUsage(jar: CookieJar) async throws -> UsageResponse {
        guard let url = URL(string: "https://claude.ai/api/organizations/\(jar.orgUUID)/usage") else {
            throw APIError.invalidURL
        }
        let req = makeRequest(url, jar: jar)
        return try await perform(req)
    }

    func fetchRateLimits(jar: CookieJar) async throws -> RateLimitsResponse {
        guard let url = URL(string: "https://claude.ai/api/organizations/\(jar.orgUUID)/rate_limits") else {
            throw APIError.invalidURL
        }
        let req = makeRequest(url, jar: jar)
        return try await perform(req)
    }

    private func perform<T: Decodable>(_ req: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.nonHTTPResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw APIError.http(http.statusCode, body)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }
}
