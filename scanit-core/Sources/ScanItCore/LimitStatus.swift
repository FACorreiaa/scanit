import Foundation

/// Where a trip's total stands against its limit (`DESIGN.md` §5).
public enum LimitState: String, Sendable, Comparable {
    case noLimit
    /// Below 80 % of the limit.
    case ok
    /// From 80 % up to and including 100 %.
    case near
    /// Above 100 %.
    case over

    /// The haptic to play when the state changes, or `nil`. Only upward crossings speak;
    /// removing items to get back under is silent.
    public static func feedback(from old: LimitState, to new: LimitState) -> LimitFeedback? {
        guard new > old else { return nil }
        switch new {
        case .near: return .warning
        case .over: return .error
        case .noLimit, .ok: return nil
        }
    }

    private var rank: Int {
        switch self {
        case .noLimit: 0
        case .ok: 1
        case .near: 2
        case .over: 3
        }
    }

    public static func < (lhs: LimitState, rhs: LimitState) -> Bool {
        lhs.rank < rhs.rank
    }
}

public enum LimitFeedback: Sendable, Equatable {
    case warning, error
}

/// Running total against an optional limit. Pure integer maths so iOS and Android agree exactly.
public struct LimitStatus: Hashable, Sendable {
    /// Percent of the limit at which `near` starts.
    public static let nearThresholdPercent = 80

    public let totalMinor: Int
    public let limitMinor: Int?

    public init(totalMinor: Int, limitMinor: Int?) {
        self.totalMinor = totalMinor
        self.limitMinor = limitMinor.flatMap { $0 > 0 ? $0 : nil }
    }

    public var state: LimitState {
        guard let limitMinor else { return .noLimit }
        if totalMinor > limitMinor { return .over }
        if totalMinor * 100 >= limitMinor * Self.nearThresholdPercent { return .near }
        return .ok
    }

    /// Negative when over the limit.
    public var remainingMinor: Int? {
        limitMinor.map { $0 - totalMinor }
    }

    /// 0…1, and above 1 when over. For drawing the limit bar.
    public var progress: Double? {
        limitMinor.map { Double(totalMinor) / Double($0) }
    }

    /// How many more items of average price fit before the limit.
    public func itemsLeft(averageItemMinor: Int) -> Int? {
        guard let remainingMinor, averageItemMinor > 0 else { return nil }
        return max(0, remainingMinor / averageItemMinor)
    }
}

extension Money {
    /// From a user-typed amount, rounded half-up to the currency's minor units.
    public init(decimal: Decimal, currency: String) {
        var scaled = decimal * pow(10, Money.minorUnitDigits(for: currency))
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        self.init(amountMinor: NSDecimalNumber(decimal: rounded).intValue, currency: currency)
    }
}
