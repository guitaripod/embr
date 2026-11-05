import UIKit

/// A centred message for a screen with nothing to show: loading, empty or failed, with an optional button.
final class TVStateView: UIView {
    private let spinner = UIActivityIndicatorView(style: .large)
    private let symbolView = UIImageView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let button = UIButton(configuration: .bordered())
    private var action: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        symbolView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 80, weight: .regular)
        symbolView.tintColor = Theme.secondaryText
        symbolView.contentMode = .scaleAspectFit

        titleLabel.font = TVFont.bold(.title3)
        titleLabel.textColor = Theme.primaryText
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        messageLabel.font = TVFont.body
        messageLabel.textColor = Theme.secondaryText
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0

        button.addAction(UIAction { [weak self] _ in self?.action?() }, for: .primaryActionTriggered)

        let stack = UIStackView(arrangedSubviews: [spinner, symbolView, titleLabel, messageLabel, button])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 24
        stack.setCustomSpacing(48, after: messageLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 1000),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var preferredFocusEnvironments: [any UIFocusEnvironment] {
        button.isHidden ? [] : [button]
    }

    func showLoading() {
        spinner.startAnimating()
        spinner.isHidden = false
        symbolView.isHidden = true
        titleLabel.isHidden = true
        messageLabel.isHidden = true
        button.isHidden = true
        isHidden = false
    }

    func show(symbol: String, title: String, message: String?, buttonTitle: String? = nil, action: (() -> Void)? = nil) {
        spinner.stopAnimating()
        spinner.isHidden = true
        symbolView.image = UIImage(systemName: symbol)
        symbolView.isHidden = false
        titleLabel.text = title
        titleLabel.isHidden = false
        messageLabel.text = message
        messageLabel.isHidden = message == nil
        button.configuration?.title = buttonTitle
        button.isHidden = buttonTitle == nil
        self.action = action
        isHidden = false
        setNeedsFocusUpdate()
    }

    func hide() {
        spinner.stopAnimating()
        isHidden = true
    }
}
