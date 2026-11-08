import UIKit
import EmbrCore
import MidgarCore

/// AutoMod's held messages on the TV, oldest first, with Allow and Deny for the one on top.
final class TVStudioModerationCard: StudioCard {
    var onResolve: ((HeldMessage, Bool) -> Void)?

    private let scale: StudioScale
    private let header = UILabel()
    private let author = UILabel()
    private let text = UILabel()
    private let requests = UILabel()
    private let allow: UIButton
    private let deny: UIButton
    private var current: HeldMessage?
    private(set) var isEmpty = true

    override init(scale: StudioScale) {
        self.scale = scale
        allow = StudioButton.make(title: String(localized: "Allow", comment: "AutoMod held message"), scale: scale)
        deny = StudioButton.make(title: String(localized: "Deny", comment: "AutoMod held message"), scale: scale)
        super.init(scale: scale)
        header.font = scale.font(scale.label, .bold)
        header.textColor = StudioPalette.muted
        author.font = scale.font(scale.body, .bold)
        author.textColor = StudioPalette.text
        text.font = scale.font(scale.body * 0.95)
        text.textColor = StudioPalette.muted
        text.numberOfLines = 3
        requests.font = scale.font(scale.caption)
        requests.textColor = StudioPalette.muted
        allow.addAction(UIAction { [weak self] _ in self?.resolve(true) }, for: .primaryActionTriggered)
        deny.addAction(UIAction { [weak self] _ in self?.resolve(false) }, for: .primaryActionTriggered)
        let buttons = UIStackView(arrangedSubviews: [deny, allow])
        buttons.spacing = scale.spacing
        buttons.distribution = .fillEqually
        let column = UIStackView(arrangedSubviews: [header, author, text, buttons, requests])
        column.axis = .vertical
        column.spacing = scale.spacing * 0.7
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: topAnchor, constant: scale.padding),
            column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: scale.padding),
            column.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -scale.padding),
            column.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -scale.padding),
        ])
        show(ModerationQueue())
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(_ queue: ModerationQueue) {
        current = queue.held.first
        isEmpty = queue.held.isEmpty && queue.requests.isEmpty
        header.text = String(localized: "AUTOMOD HELD · \(queue.held.count)", comment: "Studio moderation card header")
        if let held = current {
            author.text = held.author.displayName
            text.text = held.text
            author.isHidden = false
            text.isHidden = false
            allow.isHidden = false
            deny.isHidden = false
        } else {
            author.isHidden = true
            text.text = String(localized: "Nothing waiting. Held messages show up here.", comment: "Studio moderation card, empty")
            allow.isHidden = true
            deny.isHidden = true
        }
        requests.text = queue.requests.isEmpty ? nil : String(localized: "Unban requests: \(queue.requests.count) waiting on iPhone", comment: "Studio moderation card")
        requests.isHidden = queue.requests.isEmpty
    }

    private func resolve(_ allowIt: Bool) {
        guard let current else { return }
        onResolve?(current, allowIt)
    }
}

/// The screen when the channel isn't live: the next scheduled stream, the last stream's recap and a note that Studio
/// comes back on its own.
final class TVStudioOfflineView: UIView {
    var onSettings: (() -> Void)?

    private let scale: StudioScale
    private let big = UILabel()
    private let nextLabel = UILabel()
    private let note = UILabel()
    private let recapCard: StudioCard
    private let recapHeader = UILabel()
    private let recapGrid = UIStackView()
    private let recapFoot = UILabel()
    private let settingsButton: UIButton

    init(scale: StudioScale) {
        self.scale = scale
        recapCard = StudioCard(scale: scale)
        settingsButton = StudioButton.make(title: String(localized: "Settings", comment: "Studio offline screen button"), scale: scale, symbol: "gearshape")
        super.init(frame: .zero)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    var focusTargets: [UIView] { [settingsButton] }

    func show(_ snapshot: StudioSession.Snapshot) {
        big.text = snapshot.role == .moderator
            ? String(localized: "\(snapshot.channel.broadcasterName) is offline", comment: "Studio offline, moderator mode")
            : String(localized: "You're offline", comment: "Studio offline")
        if let segment = snapshot.nextStream {
            let line = StudioFormat.schedule(segment, now: snapshot.now)
            nextLabel.text = segment.title.isEmpty
                ? String(localized: "Next stream: \(line)", comment: "Studio offline, next stream")
                : String(localized: "Next stream: \(line)\n\(segment.title)", comment: "Studio offline, next stream with its title")
        } else {
            nextLabel.text = String(localized: "No stream on your schedule.", comment: "Studio offline")
        }
        var lines = [String(localized: "Studio comes alive the moment you go live.", comment: "Studio offline")]
        if let wentOffline = snapshot.wentOfflineAt {
            lines.insert(String(localized: "You went offline at \(StudioFormat.clock(wentOffline)). If that wasn't you, check your streaming software.", comment: "Studio offline, the stream ended"), at: 0)
        }
        note.text = lines.joined(separator: "\n\n")
        guard let recap = snapshot.recap else {
            recapCard.isHidden = true
            return
        }
        recapCard.isHidden = false
        if let ended = recap.endedAt {
            recapHeader.text = String(localized: "LAST STREAM · ENDED \(StudioFormat.clock(ended))", comment: "Studio recap header")
        }
        recapGrid.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let cells: [(String, String)] = [
            (recap.peakViewers.formatted(), String(localized: "peak viewers", comment: "Studio recap")),
            (StudioFormat.duration(recap.duration(now: snapshot.now)), String(localized: "live", comment: "Studio recap")),
            ("+\(recap.followers.formatted())", String(localized: "followers", comment: "Studio recap")),
            ((recap.subscriptions + recap.giftedSubscriptions).formatted(), String(localized: "subs and gifts", comment: "Studio recap")),
            (recap.bits.formatted(), String(localized: "bits", comment: "Studio recap")),
            ("\(recap.adBreaks) · \(StudioFormat.duration(TimeInterval(recap.adSeconds)))", String(localized: "ad breaks · total", comment: "Studio recap")),
        ]
        for pair in stride(from: 0, to: cells.count, by: 2) {
            let row = UIStackView(arrangedSubviews: cells[pair..<min(pair + 2, cells.count)].map { recapCell($0.0, $0.1) })
            row.distribution = .fillEqually
            row.spacing = scale.spacing
            recapGrid.addArrangedSubview(row)
        }
    }

    private func recapCell(_ value: String, _ label: String) -> UIView {
        let number = UILabel()
        number.text = value
        number.font = scale.digits(scale.body * 1.7, .heavy)
        number.textColor = StudioPalette.text
        let caption = UILabel()
        caption.text = label
        caption.font = scale.font(scale.caption)
        caption.textColor = StudioPalette.muted
        let column = UIStackView(arrangedSubviews: [number, caption])
        column.axis = .vertical
        column.spacing = 2
        let box = UIView()
        box.backgroundColor = StudioPalette.raised
        box.layer.cornerRadius = scale.corner * 0.7
        column.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: box.topAnchor, constant: scale.padding * 0.7),
            column.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: scale.padding * 0.8),
            column.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -scale.padding * 0.8),
            column.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -scale.padding * 0.7),
        ])
        return box
    }

    private func build() {
        big.font = scale.font(96, .heavy)
        big.textColor = StudioPalette.text
        big.adjustsFontSizeToFitWidth = true
        nextLabel.font = scale.font(scale.body * 1.2)
        nextLabel.textColor = StudioPalette.muted
        nextLabel.numberOfLines = 0
        note.font = scale.font(scale.body)
        note.textColor = StudioPalette.muted
        note.numberOfLines = 0
        settingsButton.addAction(UIAction { [weak self] _ in self?.onSettings?() }, for: .primaryActionTriggered)
        let left = UIStackView(arrangedSubviews: [big, nextLabel, note, settingsButton])
        left.axis = .vertical
        left.alignment = .leading
        left.spacing = 32
        recapHeader.font = scale.font(scale.label, .bold)
        recapHeader.textColor = StudioPalette.muted
        recapGrid.axis = .vertical
        recapGrid.spacing = scale.spacing
        recapFoot.text = String(localized: "Counts only, kept on this TV for 24 hours.", comment: "Studio recap footnote")
        recapFoot.font = scale.font(scale.caption)
        recapFoot.textColor = StudioPalette.muted
        let recapColumn = UIStackView(arrangedSubviews: [recapHeader, recapGrid, recapFoot])
        recapColumn.axis = .vertical
        recapColumn.spacing = scale.spacing
        recapColumn.translatesAutoresizingMaskIntoConstraints = false
        recapCard.addSubview(recapColumn)
        let row = UIStackView(arrangedSubviews: [left, recapCard])
        row.spacing = 60
        row.alignment = .top
        row.distribution = .fillEqually
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            recapColumn.topAnchor.constraint(equalTo: recapCard.topAnchor, constant: scale.padding),
            recapColumn.leadingAnchor.constraint(equalTo: recapCard.leadingAnchor, constant: scale.padding),
            recapColumn.trailingAnchor.constraint(equalTo: recapCard.trailingAnchor, constant: -scale.padding),
            recapColumn.bottomAnchor.constraint(equalTo: recapCard.bottomAnchor, constant: -scale.padding),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 60),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])
    }
}

/// What can be done to one chat message from the TV: pin, shout out, delete, time out, ban, report, block. Ban asks
/// again before it acts. Report and block are there for everyone, moderator or not.
@MainActor
struct TVStudioMessageActions {
    let message: ChatMessage
    let session: StudioSession
    let canModerate: Bool
    let channelLogin: String
    let toast: (String) -> Void

    func sheet() -> UIAlertController {
        let author = message.author
        let sheet = UIAlertController(title: author.displayName, message: message.plainText, preferredStyle: .actionSheet)
        let isSelf = author.id == session.snapshot.channel.id
        if canModerate {
            sheet.addAction(UIAlertAction(title: String(localized: "Pin Message", comment: "Studio message action"), style: .default) { _ in
                run({ try await session.pin(messageID: message.id) }, done: String(localized: "Message pinned", comment: "Studio toast"))
            })
            if !isSelf, !author.id.isEmpty {
                sheet.addAction(UIAlertAction(title: String(localized: "Shout Out", comment: "Studio message action"), style: .default) { _ in
                    run({ try await session.shoutout(toBroadcasterID: author.id) }, done: String(localized: "Shout-out sent", comment: "Studio toast"))
                })
            }
            sheet.addAction(UIAlertAction(title: String(localized: "Delete Message", comment: "Studio message action"), style: .default) { _ in
                session.chat.deleteMessage(messageID: message.id)
                toast(String(localized: "Message deleted", comment: "Studio toast"))
            })
            if !isSelf, !author.id.isEmpty {
                sheet.addAction(UIAlertAction(title: String(localized: "Time Out 10 Minutes", comment: "Studio message action"), style: .default) { _ in
                    session.chat.timeoutUser(userID: author.id, duration: 600)
                    toast(String(localized: "\(author.displayName) timed out for 10 minutes", comment: "Studio toast"))
                })
                sheet.addAction(UIAlertAction(title: String(localized: "Ban…", comment: "Studio message action"), style: .destructive) { _ in
                    confirmBan()
                })
            }
        }
        if !isSelf {
            sheet.addAction(UIAlertAction(title: String(localized: "Report…", comment: "Studio message action"), style: .destructive) { _ in
                session.chat.report(message: message, reason: "Studio: inappropriate message", channelLogin: channelLogin)
                toast(String(localized: "Reported. Their messages are now hidden.", comment: "Studio toast"))
            })
            sheet.addAction(UIAlertAction(title: String(localized: "Block \(author.displayName)", comment: "Studio message action"), style: .destructive) { _ in
                session.chat.block(userID: author.id, login: author.login, message: message, channelLogin: channelLogin)
                toast(String(localized: "Blocked \(author.displayName)", comment: "Studio toast"))
            })
        }
        sheet.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        return sheet
    }

    private func confirmBan() {
        let author = message.author
        let confirm = UIAlertController(
            title: String(localized: "Ban \(author.displayName)?", comment: "Studio ban confirm"),
            message: String(localized: "They can't chat in this channel until someone unbans them.", comment: "Studio ban confirm"),
            preferredStyle: .alert
        )
        confirm.addAction(UIAlertAction(title: String(localized: "Ban", comment: "Studio ban confirm"), style: .destructive) { _ in
            session.chat.banUser(userID: author.id)
            toast(String(localized: "\(author.displayName) banned", comment: "Studio toast"))
        })
        confirm.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .first
            .map { TVRouter.topmost(from: $0) }?
            .present(confirm, animated: true)
    }

    private func run(_ work: @escaping @MainActor () async throws -> Void, done: String) {
        Task {
            do {
                try await work()
                toast(done)
            } catch StudioSession.ActionError.refused(let message) {
                toast(message)
            } catch {
                toast(String(localized: "That didn't work. Try again in a moment.", comment: "Studio toast"))
            }
        }
    }
}
