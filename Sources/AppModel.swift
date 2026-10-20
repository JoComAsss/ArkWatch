import Foundation
import Combine

final class AppModel: ObservableObject {
    @Published private(set) var accounts: [Account] = []
    @Published private(set) var session: Session?
    @Published private(set) var snapshot: AFPSnapshot?
    @Published private(set) var plan: PlanInfo?
    @Published private(set) var usageRows: [UsageRow] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var statusTitle: String = "Ark"

    let store = AccountStore()
    let prefs = Preferences.shared
    private var timer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    var isLoggedIn: Bool { session != nil }

    var activeAccount: Account? {
        guard let session else { return nil }
        return accounts.first { $0.phone == session.phone }
    }

    init() {
        accounts = store.accounts
        if let restored = SessionStore.load() {
            session = restored
            store.ensureAccount(phone: restored.phone)
            accounts = store.accounts
        }

        prefs.$refreshSeconds
            .sink { [weak self] _ in self?.restartTimer() }
            .store(in: &cancellables)
        prefs.$displayMode
            .sink { [weak self] _ in self?.recomputeTitle() }
            .store(in: &cancellables)

        restartTimer()
        recomputeTitle()
        if session != nil { refresh(force: true) }
    }

    // MARK: 登录 / 退出

    /// 验证码校验通过后建立会话；会话写入钥匙串，重启后自动恢复，直到用户主动退出
    @discardableResult
    func login(phone: String) -> Account {
        let account = store.ensureAccount(phone: phone)
        accounts = store.accounts
        let newSession = Session(phone: phone, token: UUID().uuidString, loginAt: Date())
        session = newSession
        SessionStore.save(newSession)
        errorMessage = nil
        recomputeTitle()
        refresh(force: true)
        return account
    }

    /// 退出登录：清除会话（账号与 AK/SK 仍保留，下次验证码登录后可继续使用）
    func logout() {
        SessionStore.clear()
        session = nil
        snapshot = nil
        plan = nil
        usageRows = []
        errorMessage = nil
        lastUpdated = nil
        isLoading = false
        recomputeTitle()
    }

    // MARK: 账号信息

    func reloadAccounts() {
        store.load()
        accounts = store.accounts
        recomputeTitle()
    }

    /// 绑定 / 更新 AK（SK 为空表示不修改）
    func bindCredentials(phone: String, ak: String, sk: String, name: String, note: String) {
        store.ensureAccount(phone: phone)
        guard var account = store.account(phone: phone) else { return }
        account.ak = ak.trimmingCharacters(in: .whitespacesAndNewlines)
        account.name = name.isEmpty ? account.maskedPhone : name
        account.note = note
        store.update(account, sk: sk.isEmpty ? nil : sk)
        reloadAccounts()
        if session?.phone == phone { refresh(force: true) }
    }

    func updateAccount(_ account: Account, sk: String?) {
        store.update(account, sk: sk)
        reloadAccounts()
        if account.phone == session?.phone { refresh(force: true) }
    }

    func deleteAccount(_ account: Account) {
        store.remove(account)
        reloadAccounts()
        if account.phone == session?.phone { refresh(force: true) }
    }

    func secretKey(for account: Account) -> String? {
        store.secretKey(for: account)
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
        guard let session, let account = activeAccount else { return }

        guard account.hasCredentials else {
            errorMessage = "尚未绑定 AK/SK，请在设置中完成绑定后即可读取用量"
            recomputeTitle()
            return
        }
        guard let sk = store.secretKey(for: account), !sk.isEmpty else {
            errorMessage = "该账号缺少 Secret Key，请在设置中重新绑定"
            recomputeTitle()
            return
        }

        isLoading = true
        let client = ArkClient(ak: account.ak, sk: sk)
        let loginToken = session.token

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
                // 期间退出登录或切换账号则丢弃结果
                guard self.session?.token == loginToken else {
                    self.isLoading = false
                    return
                }
                if let snapshot = newSnapshot { self.snapshot = snapshot }
                if let plan = newPlan { self.plan = plan }
                if !newRows.isEmpty || collectedErrors.isEmpty { self.usageRows = newRows }
                self.errorMessage = collectedErrors.isEmpty ? nil : collectedErrors.joined(separator: "\n")
                self.lastUpdated = Date()
                self.isLoading = false
                self.recomputeTitle()
            }
        }
    }

    // MARK: 菜单栏标题

    private func recomputeTitle() {
        guard session != nil else {
            statusTitle = "Ark 登录"
            return
        }
        guard let account = activeAccount, account.hasCredentials else {
            statusTitle = "Ark ⚙"
            return
        }
        if isLoading && snapshot == nil {
            statusTitle = "Ark …"
            return
        }
        guard let snapshot else {
            statusTitle = errorMessage == nil ? "Ark —" : "Ark ⚠"
            return
        }

        let window = snapshot.window("monthly")
            ?? snapshot.window("weekly")
            ?? snapshot.windows.first
        guard let window, window.hasQuota else {
            statusTitle = "Ark —"
            return
        }

        switch prefs.displayMode {
        case "usedPercent":
            statusTitle = String(format: "%.0f%%", window.ratio * 100)
        case "remainingAFP":
            statusTitle = Self.formatAFP(window.remaining)
        default:
            statusTitle = String(format: "%.0f%%", (1 - window.ratio) * 100)
        }
    }

    // MARK: 定时器

    private func restartTimer() {
        timer?.invalidate()
        let interval = TimeInterval(max(15, prefs.refreshSeconds))
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.session != nil else { return }
                self.refresh()
            }
        }
        timer?.tolerance = 5
    }

    // MARK: 演示数据（仅用于 --render 预览）

    func loadDemoData() {
        let now = Date()
        session = Session(phone: "13800008000", token: "demo", loginAt: now)
        accounts = [Account(phone: "13800008000", name: "个人", ak: "AKLTdemo")]
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
        recomputeTitle()
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
