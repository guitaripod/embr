import UIKit
import EmbrCore

/// Settings > Chat > Highlights: what makes a message stand out (mentions of the viewer, their words and phrases, the
/// people they chose) and whether a standing-out message also plays a haptic or a sound.
@MainActor
final class HighlightsViewController: UIViewController {
    private enum Section: Int, CaseIterable {
        case alerts
        case words
        case users
    }

    private enum Item: Hashable {
        case mentions
        case haptic
        case sound
        case word(String)
        case addWord
        case user(String)
        case addUser
    }

    private let store: SettingsStore
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!

    init(store: SettingsStore = .shared) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
        title = String(localized: "Highlights")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        navigationItem.largeTitleDisplayMode = .never
        setUpCollectionView()
        setUpDataSource()
        applySnapshot(animated: false)
    }

    private func setUpCollectionView() {
        var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        config.backgroundColor = Theme.background
        config.headerMode = .supplementary
        config.footerMode = .supplementary
        config.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
            guard let self, let item = self.dataSource.itemIdentifier(for: indexPath) else { return nil }
            switch item {
            case .word(let word):
                return Self.deleteAction { [weak self] in self?.removeWord(word) }
            case .user(let login):
                return Self.deleteAction { [weak self] in self?.removeUser(login) }
            default:
                return nil
            }
        }
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
    }

    private static func deleteAction(_ perform: @escaping () -> Void) -> UISwipeActionsConfiguration {
        let delete = UIContextualAction(style: .destructive, title: String(localized: "Delete")) { _, _, completion in
            perform()
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    private func setUpDataSource() {
        let row = UICollectionView.CellRegistration<UICollectionViewListCell, Item> { [weak self] cell, _, item in
            self?.configure(cell, item)
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { collectionView, indexPath, item in
            collectionView.dequeueConfiguredReusableCell(using: row, for: indexPath, item: item)
        }
        let header = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(elementKind: UICollectionView.elementKindSectionHeader) { cell, _, indexPath in
            var content = UIListContentConfiguration.groupedHeader()
            content.text = Section(rawValue: indexPath.section).flatMap(Self.header)
            cell.contentConfiguration = content
        }
        let footer = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(elementKind: UICollectionView.elementKindSectionFooter) { cell, _, indexPath in
            var content = UIListContentConfiguration.groupedFooter()
            content.text = Section(rawValue: indexPath.section).flatMap(Self.footer)
            cell.contentConfiguration = content
        }
        dataSource.supplementaryViewProvider = { collectionView, kind, indexPath in
            kind == UICollectionView.elementKindSectionHeader
                ? collectionView.dequeueConfiguredReusableSupplementary(using: header, for: indexPath)
                : collectionView.dequeueConfiguredReusableSupplementary(using: footer, for: indexPath)
        }
    }

    private static func header(_ section: Section) -> String? {
        switch section {
        case .alerts: nil
        case .words: String(localized: "Words and Phrases")
        case .users: String(localized: "People")
        }
    }

    private static func footer(_ section: Section) -> String? {
        switch section {
        case .alerts: String(localized: "Messages that mention you, contain your words or come from your people stand out in chat. The haptic and sound play while that chat is on screen.")
        case .words: String(localized: "A single word matches on its own, a phrase anywhere in a message. Case and accents don't matter.")
        case .users: String(localized: "You can also tap a name in chat and choose Highlight.")
        }
    }

    private func configure(_ cell: UICollectionViewListCell, _ item: Item) {
        var content = cell.defaultContentConfiguration()
        cell.accessories = []
        cell.backgroundConfiguration = Theme.groupedRowBackground()
        let settings = store.current
        switch item {
        case .mentions:
            toggle(cell, &content, String(localized: "Mentions of Me"), symbol: "at", isOn: settings.highlightMentions) { $0.highlightMentions = $1 }
        case .haptic:
            toggle(cell, &content, String(localized: "Haptic"), symbol: "iphone.radiowaves.left.and.right", isOn: settings.highlightHapticEnabled) { $0.highlightHaptic = $1 }
        case .sound:
            toggle(cell, &content, String(localized: "Sound"), symbol: "speaker.wave.2", isOn: settings.highlightSoundEnabled) { $0.highlightSound = $1 }
        case .word(let word):
            content.text = word
            content.image = UIImage(systemName: "highlighter")
            cell.contentConfiguration = content
        case .user(let login):
            content.text = login
            content.image = UIImage(systemName: "person.fill")
            cell.contentConfiguration = content
        case .addWord:
            content.text = String(localized: "Add Word or Phrase")
            content.image = UIImage(systemName: "plus.circle.fill")
            content.textProperties.color = Theme.accent
            cell.contentConfiguration = content
        case .addUser:
            content.text = String(localized: "Add Person")
            content.image = UIImage(systemName: "plus.circle.fill")
            content.textProperties.color = Theme.accent
            cell.contentConfiguration = content
        }
    }

    private func toggle(_ cell: UICollectionViewListCell, _ content: inout UIListContentConfiguration, _ title: String, symbol: String, isOn: Bool, set: @escaping (inout Settings, Bool) -> Void) {
        content.text = title
        content.image = UIImage(systemName: symbol)
        cell.contentConfiguration = content
        let control = UISwitch()
        control.isOn = isOn
        control.onTintColor = Theme.accent
        control.accessibilityLabel = title
        control.addAction(UIAction { [weak self] action in
            guard let self, let control = action.sender as? UISwitch else { return }
            Haptics.selection()
            self.store.update { set(&$0, control.isOn) }
        }, for: .valueChanged)
        cell.accessories = [.customView(configuration: .init(customView: control, placement: .trailing()))]
    }

    private func applySnapshot(animated: Bool) {
        let settings = store.current
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections(Section.allCases)
        snapshot.appendItems([.mentions, .haptic, .sound], toSection: .alerts)
        snapshot.appendItems(settings.highlightWordList.map(Item.word) + [.addWord], toSection: .words)
        snapshot.appendItems(settings.highlightUserList.map(Item.user) + [.addUser], toSection: .users)
        dataSource.apply(snapshot, animatingDifferences: animated)
    }

    private func promptForWord() {
        prompt(
            title: String(localized: "Highlight a Word"),
            message: String(localized: "Messages containing this word or phrase will stand out in chat."),
            placeholder: String(localized: "Word or phrase")
        ) { [weak self] text in self?.addWord(text) }
    }

    private func promptForUser() {
        prompt(
            title: String(localized: "Highlight a Person"),
            message: String(localized: "Everything this person says will stand out in chat."),
            placeholder: String(localized: "Twitch username")
        ) { [weak self] text in self?.addUser(text) }
    }

    private func prompt(title: String, message: String, placeholder: String, add: @escaping (String) -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = placeholder
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.returnKeyType = .done
        }
        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "Add"), style: .default) { [weak alert] _ in
            add(alert?.textFields?.first?.text ?? "")
        })
        present(alert, animated: true)
    }

    private func addWord(_ raw: String) {
        let word = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }
        let words = store.current.highlightWordList
        guard !words.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) else {
            Haptics.notify(.warning)
            return
        }
        Haptics.selection()
        store.update { $0.highlightWords = (words + [word]).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending } }
        applySnapshot(animated: true)
    }

    private func addUser(_ raw: String) {
        let login = raw.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "@")).lowercased()
        guard !login.isEmpty else { return }
        let users = store.current.highlightUserList
        guard !users.contains(login) else {
            Haptics.notify(.warning)
            return
        }
        Haptics.selection()
        store.update { $0.highlightUsers = (users + [login]).sorted() }
        applySnapshot(animated: true)
    }

    private func removeWord(_ word: String) {
        Haptics.selection()
        store.update { $0.highlightWords = $0.highlightWordList.filter { $0 != word } }
        applySnapshot(animated: true)
    }

    private func removeUser(_ login: String) {
        Haptics.selection()
        store.update { $0.highlightUsers = $0.highlightUserList.filter { $0 != login } }
        applySnapshot(animated: true)
    }
}

extension HighlightsViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        switch dataSource.itemIdentifier(for: indexPath) {
        case .addWord, .addUser: true
        default: false
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        switch dataSource.itemIdentifier(for: indexPath) {
        case .addWord: promptForWord()
        case .addUser: promptForUser()
        default: break
        }
    }
}
