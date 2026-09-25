import Foundation

/// Decides when Embr has earned the right to interrupt with Apple's own rating prompt.
///
/// A pure function of banked state — how many times the app has delivered its core value, when
/// it last asked, and how much of that value was fresh at the time — so the schedule (first ask
/// at the second success, a re-ask only after both a fourteen-day cooldown and three fresh
/// successes, never a fourth ask inside a rolling year) is exercised directly in tests instead of
/// through UserDefaults and StoreKit.
public enum ReviewPromptPolicy {
    public static let successesForFirstAsk = 2
    public static let minimumIntervalBetweenAsks: TimeInterval = 14 * secondsPerDay
    public static let minimumNewSuccessesBetweenAsks = 3
    public static let maximumAsksPerRollingYear = 3
    public static let rollingYearInterval: TimeInterval = 365 * secondsPerDay

    private static let secondsPerDay: TimeInterval = 86_400

    public static func shouldAsk(
        successCount: Int,
        askDates: [Date],
        successCountAtLastAsk: Int,
        now: Date
    ) -> Bool {
        guard successCount >= successesForFirstAsk else { return false }
        guard recentAskCount(in: askDates, before: now) < maximumAsksPerRollingYear else { return false }
        guard let mostRecentAsk = askDates.max() else { return true }
        guard now.timeIntervalSince(mostRecentAsk) >= minimumIntervalBetweenAsks else { return false }
        return successCount - successCountAtLastAsk >= minimumNewSuccessesBetweenAsks
    }

    private static func recentAskCount(in askDates: [Date], before now: Date) -> Int {
        askDates.filter { now.timeIntervalSince($0) < rollingYearInterval }.count
    }
}
