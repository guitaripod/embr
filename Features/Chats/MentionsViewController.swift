import UIKit
import Combine
import EmbrCore

/// Everything that stood out for the viewer in any open chat since the Chats tab opened, newest first, each with the
/// chat it came from. Choosing one brings that chat to the front.
@MainActor
final class MentionsViewController: UIViewController {
    private let model: ChatsModel
    private let choose: (ChatsModel.Mention) -> Void
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, ChatsModel.Mention>!
    private let emptyLabel = UILabel()
    private var cancellables = Set<AnyCancellable>()

    init(model: ChatsModel, choose: @escaping (ChatsModel.Mention) -> Void) {
        self.model = model
        self.choose = choose
        super.init(nibName: nil, bundle: nil)
        title = String(localized: "Mentions")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: String(localized: "Clear"), primaryAction: UIAction { [weak self] _ in
            self?.model.clearMentions()
        })
        setUpList()
        emptyLabel.text = String(localized: "Messages that mention you, contain your highlight words or come from your highlighted people show up here from every open chat.")
        emptyLabel.font = .preferredFont(forTextStyle: .subheadline)
        emptyLabel.adjustsFontForContentSizeCategory = true
        emptyLabel.textColor = Theme.secondaryText
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.readableContentGuide.leadingAnchor, constant: 16),
            emptyLabel.trailingAnchor.constraint(equalTo: view.readableContentGuide.trailingAnchor, constant: -16),
        ])
        model.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.apply() }
            .store(in: &cancellables)
        apply()
    }

    private func setUpList() {
        var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        config.backgroundColor = Theme.background
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: StreamListLayout.readableList(using: config))
        collectionView.backgroundColor = Theme.background
        collectionView.delegate = self
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        let row = UICollectionView.CellRegistration<UICollectionViewListCell, ChatsModel.Mention> { cell, _, mention in
            let message = mention.row.message
            var content = UIListContentConfiguration.subtitleCell()
            let name = NSMutableAttributedString(string: message.author.displayName + ": ", attributes: [
                .font: UIFont.preferredFont(forTextStyle: .body).bold,
                .foregroundColor: Theme.readableUsernameColor(message.author.color),
            ])
            name.append(NSAttributedString(string: message.plainText, attributes: [
                .font: UIFont.preferredFont(forTextStyle: .body),
                .foregroundColor: Theme.primaryText,
            ]))
            content.attributedText = name
            content.secondaryText = "\(mention.channel.name) · \(mention.arrived.formatted(date: .omitted, time: .shortened))"
            content.secondaryTextProperties.color = Theme.secondaryText
            content.textToSecondaryTextVerticalPadding = 4
            cell.contentConfiguration = content
            cell.backgroundConfiguration = Theme.groupedRowBackground()
            cell.accessories = [.disclosureIndicator()]
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { collectionView, indexPath, mention in
            collectionView.dequeueConfiguredReusableCell(using: row, for: indexPath, item: mention)
        }
    }

    private func apply() {
        var snapshot = NSDiffableDataSourceSnapshot<Int, ChatsModel.Mention>()
        snapshot.appendSections([0])
        snapshot.appendItems(model.mentions, toSection: 0)
        dataSource.apply(snapshot, animatingDifferences: true)
        emptyLabel.isHidden = !model.mentions.isEmpty
        navigationItem.leftBarButtonItem?.isEnabled = !model.mentions.isEmpty
        model.markMentionsSeen()
    }
}

extension MentionsViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let mention = dataSource.itemIdentifier(for: indexPath) else { return }
        Haptics.selection()
        choose(mention)
        dismiss(animated: true)
    }
}

private extension UIFont {
    var bold: UIFont {
        fontDescriptor.withSymbolicTraits(.traitBold).map { UIFont(descriptor: $0, size: 0) } ?? self
    }
}
