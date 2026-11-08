import UIKit
import CoreImage.CIFilterBuiltins
import EmbrCore
import MidgarCore

/// Sign-in on the Apple TV with Twitch's device code: scan the QR code with a phone (it opens the activation page
/// with the code filled in) or type the code at twitch.tv/activate, approve, and the TV signs itself in. A code that
/// runs out is replaced on screen without a press.
final class TVSignInViewController: UIViewController {
    /// Called once the TV is signed in, instead of the screen closing itself.
    var onSignedIn: (() -> Void)?

    private let scopes: [String]
    private let titleLabel = UILabel()
    private let stepsLabel = UILabel()
    private let codeLabel = UILabel()
    private let footnoteLabel = UILabel()
    private let qrView = UIImageView()
    private let qrPanel = UIView()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let doneButton = UIButton(configuration: .bordered())
    private var flow: Task<Void, Never>?

    private let transport = AppContainer.shared.transport
    private let clientID = Configuration.current.twitchClientID

    init(scopes: [String] = DeviceAuthorization.scopes) {
        self.scopes = scopes
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        titleLabel.text = String(localized: "Sign in with Twitch")
        titleLabel.font = TVFont.screenTitle
        titleLabel.textColor = Theme.primaryText

        stepsLabel.font = TVFont.body
        stepsLabel.textColor = Theme.secondaryText
        stepsLabel.numberOfLines = 0
        stepsLabel.text = String(localized: "1. Scan the code with your phone's camera, or go to twitch.tv/activate\n2. Check the code matches this one\n3. Choose Authorize")

        codeLabel.font = TVFont.mono(size: 96, weight: .bold)
        codeLabel.textColor = Theme.primaryText
        codeLabel.adjustsFontSizeToFitWidth = true

        footnoteLabel.font = TVFont.cardSubtitle
        footnoteLabel.textColor = Theme.secondaryText
        footnoteLabel.numberOfLines = 0
        footnoteLabel.text = String(localized: "Twitch asks you to approve exactly the permissions you chose. Embr never sees your password.", comment: "Studio sign-in footnote")

        doneButton.configuration?.title = String(localized: "Not Now")
        doneButton.addAction(UIAction { [weak self] _ in self?.close() }, for: .primaryActionTriggered)

        let text = UIStackView(arrangedSubviews: [titleLabel, stepsLabel, codeLabel, footnoteLabel, doneButton])
        text.axis = .vertical
        text.alignment = .leading
        text.spacing = 28
        text.setCustomSpacing(48, after: stepsLabel)
        text.setCustomSpacing(48, after: footnoteLabel)

        qrPanel.backgroundColor = .white
        qrPanel.layer.cornerRadius = 28
        qrPanel.layer.cornerCurve = .continuous
        qrPanel.translatesAutoresizingMaskIntoConstraints = false
        qrView.contentMode = .scaleAspectFit
        qrView.layer.magnificationFilter = .nearest
        qrView.translatesAutoresizingMaskIntoConstraints = false
        qrPanel.addSubview(qrView)
        spinner.color = .darkGray
        spinner.translatesAutoresizingMaskIntoConstraints = false
        qrPanel.addSubview(spinner)

        let row = UIStackView(arrangedSubviews: [text, qrPanel])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 120
        row.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(row)

        NSLayoutConstraint.activate([
            text.widthAnchor.constraint(equalToConstant: 900),
            qrPanel.widthAnchor.constraint(equalToConstant: 520),
            qrPanel.heightAnchor.constraint(equalToConstant: 520),
            qrView.topAnchor.constraint(equalTo: qrPanel.topAnchor, constant: 40),
            qrView.leadingAnchor.constraint(equalTo: qrPanel.leadingAnchor, constant: 40),
            qrView.trailingAnchor.constraint(equalTo: qrPanel.trailingAnchor, constant: -40),
            qrView.bottomAnchor.constraint(equalTo: qrPanel.bottomAnchor, constant: -40),
            spinner.centerXAnchor.constraint(equalTo: qrPanel.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: qrPanel.centerYAnchor),
            row.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            row.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    override var preferredFocusEnvironments: [any UIFocusEnvironment] {
        [doneButton]
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard flow == nil else { return }
        flow = Task { [weak self] in await self?.run() }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        flow?.cancel()
        flow = nil
    }

    private func run() async {
        while !Task.isCancelled {
            showWaiting()
            guard let start = await requestCode() else {
                showFailure(String(localized: "Twitch can't be reached right now. Check the Apple TV's network connection."))
                try? await Task.sleep(for: .seconds(10))
                continue
            }
            show(start)
            switch await poll(start) {
            case .signedIn(let user):
                showSignedIn(user)
                try? await Task.sleep(for: .seconds(1.5))
                if let onSignedIn {
                    onSignedIn()
                } else {
                    dismiss(animated: true)
                }
                return
            case .expired:
                continue
            case .denied:
                showFailure(String(localized: "The sign-in was declined on Twitch. A new code is ready if you want to try again."))
                try? await Task.sleep(for: .seconds(4))
            case .cancelled:
                return
            }
        }
    }

    private enum Outcome {
        case signedIn(AuthenticatedUser)
        case expired
        case denied
        case cancelled
    }

    private func requestCode() async -> DeviceAuthorization.Start? {
        do {
            let response = try await transport.send(DeviceAuthorization.startRequest(clientID: clientID, scopes: scopes))
            return try DeviceAuthorization.decodeStart(response)
        } catch {
            MidgarLog.notice("tv sign-in: device code request failed: \(error)", category: .auth)
            return nil
        }
    }

    private func poll(_ start: DeviceAuthorization.Start) async -> Outcome {
        var interval = start.pollInterval
        let deadline = Date().addingTimeInterval(TimeInterval(start.expiresIn))
        while Date() < deadline {
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return .cancelled }
            let request = DeviceAuthorization.tokenRequest(clientID: clientID, deviceCode: start.deviceCode, scopes: scopes)
            guard let response = try? await transport.send(request) else { continue }
            switch DeviceAuthorization.pollResult(response) {
            case .authorized(let token):
                do {
                    return .signedIn(try await AppContainer.shared.auth.completeDeviceLogin(token))
                } catch {
                    MidgarLog.error("tv sign-in: token rejected: \(error)", category: .auth)
                    return .expired
                }
            case .pending:
                continue
            case .slowDown:
                interval += 5
            case .expired:
                return .expired
            case .denied:
                return .denied
            case .failed(let message):
                MidgarLog.notice("tv sign-in: poll failed: \(message)", category: .auth)
            }
        }
        return .expired
    }

    private func showWaiting() {
        spinner.startAnimating()
        qrView.image = nil
        codeLabel.text = "––––-––––"
    }

    private func show(_ start: DeviceAuthorization.Start) {
        spinner.stopAnimating()
        qrView.image = Self.qrCode(for: start.verificationURI)
        qrView.accessibilityLabel = String(localized: "QR code that opens Twitch's activation page")
        let code = DeviceAuthorization.displayCode(start.userCode)
        codeLabel.text = code
        codeLabel.accessibilityLabel = String(localized: "Code: \(code.map(String.init).joined(separator: " "))")
        UIAccessibility.post(notification: .layoutChanged, argument: codeLabel)
    }

    private func showSignedIn(_ user: AuthenticatedUser) {
        titleLabel.text = String(localized: "Signed in as \(user.login)")
        stepsLabel.text = String(localized: "Opening Studio…", comment: "Studio sign-in done")
        codeLabel.text = "✓"
        UIAccessibility.post(notification: .announcement, argument: titleLabel.text)
    }

    private func showFailure(_ message: String) {
        spinner.stopAnimating()
        stepsLabel.text = message
    }

    private func close() {
        if let navigation = navigationController, navigation.viewControllers.first !== self {
            navigation.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }

    private static func qrCode(for url: URL) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
