import Foundation
import AppKit

enum Formatting {
    static let filledBlock: Character = "\u{2588}"
    static let emptyBlock: Character = "\u{2591}"

    static func bar(percent: Double, width: Int = 10) -> String {
        let clamped = max(0.0, min(100.0, percent))
        let filled = Int((clamped / 100.0 * Double(width)).rounded())
        let safe = max(0, min(width, filled))
        return String(repeating: String(filledBlock), count: safe)
            + String(repeating: String(emptyBlock), count: width - safe)
    }

    static func percent(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        return "\(rounded)%"
    }

    /// Returns the absolute "when" of a reset, in English.
    ///   - past / < 1 min      → "in less than a minute"
    ///   - < 1h                → "in 12 min"
    ///   - same day            → "at 4:47 PM"
    ///   - within a week       → "Tuesday at 1:00 PM"
    ///   - 7+ days out         → "on May 19 at 1:00 PM"
    static func resetText(from date: Date?, now: Date = Date()) -> String {
        guard let date else { return "—" }
        let interval = max(0, date.timeIntervalSince(now))
        if interval < 60 { return "in less than a minute" }
        let totalMinutes = Int(interval / 60.0)
        let totalHours = totalMinutes / 60
        let days = totalHours / 24

        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")

        if days >= 7 {
            f.dateFormat = "MMM d 'at' h:mm a"
            return "on " + f.string(from: date)
        }
        if days >= 1 {
            f.dateFormat = "EEEE 'at' h:mm a"
            return f.string(from: date)
        }
        if totalHours >= 1 {
            f.dateFormat = "h:mm a"
            return "at " + f.string(from: date)
        }
        return "in \(totalMinutes) min"
    }

    /// Compact relative gap, useful as a subtle parenthetical next to the absolute time.
    /// Returns nil for anything under an hour (where the absolute already implies "soon").
    static func resetRelativeShort(from date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let interval = max(0, date.timeIntervalSince(now))
        let totalMinutes = Int(interval / 60.0)
        let totalHours = totalMinutes / 60
        let days = totalHours / 24
        if days >= 1 {
            let remHours = totalHours - days * 24
            return remHours == 0 ? "in \(days)d" : "in \(days)d \(remHours)h"
        }
        if totalHours >= 1 {
            let mins = totalMinutes - totalHours * 60
            return mins == 0 ? "in \(totalHours)h" : "in \(totalHours)h \(mins)m"
        }
        return nil
    }

    static func resetLine(from date: Date?, now: Date = Date()) -> String {
        let txt = resetText(from: date, now: now)
        if txt == "—" { return txt }
        if let rel = resetRelativeShort(from: date, now: now) {
            return "Resets \(txt) · \(rel)"
        }
        return "Resets \(txt)"
    }

    static func tintColor(forPercent percent: Double) -> NSColor {
        // Aggressive thresholds so users get warned early on a fixed weekly budget:
        //   <  50%  green   — comfortable
        //   50–80% orange   — watch it
        //   >= 80% red      — close to the cap
        switch percent {
        case ..<50: return .systemGreen
        case ..<80: return .systemOrange
        default:    return .systemRed
        }
    }

    static func iconName(forPercent percent: Double) -> String {
        switch percent {
        case ..<25: return "circle.dotted"
        case ..<50: return "circle.bottomhalf.filled"
        case ..<75: return "circle.lefthalf.filled"
        default:    return "circle.fill"
        }
    }

    static func prettyPlanTier(_ raw: String) -> String {
        let trimmed = raw.hasPrefix("default_") ? String(raw.dropFirst("default_".count)) : raw
        let parts = trimmed.split(separator: "_").map(String.init)
        return parts.map { piece -> String in
            if piece.lowercased() == "claude" { return "Claude" }
            if piece.lowercased() == "max" { return "Max" }
            if piece.lowercased() == "pro" { return "Pro" }
            if piece.lowercased() == "free" { return "Free" }
            if piece.range(of: #"^[0-9]+x$"#, options: .regularExpression) != nil { return piece }
            return piece.prefix(1).uppercased() + piece.dropFirst()
        }.joined(separator: " ")
    }

    static func currencySymbol(_ code: String?) -> String {
        switch (code ?? "").uppercased() {
        case "EUR": return "€"
        case "USD": return "$"
        case "GBP": return "£"
        case "JPY": return "¥"
        case let other where !other.isEmpty: return other
        default: return ""
        }
    }

    /// ISO 4217 currencies with no fractional unit. For these, API minor-unit values are already
    /// the major unit and shouldn't be divided. (Stripe maintains a similar list.)
    private static let zeroDecimalCurrencies: Set<String> = [
        "BIF", "CLP", "DJF", "GNF", "ISK", "JPY", "KMF", "KRW", "MGA",
        "PYG", "RWF", "UGX", "VND", "VUV", "XAF", "XOF", "XPF"
    ]

    /// Anthropic returns overage credits in the smallest currency unit (cents for EUR/USD/GBP,
    /// whole units for JPY/KRW/etc). Convert to the major unit for display.
    static func minorToMajor(_ amount: Double, currency: String?) -> Double {
        let code = (currency ?? "").uppercased()
        return zeroDecimalCurrencies.contains(code) ? amount : amount / 100.0
    }

    static func formatMoney(_ amount: Double, currency: String?) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        let str = f.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
        let sym = currencySymbol(currency)
        return sym.isEmpty ? str : "\(sym)\(str)"
    }

    static func formatInt(_ amount: Double, currency: String?) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = 0
        let str = f.string(from: NSNumber(value: amount)) ?? String(format: "%.0f", amount)
        let sym = currencySymbol(currency)
        return sym.isEmpty ? str : "\(sym)\(str)"
    }

    static func relativeAge(seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        if s < 5 { return "just now" }
        if s < 60 { return "\(s)s ago" }
        let m = s / 60
        if m < 60 { return "\(m) min ago" }
        let h = m / 60
        return "\(h)h \(String(format: "%02d", m - h * 60))m ago"
    }
}
