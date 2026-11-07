import UIKit

/// A Settings page laid out like the Apple TV's own Settings: the list on the right and, on the left, a picture with
/// the name and description of what is in focus. Subclasses fill the table and the hero.
class TVSettingsPageViewController: UIViewController {
    let hero = TVSettingsHeroView()
    let tableView = UITableView(frame: .zero, style: .grouped)

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        hero.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hero)

        tableView.backgroundColor = .clear
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.remembersLastFocusedIndexPath = true
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.contentInset = UIEdgeInsets(top: TVMetrics.tabBarClearance, left: 0, bottom: 80, right: 0)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            hero.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: TVMetrics.horizontalInset + 40),
            hero.widthAnchor.constraint(equalToConstant: 640),
            hero.topAnchor.constraint(equalTo: view.topAnchor, constant: TVMetrics.tabBarClearance),
            hero.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -TVMetrics.tabBarClearance / 2),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: hero.trailingAnchor, constant: 80),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -TVMetrics.horizontalInset),
        ])
        setContentScrollView(tableView, for: .top)
    }

    override var preferredFocusEnvironments: [any UIFocusEnvironment] {
        [tableView]
    }
}
