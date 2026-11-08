import Foundation
import EmbrCore

/// The words Studio puts on screen for each moment, shared by the Apple TV, iPad and iPhone screens.
enum StudioFormat {
    struct AlertText {
        let symbol: String
        let title: String
        let detail: String?
    }

    static func alert(_ item: StudioFeedItem) -> AlertText {
        switch item.event {
        case .follow(let follow):
            if item.moreFollowers.isEmpty {
                return AlertText(symbol: "heart.fill", title: String(localized: "\(follow.userName) followed", comment: "Studio alert"), detail: nil)
            }
            return AlertText(
                symbol: "heart.fill",
                title: String(localized: "\(item.moreFollowers.count + 1) new followers", comment: "Studio alert, several follows at once"),
                detail: ([follow.userName] + item.moreFollowers.prefix(3)).joined(separator: ", ")
            )
        case .subscription(let sub):
            return AlertText(symbol: "star.fill", title: subscriptionTitle(sub), detail: subscriptionDetail(sub))
        case .giftBomb(let bomb):
            let who = bomb.gifterName ?? String(localized: "Someone", comment: "Studio alert, an anonymous gifter")
            return AlertText(
                symbol: "gift.fill",
                title: String(localized: "\(who) gifted \(bomb.count) subs", comment: "Studio alert"),
                detail: tierText(bomb.tier)
            )
        case .cheer(let cheer):
            let who = cheer.userName ?? String(localized: "Someone", comment: "Studio alert, an anonymous cheerer")
            return AlertText(
                symbol: "diamond.fill",
                title: String(localized: "\(who) cheered \(cheer.bits.formatted())", comment: "Studio alert, bits"),
                detail: cheer.message.isEmpty ? nil : cheer.message
            )
        case .powerUp(let power):
            return AlertText(
                symbol: "bolt.fill",
                title: String(localized: "\(power.userName) used \(power.title)", comment: "Studio alert, a Power-up"),
                detail: String(localized: "\(power.bits.formatted()) bits", comment: "Studio alert detail")
            )
        case .raid(let raid):
            return AlertText(
                symbol: "person.3.fill",
                title: String(localized: "\(raid.raiderName) raided with \(raid.viewers.formatted())", comment: "Studio alert"),
                detail: nil
            )
        case .redemption(let redemption):
            return AlertText(
                symbol: "sparkles",
                title: String(localized: "\(redemption.userName) redeemed \(redemption.rewardTitle)", comment: "Studio alert"),
                detail: redemption.input.isEmpty
                    ? String(localized: "\(redemption.cost.formatted()) points", comment: "Studio alert detail")
                    : redemption.input
            )
        case .charity(let charity):
            let amount = charity.amount.formatted(.currency(code: charity.currency.isEmpty ? "USD" : charity.currency))
            return AlertText(
                symbol: "hands.and.sparkles.fill",
                title: String(localized: "\(charity.userName) donated \(amount)", comment: "Studio alert, a charity donation"),
                detail: charity.charityName
            )
        default:
            return AlertText(symbol: "bell.fill", title: "", detail: nil)
        }
    }

    private static func subscriptionTitle(_ sub: StudioSubscription) -> String {
        switch sub.kind {
        case .new:
            sub.isPrime
                ? String(localized: "\(sub.userName) subscribed with Prime", comment: "Studio alert")
                : String(localized: "\(sub.userName) subscribed", comment: "Studio alert")
        case .resub(let months):
            String(localized: "\(sub.userName) resubscribed · \(months) months", comment: "Studio alert")
        case .gift(let recipient):
            String(localized: "\(sub.userName) gifted a sub to \(recipient)", comment: "Studio alert")
        case .giftUpgrade, .primeUpgrade:
            String(localized: "\(sub.userName) continued their sub", comment: "Studio alert")
        case .payItForward:
            String(localized: "\(sub.userName) paid it forward", comment: "Studio alert")
        }
    }

    private static func subscriptionDetail(_ sub: StudioSubscription) -> String? {
        if !sub.message.isEmpty { return sub.message }
        return sub.tier == .one ? nil : tierText(sub.tier)
    }

    static func tierText(_ tier: StudioTier) -> String {
        String(localized: "Tier \(tier.number)", comment: "Subscription tier")
    }

    static func countdown(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.up)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    static func uptime(since start: Date, now: Date) -> String {
        countdown(now.timeIntervalSince(start))
    }

    static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func duration(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = interval >= 3600 ? [.hour, .minute] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: interval) ?? countdown(interval)
    }

    static func schedule(_ segment: ScheduleSegment, now: Date) -> String {
        let calendar = Calendar.current
        let time = segment.startTime.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(segment.startTime) {
            return String(localized: "Today, \(time)", comment: "Studio offline screen, next stream")
        }
        if calendar.isDateInTomorrow(segment.startTime) {
            return String(localized: "Tomorrow, \(time)", comment: "Studio offline screen, next stream")
        }
        return segment.startTime.formatted(.dateTime.weekday(.wide).hour().minute())
    }
}
