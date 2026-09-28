import Foundation

/// Currency and crypto rates with disk caching and offline fallback.
/// Fiat rates come from frankfurter.app (ECB reference rates, no key);
/// crypto spot prices come from Coinbase's public API (no key).
/// No network happens inside tests — inject a rate table instead.
public struct CurrencyRates: Sendable {
    /// Major fiat codes plus crypto shorthands.
    public static let fiat: Set<String> = [
        "USD", "EUR", "GBP", "JPY", "CHF", "CAD", "AUD", "NZD",
        "SEK", "NOK", "DKK", "PLN", "CZK", "HUF", "ILS", "MXN",
        "BRL", "ZAR", "SGD", "HKD", "CNY", "KRW", "INR", "TRY",
    ]
    public static let crypto: Set<String> = ["BTC", "ETH", "SOL", "DOGE"]

    public static func isCurrency(_ code: String) -> Bool {
        let upper = code.uppercased()
        return fiat.contains(upper) || crypto.contains(upper)
    }

    public struct Snapshot: Codable, Sendable {
        public var fetchedAt: Date
        /// USD-per-unit for every known code (USD itself is 1.0).
        public var usdPerUnit: [String: Double]

        public init(fetchedAt: Date, usdPerUnit: [String: Double]) {
            self.fetchedAt = fetchedAt
            self.usdPerUnit = usdPerUnit
        }

        public func rate(from: String, to: String) -> Double? {
            guard let f = usdPerUnit[from.uppercased()],
                  let t = usdPerUnit[to.uppercased()], t != 0
            else { return nil }
            return f / t
        }
    }

    /// Converts via the snapshot. Nil when either side is unknown.
    public static func convert(amount: Double, from: String, to: String, rates: Snapshot) -> Double? {
        rates.rate(from: from, to: to).map { amount * $0 }
    }

    /// Freshness of a rate snapshot for gutter/footnote display.
    public enum Freshness: Equatable, Sendable {
        case live
        case cachedStale
        case unavailable
    }

    /// Classifies a snapshot: fresh within TTL is live, older is cached
    /// stale, nil is unavailable. Never invents a number — callers show
    /// the cached value with its age or an honest offline message.
    public static func freshness(of snapshot: Snapshot?, now: Date = Date()) -> Freshness {
        guard let snapshot else { return .unavailable }
        return now.timeIntervalSince(snapshot.fetchedAt) <= RateStore.cacheTTL ? .live : .cachedStale
    }

    /// Human age for footnotes: "just now", "25m ago", "3h ago".
    public static func ageLabel(since fetchedAt: Date, now: Date = Date()) -> String {
        let mins = Int(now.timeIntervalSince(fetchedAt) / 60)
        if mins < 1 { return "just now" }
        if mins < 60 { return "\(mins)m ago" }
        return "\(mins / 60)h ago"
    }
}

/// Disk-cached rate fetcher. Refreshes at most hourly; serves stale cache
/// offline so math notes never break without network.
public final class RateStore: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: CurrencyRates.Snapshot?
    private let fileURL: URL
    public static let cacheTTL: TimeInterval = 3600
    /// Injectable fetch for tests (outage/timeout simulation).
    nonisolated(unsafe) public var fetchOverride: (@Sendable (String) async throws -> Data)?

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("ConstellationContext", isDirectory: true)
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            self.fileURL = base.appendingPathComponent("rates.json")
        }
        load()
    }

    public var current: CurrencyRates.Snapshot? {
        lock.withLock { snapshot }
    }

    public var isStale: Bool {
        lock.withLock {
            guard let snap = snapshot else { return true }
            return Date().timeIntervalSince(snap.fetchedAt) > Self.cacheTTL
        }
    }

    /// Refreshes fiat + crypto rates unless the cache is fresh.
    /// Never throws — offline keeps serving the last snapshot.
    /// Returns true when at least one provider answered; false means the
    /// outage path: caller keeps showing cached rates with their age.
    @discardableResult
    public func refresh() async -> Bool {
        var usdPerUnit: [String: Double] = ["USD": 1.0]
        var anyProvider = false
        // Fiat via Frankfurter (base USD).
        if let data = try? await fetch(url: "https://api.frankfurter.app/latest?from=USD"),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let rates = json["rates"] as? [String: Double], !rates.isEmpty
        {
            anyProvider = true
            for (code, perUSD) in rates where perUSD != 0 {
                usdPerUnit[code.uppercased()] = 1.0 / perUSD
            }
        }
        // Crypto spot via Coinbase.
        for coin in CurrencyRates.crypto {
            let urlString = "https://api.coinbase.com/v2/prices/" + coin + "-USD/spot"
            guard let data = try? await fetch(url: urlString),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataObj = json["data"] as? [String: Any],
                  let amountStr = dataObj["amount"] as? String,
                  let amount = Double(amountStr)
            else { continue }
            anyProvider = true
            usdPerUnit[coin] = amount
        }
        // Outage: no provider answered — keep the old snapshot untouched.
        guard anyProvider, usdPerUnit.count > 1 else { return false }
        let snap = CurrencyRates.Snapshot(fetchedAt: Date(), usdPerUnit: usdPerUnit)
        lock.withLock { snapshot = snap }
        save()
        return true
    }

    /// Refreshes unless the cache is fresh. Returns provider-reached flag.
    @discardableResult
    public func refreshIfNeeded() async -> Bool {
        if !isStale { return true }
        return await refresh()
    }

    public func inject(_ snapshot: CurrencyRates.Snapshot) {
        lock.withLock { self.snapshot = snapshot }
        save()
    }

    private func fetch(url: String) async throws -> Data {
        if let override = fetchOverride { return try await override(url) }
        guard let u = URL(string: url) else { throw URLError(.badURL) }
        var req = URLRequest(url: u, timeoutInterval: 8)
        req.setValue("ConstellationContext/1.0", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)
        return data
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let snap = try? JSONDecoder().decode(CurrencyRates.Snapshot.self, from: data)
        else { return }
        snapshot = snap
    }

    private func save() {
        guard let data = lock.withLock({ () -> Data? in
            guard let snap = snapshot else { return nil }
            return try? JSONEncoder().encode(snap)
        }) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
