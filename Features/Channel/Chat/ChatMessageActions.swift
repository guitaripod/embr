import UIKit
import EmbrCore

/// What a long-pressed chat message offers: replying, the author's card, copying, and for moderators deleting, a
/// timeout of a chosen length and a ban that asks once more; for anyone else's message, blocking and reporting.
@MainActor
struct ChatMessageActions {
    let message: ChatMessage
    let isOwn: Bool
    let canChat: Bool
    let canModerate: Bool
    let channelLogin: String?
    let viewModel: ChatViewModel
    let onReply: () -> Void
    let onViewProfile: () -> Void

    func present(from host: UIViewController, sourceRect: CGRect) {
        let sheet = UIAlertController(title: message.author.displayName, message: nil, preferredStyle: .actionSheet)
        if canChat {
            sheet.addAction(UIAlertAction(title: String(localized: "Reply"), style: .default) { _ in onReply() })
        }
        sheet.addAction(UIAlertAction(title: String(localized: "View Profile"), style: .default) { _ in onViewProfile() })
        let text = message.plainText
        sheet.addAction(UIAlertAction(title: String(localized: "Copy Message"), style: .default) { _ in
            UIPasteboard.general.string = text
        })
        if canModerate, !isOwn {
            let messageID = message.id
            let viewModel = viewModel
            sheet.addAction(UIAlertAction(title: String(localized: "Delete Message"), style: .destructive) { _ in
                viewModel.deleteMessage(messageID: messageID)
            })
            sheet.addAction(UIAlertAction(title: String(localized: "Timeout…"), style: .default) { [weak host] _ in
                guard let host else { return }
                presentTimeoutChoices(from: host, sourceRect: sourceRect)
            })
            sheet.addAction(UIAlertAction(title: String(localized: "Ban…"), style: .destructive) { [weak host] _ in
                guard let host else { return }
                confirmBan(from: host)
            })
        }
        if !isOwn {
            sheet.addAction(UIAlertAction(title: String(localized: "Block @\(message.author.login)"), style: .destructive) { _ in
                Haptics.notify(.success)
                viewModel.block(userID: message.author.id, login: message.author.login, message: message, channelLogin: channelLogin)
            })
            sheet.addAction(UIAlertAction(title: String(localized: "Report Message"), style: .destructive) { [weak host] _ in
                guard let host else { return }
                presentReportReasons(from: host, sourceRect: sourceRect)
            })
        }
        sheet.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        present(sheet, from: host, sourceRect: sourceRect)
    }

    private func presentTimeoutChoices(from host: UIViewController, sourceRect: CGRect) {
        let sheet = UIAlertController(title: String(localized: "Time out @\(message.author.login)"), message: nil, preferredStyle: .actionSheet)
        let choices: [(String, Int)] = [
            (String(localized: "1 minute"), 60),
            (String(localized: "10 minutes"), 600),
            (String(localized: "1 hour"), 3600),
            (String(localized: "1 day"), 86_400),
        ]
        let userID = message.author.id
        for (title, seconds) in choices {
            sheet.addAction(UIAlertAction(title: title, style: .default) { _ in
                Haptics.notify(.success)
                viewModel.timeoutUser(userID: userID, duration: seconds)
            })
        }
        sheet.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        present(sheet, from: host, sourceRect: sourceRect)
    }

    /// A ban lasts until someone lifts it, so it asks once more before it happens.
    private func confirmBan(from host: UIViewController) {
        let user = message.author
        let alert = UIAlertController(
            title: String(localized: "Ban @\(user.login)?"),
            message: String(localized: "They can't chat here until a moderator unbans them."),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "Ban"), style: .destructive) { _ in
            Haptics.notify(.warning)
            viewModel.banUser(userID: user.id)
        })
        host.present(alert, animated: true)
    }

    private func presentReportReasons(from host: UIViewController, sourceRect: CGRect) {
        let sheet = UIAlertController(
            title: String(localized: "Report @\(message.author.login)"),
            message: String(localized: "Reports are reviewed and this user will be hidden from your chat."),
            preferredStyle: .actionSheet
        )
        for reason in ChatReportReason.allCases {
            sheet.addAction(UIAlertAction(title: reason.title, style: .destructive) { _ in
                Haptics.notify(.success)
                viewModel.report(message: message, reason: reason.rawValue, channelLogin: channelLogin)
            })
        }
        sheet.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        present(sheet, from: host, sourceRect: sourceRect)
    }

    private func present(_ sheet: UIAlertController, from host: UIViewController, sourceRect: CGRect) {
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = host.view
            popover.sourceRect = sourceRect
        }
        host.present(sheet, animated: true)
    }
}
