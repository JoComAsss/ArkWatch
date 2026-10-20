import Foundation
import Combine

final class AppModel: ObservableObject {
    @Published private(set) var accounts: [Account] = []
    @Published var activeID: String? {
        didSet {
            UserDefaults.standard.set(activeID, forKey: "activeAccountID")
            refresh(force: true)
            recomputeTitle()
        }
    }

    @Published private(set) var snapshot: AFPSnapshot?
    @Published private(set) var plan: PlanInfo?
    @Published private(set) var usageRows: [UsageRow] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var statusTitle: String = "Ark"
    /// 正在检测套餐开通状态
    @Published private(set) var isCheckingPlan = false
    /// 菜单栏小字说明（剩余 / 已用 / 剩余 AFP），为空时不显示
    @Published private(set) var statusLabel: String = ""
    /// 菜单栏主数值
    @Published private(set) var statusValue: String = "⚙"

    /// 本机查看的套餐（不改变实际订阅）
    @Published var selectedPlanID: String? {
        didSet {
            UserDefaults.standard.set(selectedPlanID, forKey: "selectedPlanID")
            detectPlan()
            recomputeTitle()
        }
    }

    let store = AccountStore()
    let prefs = Preferences.shared
    private var timer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    var activeAccount: Account? {
        accounts.first { $0.id == activeID }
    }

    init() {
        accounts = store.accounts
        selectedPlanID = UserDefaults.standard.string(forKey: "selectedPlanID")
        let saved = UserDefaults.standard.string(forKey: "activeAccountID")
        activeID = accounts.contains(where: { $0.id == saved }) ? saved : accounts.first?.id

        prefs.$refreshSeconds
            .sink { [weak self] _ in self?.restartTimer() }
            .store(in: &cancellables)
        prefs.$displayMode
            // @Published 在 willSet 阶段发事件，切到主队列下一轮再读新值
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.recomputeTitle()
            }
            .store(in: &cancellables)

        prefs.$menuBarWindow
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.recomputeTitle()
            }
            .store(in: &cancellables)

        restartTimer()
        recomputeTitle()
        if activeAccount != nil { refresh(force: true) }
    }

    /// 当前查看的套餐是否处于已开通状态
    var isSelectedPlanOpened: Bool {
        guard plan != nil else { return false }
        guard let selectedPlanID else { return true }
        return selectedPlanID == livePlanID
    }

    /// 套餐生效时间范围，未开通返回「无」
    var planRangeText: String {
        guard let plan, let start = plan.startTime, let end = plan.endTime,
              start.count >= 10, end.count >= 10 else { return "无" }
        return "\(String(start.prefix(10))) ~ \(String(end.prefix(10)))"
    }

    // MARK: 套餐检测

    /// 打开套餐页时主动检测一次开通状态
    func detectPlan() {
        guard !isCheckingPlan else { return }
        guard let account = activeAccount, !account.ak.isEmpty,
              let sk = store.secretKey(for: account), !sk.isEmpty else {
            isCheckingPlan = false
            return
        }
        isCheckingPlan = true
        let client = ArkClient(ak: account.ak, sk: sk)
        Task { [weak self] in
            var info: PlanInfo?
            do { info = try await client.fetchActivePlan() } catch { info = nil }
            await MainActor.run {
                guard let self else { return }
                if let info { self.plan = info }
                self.isCheckingPlan = false
                self.recomputeTitle()
            }
        }
    }

    // MARK: 套餐

    /// 实际已开通的套餐（来自接口）
    var livePlanID: String? {
        guard let plan else { return nil }
        let prefix = plan.plan == "CodingPlan" ? "coding" : "agent"
        return "\(prefix)-\(plan.planType.lowercased())"
    }

    var selectedTier: PlanTier? {
        PlanCatalog.tier(id: selectedPlanID ?? livePlanID)
    }

    /// 面板/设置里展示的套餐名
    var selectedPlanLabel: String {
        guard plan != nil || selectedPlanID != nil else { return "未绑定" }
        if let tier = selectedTier {
            return "\(tier.family == "CodingPlan" ? "Coding" : "Agent") \(tier.name)"
        }
        if let plan {
            return "\(plan.plan == "CodingPlan" ? "Coding" : "Agent") \(plan.planType)"
        }
        return "未绑定"
    }

    // MARK: 账号管理

    func reloadAccounts() {
        store.load()
        accounts = store.accounts
        if !accounts.contains(where: { $0.id == activeID }) {
            activeID = accounts.first?.id
        }
        recomputeTitle()
    }

    @discardableResult
    func addAccount(name: String, ak: String, sk: String, note: String) -> Account? {
        guard let account = store.add(name: name, ak: ak, sk: sk, note: note) else { return nil }
        reloadAccounts()
        activeID = account.id
        return account
    }

    func updateAccount(_ account: Account, sk: String?) {
        store.update(account, sk: sk)
        reloadAccounts()
        if account.id == activeID { refresh(force: true) }
    }

    func deleteAccount(_ account: Account) {
        store.remove(account)
        reloadAccounts()
    }

    /// 校验一组 AK/SK 是否可用，返回可读结果
    func verify(ak: String, sk: String) async -> String {
        let client = ArkClient(ak: ak, sk: sk)
        do {
            let plan = try await client.fetchActivePlan()
            if let plan {
                return "连接成功 · \(plan.plan) \(plan.planType) · \(plan.status)"
            }
            return "连接成功，但该账号没有生效中的 Agent/Coding Plan 套餐"
        } catch {
            return "连接失败：\(error.localizedDescription)"
        }
    }

    // MARK: 数据刷新

    func refresh(force: Bool = false) {
        guard !isLoading else { return }
        guard let account = activeAccount else { return }
        guard let sk = store.secretKey(for: account), !sk.isEmpty else {
            errorMessage = "账号「\(account.name)」缺少 Secret Key，请重新编辑账号"
            recomputeTitle()
            return
        }

        isLoading = true
        let client = ArkClient(ak: account.ak, sk: sk)
        let accountID = account.id

        Task { [weak self] in
            guard let self else { return }
            var errors: [String] = []
            var newPlan: PlanInfo?
            var newSnapshot: AFPSnapshot?
            var newRows: [UsageRow] = []

            do {
                newPlan = try await client.fetchActivePlan()
            } catch {
                errors.append(error.localizedDescription)
            }

            if newPlan == nil || newPlan?.plan == "AgentPlan" {
                do {
                    newSnapshot = try await client.fetchAFP()
                    if newPlan == nil {
                        newPlan = PlanInfo(plan: "AgentPlan",
                                           planType: newSnapshot?.planType ?? "-",
                                           status: "Running",
                                           startTime: nil,
                                           endTime: nil,
                                           autoRenew: nil)
                    }
                } catch {
                    errors.append(error.localizedDescription)
                }
            }

            do {
                newRows = try await client.fetchUsage()
            } catch {
                errors.append(error.localizedDescription)
            }

            let collectedErrors = errors
            await MainActor.run {
                // 账号在刷新过程中被切换则丢弃结果
                guard accountID == self.activeID else {
                    self.isLoading = false
                    return
                }
                if newSnapshot != nil { self.snapshot = newSnapshot }
                if newPlan != nil { self.plan = newPlan }
                if !newRows.isEmpty || collectedErrors.isEmpty { self.usageRows = newRows }
                self.errorMessage = collectedErrors.isEmpty ? nil : collectedErrors.joined(separator: "\n")
                self.lastUpdated = Date()
                self.isLoading = false
                self.recomputeTitle()
            }
        }
    }

    // MARK: 菜单栏标题

    private var displayLabel: String {
        switch prefs.displayMode {
        case "usedPercent": return "已用"
        case "remainingAFP": return "剩余 AFP"
        default: return "剩余"
        }
    }

    private func recomputeTitle() {
        statusLabel = ""

        guard activeAccount != nil else {
            statusValue = "⚙"
            statusTitle = "Ark ⚙"
            return
        }
        if isLoading && snapshot == nil {
            statusValue = "…"
            statusTitle = "Ark …"
            return
        }
        if !isSelectedPlanOpened {
            statusValue = "无"
            statusTitle = "Ark 无"
            return
        }

        guard let snapshot else {
            statusValue = errorMessage == nil ? "—" : "⚠"
            statusTitle = "Ark " + statusValue
            return
        }

        let window = snapshot.window(prefs.menuBarWindow)
            ?? snapshot.window("monthly")
            ?? snapshot.window("weekly")
            ?? snapshot.windows.first
        guard let window, window.hasQuota else {
            statusValue = "—"
            statusTitle = "Ark —"
            return
        }

        switch prefs.displayMode {
        case "usedPercent":
            statusValue = String(format: "%.1f%%", window.ratio * 100)
        case "remainingAFP":
            statusValue = Self.formatAFP(window.remaining)
        default:
            statusValue = String(format: "%.1f%%", (1 - window.ratio) * 100)
        }
        statusLabel = displayLabel
        statusTitle = statusLabel + " " + statusValue
    }

    // MARK: 定时器

    private func restartTimer() {
        timer?.invalidate()
        let interval = TimeInterval(max(15, prefs.refreshSeconds))
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer?.tolerance = 5
    }

    // MARK: 演示数据（仅用于 --render 预览）

    func loadDemoData() {
        let now = Date()
        snapshot = AFPSnapshot(planType: "Small", windows: [
            AFPWindow(id: "fiveHour", title: "5 小时", used: 812, quota: 2000,
                      resetTime: now.addingTimeInterval(2.4 * 3600), startTime: now.addingTimeInterval(-2.6 * 3600)),
            AFPWindow(id: "daily", title: "今日", used: 1050, quota: 10000,
                      resetTime: now.addingTimeInterval(5.6 * 3600), startTime: now.addingTimeInterval(-18 * 3600)),
            AFPWindow(id: "weekly", title: "本周", used: 3120, quota: 7000,
                      resetTime: now.addingTimeInterval(2.2 * 86400), startTime: now.addingTimeInterval(-4.8 * 86400)),
            AFPWindow(id: "monthly", title: "本月", used: 9480, quota: 20000,
                      resetTime: now.addingTimeInterval(18.3 * 86400), startTime: now.addingTimeInterval(-11.7 * 86400))
        ])
        plan = PlanInfo(plan: "AgentPlan", planType: "Small", status: "Running",
                        startTime: "2026-10-01T00:00:00+08:00",
                        endTime: "2026-11-19T23:59:59+08:00",
                        autoRenew: true)
        usageRows = [
            UsageRow(model: "deepseek-v4.1-flash-economy", unit: "Tokens", billingType: "WithinPlan", usage: 1_284_000, time: now),
            UsageRow(model: "doubao-seed-evolving", unit: "Tokens", billingType: "WithinPlan", usage: 326_500, time: now),
            UsageRow(model: "deepseek-v4.1-flash", unit: "Tokens", billingType: "WithinPlan", usage: 112_300, time: now),
            UsageRow(model: "doubao-seed-2.1-pro", unit: "Tokens", billingType: "OutsideOfPlan", usage: 18_400, time: now)
        ]
        lastUpdated = now
    }

    // MARK: 展示辅助

    static func formatAFP(_ value: Double) -> String {
        if value >= 1_000_000 { return String(format: "%.2fM", value / 1_000_000) }
        if value >= 10_000 { return String(format: "%.1fk", value / 1000) }
        if value >= 100 { return String(format: "%.0f", value) }
        if value >= 1 { return String(format: "%.1f", value) }
        return String(format: "%.2f", value)
    }

    static func formatTokens(_ value: Double) -> String {
        if value >= 1_000_000_000 { return String(format: "%.2fB", value / 1_000_000_000) }
        if value >= 1_000_000 { return String(format: "%.2fM", value / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", value / 1000) }
        return String(format: "%.0f", value)
    }
}
