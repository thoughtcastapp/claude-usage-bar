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

    /// Returns the absolute "when" of a reset, in French.
    ///   - past / < 1 min      → "moins d'une minute"
    ///   - < 1h                → "dans 12 min"
    ///   - same day            → "à 16h47"
    ///   - within a week       → "mardi 12 à 13h00"
    ///   - 7+ days out         → "le 19 mai à 13h00"
    static func resetText(from date: Date?, now: Date = Date()) -> String {
        guard let date else { return "—" }
        let interval = max(0, date.timeIntervalSince(now))
        if interval < 60 { return "moins d'une minute" }
        let totalMinutes = Int(interval / 60.0)
        let totalHours = totalMinutes / 60
        let days = totalHours / 24

        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")

        if days >= 7 {
            f.dateFormat = "d MMM 'à' HH'h'mm"
            return "le " + f.string(from: date)
        }
        if days >= 1 {
            f.dateFormat = "EEEE d 'à' HH'h'mm"
            return f.string(from: date)
        }
        if totalHours >= 1 {
            f.dateFormat = "HH'h'mm"
            return "à " + f.string(from: date)
        }
        return "dans \(totalMinutes) min"
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
            return remHours == 0 ? "dans \(days) j" : "dans \(days)j \(remHours)h"
        }
        if totalHours >= 1 {
            let mins = totalMinutes - totalHours * 60
            return mins == 0 ? "dans \(totalHours)h" : "dans \(totalHours)h \(mins)m"
        }
        return nil
    }

    static func resetLine(from date: Date?, now: Date = Date()) -> String {
        let txt = resetText(from: date, now: now)
        if txt == "—" { return txt }
        if let rel = resetRelativeShort(from: date, now: now) {
            return "Reset \(txt) · \(rel)"
        }
        return "Reset \(txt)"
    }

    static func tintColor(forPercent percent: Double) -> NSColor {
        switch percent {
        case ..<80: return .systemGreen
        case ..<95: return .systemOrange
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
        f.locale = Locale(identifier: "fr_FR")
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        let str = f.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
        let sym = currencySymbol(currency)
        return sym.isEmpty ? str : "\(str) \(sym)"
    }

    static func formatInt(_ amount: Double, currency: String?) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "fr_FR")
        f.maximumFractionDigits = 0
        let str = f.string(from: NSNumber(value: amount)) ?? String(format: "%.0f", amount)
        let sym = currencySymbol(currency)
        return sym.isEmpty ? str : "\(str) \(sym)"
    }

    static func relativeAge(seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        if s < 5 { return "à l'instant" }
        if s < 60 { return "il y a \(s)s" }
        let m = s / 60
        if m < 60 { return "il y a \(m) min" }
        let h = m / 60
        return "il y a \(h)h\(String(format: "%02d", m - h * 60))"
    }
}
