import APIKit
import Continuum
import DeepDiff
import UIKit

final class BuildsListViewController: UIViewController, Storyboardable, UITableViewDataSource, UITableViewDelegate {

    struct Dependency {
        let viewModel: BuildsListViewModel
    }

    static func makeFromStoryboard(_ dependency: Dependency) -> BuildsListViewController {
        let vc = BuildsListViewController.unsafeMakeFromStoryboard()
        vc.viewModel = dependency.viewModel
        return vc
    }

    private var viewModel: BuildsListViewModel!

    // animation dispatch after
    private var workItem: DispatchWorkItem?

    @IBOutlet private weak var triggerBuildButton: UIButton! {
        didSet {
            triggerBuildButton.layer.cornerRadius = triggerBuildButton.frame.width / 2
        }
    }

    @IBOutlet private weak var bitriseYmlButton: UIButton! {
        didSet {
            bitriseYmlButton.layer.cornerRadius = bitriseYmlButton.frame.width / 2
        }
    }

    @IBOutlet private weak var tableView: UITableView! {
        didSet {
            tableView.dataSource = self
            tableView.delegate = self
        }
    }

    private lazy var refreshControl: UIRefreshControl = {
        let refreshControl = UIRefreshControl()
        refreshControl.attributedTitle = NSAttributedString(string: "Pull to refresh")
        refreshControl.addTarget(self, action: #selector(pullToRefresh), for: .valueChanged)
        self.tableView.addSubview(refreshControl)
        return refreshControl
    }()

    private let disposeBag = NotificationCenterContinuum.Bag()

    // MARK: LifeCycle

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = viewModel.navigationBarTitle

        viewModel.viewDidLoad()

        notificationCenter.continuum
            .observe(viewModel.alertMessage, on: .main) { [weak self] msg in
                if !msg.isEmpty { // skip initial value
                    self?.alert(msg)
                }
            }
            .disposed(by: disposeBag)

        notificationCenter.continuum
            .observe(viewModel.dataChanges, on: .main) { [weak self] changes in
                if !changes.isEmpty { // skip initial value
                    self?.tableView.reload(changes: changes, completion: { _ in })
                }
            }
            .disposed(by: disposeBag)

        notificationCenter.continuum
            .observe(viewModel.isNewDataIndicatorHidden, on: .main) { [weak self] isHidden in
                guard let me = self else { return }

                if isHidden {
                    me.refreshControl.endRefreshing()
                } else {
                    me.refreshControl.beginRefreshing()
                }
            }
            .disposed(by: disposeBag)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        viewModel.viewWillDisappear()
    }

    // MARK: IBAction

    @IBAction func bitriseYmlButtonTap() {
        let vm = BitriseYmlViewModel(appSlug: viewModel.appSlug, appName: viewModel.navigationBarTitle)
        let vc = BitriseYmlViewController(viewModel: vm)

        vc.modalPresentationStyle = .overCurrentContext

        navigationController?.present(vc, animated: true, completion: nil)
    }

    @IBAction func triggerBuildButtonTap() {
        Haptic.generate(.light)

        let logicStore = TriggerBuildLogicStore(appSlug: viewModel.appSlug)
        let vc = TriggerBuildViewController.makeFromStoryboard(logicStore)

        vc.modalPresentationStyle = .overCurrentContext

        navigationController?.present(vc, animated: true, completion: nil)

        notificationCenter.continuum
            .observe(logicStore.buildDidTriggerRelay) { [weak viewModel] trigger in
                if trigger != nil {
                    viewModel?.triggerPullToRefresh()
                }
            }
            .disposed(by: disposeBag)

    }

    @objc private func pullToRefresh() {
        viewModel.triggerPullToRefresh()
    }

    // MARK: UITableViewDataSource & UITableViewDelegate

    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return viewModel.builds.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "BuildCell") as! BuildCell
        cell.configure(viewModel.builds[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }

    func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        actionSheet.addAction(UIAlertAction(title: "Abort", style: .default, handler: { [weak self] _ in
            self?.viewModel.sendAbortRequest(indexPath: indexPath)
        }))

        actionSheet.addAction(UIAlertAction(title: "Set Notification", style: .default, handler: { [weak self] _ in
            self?.viewModel.reserveNotification(indexPath: indexPath)
        }))

        actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))

        present(actionSheet, animated: true, completion: nil)
    }

    private var alphaChangingViews: [UIView] {
        return [triggerBuildButton, bitriseYmlButton]
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        alphaChangingViews.forEach { $0.alpha = 0.1 }
    }

    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {

        self.workItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            UIView.animate(withDuration: 0.3) {
                self?.alphaChangingViews.forEach { $0.alpha = 1.0 }
            }
        }

        self.workItem = workItem

        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.5,
                                      execute: workItem)
    }
}
