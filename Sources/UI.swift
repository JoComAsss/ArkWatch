import SwiftUI
import AppKit

// MARK: - 通用小组件

struct ProgressLine: View {
    let ratio: Double
    var height: CGFloat = 6

    var color: Color {
        if ratio >= 0.9 { return .red }
        if ratio >= 0.7 { return .orange }
        return .accentColor
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18))
                Capsule()
                    .fill(color)
                    .frame(width: max(2, geo.size.width * CGFloat(ratio)))
            }
        }
        .frame(height: height)
    }
}

struct WindowRow: View {
    let window: AFPWindow
    var showReset: Bool = true

    var resetText: String {
        guard let reset = window.resetTime else { return "" }
        let interval = reset.timeIntervalSinceNow
        if interval <= 0 { return "即将重置" }
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours >= 24 { return "\(hours / 24) 天 \(hours % 24) 小时后重置" }
        if hours > 0 { return "\(hours) 小时 \(minutes) 分后重置" }
        return "\(minutes) 分钟后重置"
    }

    /// 基于绝对重置时间每秒重算，避免使用缓存快照里的旧倒计时
    static func resetDescription(_ reset: Date, now: Date) -> String {
        let interval = reset.timeIntervalSince(now)
        if interval <= 0 { return "即将重置" }
        let total = Int(interval.rounded(.down))
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        var parts: [String] = []
        if days > 0 { parts.append("\(days) 天") }
        if hours > 0 || days > 0 { parts.append("\(hours) 小时") }
        parts.append("\(minutes) 分")
        parts.append(String(format: "%02d 秒", seconds))
        let clock = reset.formatted(date: .omitted, time: .standard)
        return parts.joined(separator: " ") + "后重置 · \(clock)"
    }

    private var barColor: Color {
        if window.rawRatio >= 0.9 { return .red }
        if window.rawRatio >= 0.7 { return .orange }
        return Color(red: 0.18, green: 0.62, blue: 0.36)
    }

    var body: some View {
        Button {
            NSWorkspace.shared.open(PlanCatalog.subscriptionURL)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(window.title)
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Text("已用 \(AppModel.formatAFP(window.used)) / \(AppModel.formatAFP(window.quota)) AFP")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f%%", window.rawRatio * 100))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(window.rawRatio >= 0.9 ? Color.red : Color.primary)
                        .frame(width: 52, alignment: .trailing)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.16))
                        Capsule()
                            .fill(LinearGradient(colors: [barColor.opacity(0.85), barColor],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(3, geo.size.width * CGFloat(window.ratio)))
                    }
                }
                .frame(height: 8)

                if showReset, let reset = window.resetTime {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(Self.resetDescription(reset, now: context.date))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 9)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help("打开火山方舟 Agent Plan 订阅页")
    }
}

/// 统一尺寸的胶囊标签（套餐、账号共用）
struct CapsuleTag: View {
    let text: String
    var color: Color = .accentColor

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
    }
}

/// 统一的设置项方框外观（下拉框与「展开」共用，保证一模一样）
struct SettingsBoxLabel: View {
    let text: String
    var width: CGFloat = 150

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.system(size: 11))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            Image(systemName: "chevron.down")
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .frame(width: width, height: 22)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.28), lineWidth: 1))
    }
}

/// NSMenu 菜单项回调载体（NSMenuItem.target 是弱引用，需要外部持有）
final class MenuActionTarget: NSObject {
    private let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func invoke(_ sender: Any?) { handler() }
}

/// 统一样式的设置下拉框：与「展开」按钮同一套方框，菜单用 NSMenu 弹出
struct SettingsSelect<Value: Hashable>: View {
    let options: [(label: String, value: Value)]
    @Binding var selection: Value
    var width: CGFloat = 150

    private var currentLabel: String {
        options.first { $0.value == selection }?.label ?? options.first?.label ?? "-"
    }

    var body: some View {
        Button(action: presentMenu) {
            SettingsBoxLabel(text: currentLabel, width: width)
        }
        .buttonStyle(.plain)
    }

    private func presentMenu() {
        let menu = NSMenu()
        var targets: [MenuActionTarget] = []
        for option in options {
            let target = MenuActionTarget { selection = option.value }
            targets.append(target)
            let item = NSMenuItem(title: option.label,
                                  action: #selector(MenuActionTarget.invoke(_:)),
                                  keyEquivalent: "")
            item.target = target
            menu.addItem(item)
        }
        if let window = NSApp.keyWindow, let view = window.contentView {
            let screenPoint = NSEvent.mouseLocation
            let windowPoint = window.convertPoint(fromScreen: screenPoint)
            let viewPoint = view.convert(windowPoint, from: nil)
            menu.popUp(positioning: nil, at: viewPoint, in: view)
        }
        _ = targets
    }
}

// MARK: - 主面板

struct PopoverView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var prefs: Preferences
    var openSettings: () -> Void
    var openAddAccount: () -> Void
    var openAbout: () -> Void
    var quit: () -> Void

    var planBadge: String {
        guard model.activeAccount != nil else { return "未登录" }
        return model.selectedPlanLabel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()

            if let snapshot = model.snapshot {
                if prefs.popoverSections != "usage" {
                    quotaSection(snapshot)
                }
            } else if model.activeAccount == nil {
                emptyState
            } else if model.isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在读取用量…").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
            } else {
                Text("暂无额度数据").font(.system(size: 11)).foregroundStyle(.secondary)
            }

            if let error = model.errorMessage {
                Text(error)
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
                    .lineLimit(4)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }

            if prefs.popoverSections != "quota", !model.usageRows.isEmpty {
                Divider()
                usageSection
            }

            Divider()
            footer
        }
        .padding(12)
        .frame(width: 400)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.fill")
                .foregroundStyle(Color.accentColor)
                .font(.system(size: 12))
            Text("ArkWatch").font(.system(size: 12, weight: .semibold))

            CapsuleTag(text: planBadge)
                .help("套餐信息，可在设置中查看全部套餐")

            Spacer()

            Menu {
                ForEach(model.accounts) { account in
                    Button {
                        model.activeID = account.id
                    } label: {
                        if account.id == model.activeID {
                            Label(account.menuName, systemImage: "checkmark")
                        } else {
                            Text(account.menuName)
                        }
                    }
                }
                if !model.accounts.isEmpty { Divider() }
                Button("添加账号…") { openAddAccount() }
                Button("管理账号…") { openSettings() }
                Divider()
                Button("关于 ArkWatch") { openAbout() }
            } label: {
                CapsuleTag(text: model.activeAccount?.displayName ?? "登录", color: .secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Button {
                model.refresh(force: true)
            } label: {
                Image(systemName: model.isLoading ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help("立即刷新")

            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape").font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help("设置")
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("尚未添加账号").font(.system(size: 12, weight: .medium))
            Text("使用火山引擎 API 访问密钥（账号 + 密码）登录，可在同一台机器上保存多个账号并随时切换。")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("添加账号") { openAddAccount() }
                .controlSize(.small)
        }
        .padding(.vertical, 6)
    }

    private func quotaSection(_ snapshot: AFPSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("燃料值(AFP)用量").font(.system(size: 10, weight: .semibold))
                Spacer()
                ForEach([("5 小时", "fiveHour"), ("一周", "weekly"), ("一月", "monthly")], id: \.1) { item in
                    Button(item.0) { prefs.menuBarWindow = item.1 }
                        .buttonStyle(.plain)
                        .font(.system(size: 9, weight: prefs.menuBarWindow == item.1 ? .semibold : .regular))
                        .foregroundStyle(prefs.menuBarWindow == item.1 ? Color.accentColor : Color.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(prefs.menuBarWindow == item.1
                                           ? Color.accentColor.opacity(0.16)
                                           : Color.secondary.opacity(0.08))
                        )
                }
            }

            if let five = snapshot.window("fiveHour") {
                WindowRow(window: five, showReset: true)
            }
            if let week = snapshot.window("weekly") {
                WindowRow(window: week, showReset: false)
            }
            if let month = snapshot.window("monthly") {
                WindowRow(window: month, showReset: false)
            }
        }
    }

    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("今日模型用量").font(.system(size: 10, weight: .semibold))
                Spacer()
                Text("Token").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            ForEach(model.usageRows.prefix(6)) { row in
                HStack(spacing: 6) {
                    Text(row.model)
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if row.billingType == "OutsideOfPlan" {
                        Text("超额")
                            .font(.system(size: 8))
                            .padding(.horizontal, 4)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                    }
                    Spacer()
                    Text(AppModel.formatTokens(row.usage))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if let plan = model.plan, let end = plan.endTime {
                Text("到期 \(String(end.prefix(10)))")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                if plan.autoRenew == true {
                    Text("自动续费").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if let updated = model.lastUpdated {
                Text("更新 \(updated.formatted(date: .omitted, time: .standard))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            Text("· \(prefs.refreshSeconds)s")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
            Button("退出") { quit() }
                .buttonStyle(.borderless)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }
}

/// 通用「从剪贴板粘贴」按钮
struct PasteButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 11))
        }
        .buttonStyle(.borderless)
        .help("从剪贴板粘贴")
        .accessibilityLabel("从剪贴板粘贴")
    }
}

// MARK: - 设置视图模型（避免使用 SwiftUI 宏，兼容仅有命令行工具的环境）

final class SettingsModel: ObservableObject {
    @Published var showAdd = false
    @Published var editing: Account?
    @Published var newName = ""
    @Published var newAK = ""
    @Published var newSK = ""
    @Published var newNote = ""
    @Published var verifyMessage = ""
    @Published var verifying = false

    func startAdd() {
        newName = ""
        newAK = ""
        newNote = ""
        newSK = ""
        verifyMessage = ""
        verifying = false
        showAdd = true
    }

    private func clipboardText() -> String? {
        guard let raw = NSPasteboard.general.string(forType: .string) else { return nil }
        let cleaned = raw
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// 粘贴到「账号」：去掉所有空白字符
    func pasteAccount() {
        guard let value = clipboardText() else {
            NSSound.beep()
            return
        }
        newAK = value.components(separatedBy: .whitespacesAndNewlines).joined()
        verifyMessage = ""
    }

    /// 粘贴到「密码」：去掉所有空白字符
    func pasteSecret() {
        guard let value = clipboardText() else {
            NSSound.beep()
            return
        }
        newSK = value.components(separatedBy: .whitespacesAndNewlines).joined()
        verifyMessage = ""
    }

    func startEdit(_ account: Account) {
        newName = account.name
        newNote = account.note
        newSK = ""
        verifyMessage = ""
        editing = account
    }

    func test(model: AppModel, account: Account?) async {
        verifying = true
        let ak = account?.ak ?? newAK
        var sk = newSK
        if sk.isEmpty, let account { sk = model.store.secretKey(for: account) ?? "" }
        let result = await model.verify(ak: ak, sk: sk)
        await MainActor.run {
            self.verifyMessage = result
            self.verifying = false
        }
    }

    func save(model: AppModel, account: Account?) {
        if let account {
            var updated = account
            updated.name = newName.isEmpty ? account.name : newName
            updated.note = newNote
            model.updateAccount(updated, sk: newSK.isEmpty ? nil : newSK)
            editing = nil
        } else {
            _ = model.addAccount(name: newName, ak: newAK, sk: newSK, note: newNote)
            showAdd = false
        }
    }
}

// MARK: - 设置 / 账号管理

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var prefs: Preferences
    @ObservedObject var vm: SettingsModel
    var openPlans: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("账号").font(.system(size: 13, weight: .semibold))

            if model.accounts.isEmpty {
                Text("还没有账号，点击下方「添加账号」，填入 API 访问密钥的账号与密码即可。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(model.accounts) { account in
                        HStack(spacing: 8) {
                            Image(systemName: account.id == model.activeID ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(account.id == model.activeID ? Color.accentColor : Color.secondary)
                                .onTapGesture { model.activeID = account.id }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(account.displayName).font(.system(size: 12))
                                Text(account.ak).font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Button("编辑") { vm.startEdit(account) }
                                .buttonStyle(.borderless)
                                .font(.system(size: 10))
                            Button("删除") { model.deleteAccount(account) }
                                .buttonStyle(.borderless)
                                .font(.system(size: 10))
                                .foregroundStyle(.red)
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            Button {
                vm.startAdd()
            } label: {
                Label("添加账号", systemImage: "plus")
            }
            .controlSize(.small)

            Divider()

            HStack(spacing: 8) {
                Text("套餐").font(.system(size: 13, weight: .semibold))
                if model.activeAccount != nil {
                    if model.isCheckingPlan {
                        CapsuleTag(text: "检测中", color: Color(red: 0.78, green: 0.60, blue: 0.05))
                    } else if model.isSelectedPlanOpened {
                        CapsuleTag(text: "已开通 · \(model.selectedPlanLabel)", color: .green)
                    } else {
                        CapsuleTag(text: "未开通", color: .red)
                    }
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Text("查看全部套餐").font(.system(size: 11))
                Spacer()
                Button {
                    openPlans()
                } label: {
                    SettingsBoxLabel(text: "展开", width: 150)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                Text("套餐生效时间范围").font(.system(size: 11))
                Spacer()
                Text(model.planRangeText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(model.plan == nil ? .secondary : .primary)
            }

            Divider()

            Text("外观").font(.system(size: 13, weight: .semibold))

            HStack {
                Text("设置栏大小").font(.system(size: 11))
                Spacer()
                SettingsSelect(options: stride(from: 80, through: 150, by: 5).map { ("\($0)%", $0) },
                               selection: $prefs.settingsScalePercent)
            }

            HStack {
                Text("菜单栏大小").font(.system(size: 11))
                Spacer()
                SettingsSelect(options: stride(from: 80, through: 130, by: 5).map { ("\($0)%", $0) },
                               selection: $prefs.menuBarScalePercent)
            }

            HStack {
                Text("整体外观").font(.system(size: 11))
                Spacer()
                SettingsSelect(options: [("跟随系统", "system"), ("浅色", "light"), ("深色", "dark")],
                               selection: $prefs.appearanceMode)
            }

            Divider()

            Text("通用").font(.system(size: 13, weight: .semibold))

            HStack {
                Text("刷新间隔").font(.system(size: 11))
                Spacer()
                SettingsSelect(options: [("30 秒", 30), ("60 秒", 60), ("2 分钟", 120), ("5 分钟", 300)],
                               selection: $prefs.refreshSeconds)
            }

            HStack {
                Text("菜单栏显示").font(.system(size: 11))
                Spacer()
                SettingsSelect(options: [("剩余 %", "remainingPercent"), ("已用 %", "usedPercent"), ("剩余 AFP", "remainingAFP")],
                               selection: $prefs.displayMode)
            }

            HStack {
                Text("菜单栏选项").font(.system(size: 11))
                Spacer()
                SettingsSelect(options: [("余量 + 模型用量", "all"), ("仅余量统计", "quota"), ("仅模型用量", "usage")],
                               selection: $prefs.popoverSections)
            }

            Toggle("开机自动启动", isOn: $prefs.launchAtLogin)
                .font(.system(size: 11))
                .toggleStyle(.switch)
                .controlSize(.small)

            Divider()

            HStack {
                Text("版本").font(.system(size: 9)).foregroundStyle(.tertiary)
                Text(AppInfo.versionText)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer()
            }

            Text("AK/SK 在火山引擎控制台「API 访问密钥」中创建；Secret Key 仅保存在本机钥匙串。")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 420, alignment: .topLeading)
        .sheet(isPresented: $vm.showAdd) {
            accountForm(title: "添加账号", account: nil)
        }
        .sheet(item: $vm.editing) { account in
            accountForm(title: "编辑账号", account: account)
        }
        .onReceive(NotificationCenter.default.publisher(for: .arkWatchAddAccount)) { _ in
            vm.startAdd()
        }
    }

    private func accountForm(title: String, account: Account?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 13, weight: .semibold))

            VStack(alignment: .leading, spacing: 4) {
                Text("账号").font(.system(size: 10)).foregroundStyle(.secondary)
                if account == nil {
                    HStack(spacing: 6) {
                        TextField("Access Key ID，通常以 AKLT 开头", text: $vm.newAK)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                        PasteButton(action: { vm.pasteAccount() })
                    }
                } else {
                    Text(account!.ak)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("密码").font(.system(size: 10)).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    SecureField(account == nil ? "Secret Access Key" : "Secret Access Key（留空则不修改）",
                                text: $vm.newSK)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                    PasteButton(action: { vm.pasteSecret() })
                }
            }

            if !vm.verifyMessage.isEmpty {
                Text(vm.verifyMessage)
                    .font(.system(size: 10))
                    .foregroundStyle(vm.verifyMessage.hasPrefix("连接成功") ? .green : .red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button(vm.verifying ? "测试中…" : "测试连接") {
                    Task { await vm.test(model: model, account: account) }
                }
                .disabled(vm.verifying || (vm.newSK.isEmpty && account == nil))
                .controlSize(.small)

                Spacer()

                Button("取消") {
                    vm.showAdd = false
                    vm.editing = nil
                }
                .controlSize(.small)

                Button("保存") {
                    vm.save(model: model, account: account)
                }
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
                .disabled(vm.newSK.isEmpty || (account == nil && vm.newAK.isEmpty))
            }

            Text("这两项是火山引擎「访问控制 → API 访问密钥」里的 Access Key ID 与 Secret Access Key，不是控制台登录用的手机号/密码。")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 400)
    }
}

extension View {
    /// 所有设置项下拉框统一样式：隐藏标签、固定 130pt、右对齐
    func settingsPickerLayout() -> some View {
        self.labelsHidden()
            .frame(width: 130, alignment: .trailing)
    }
}

// MARK: - 设置窗口容器（按设置栏缩放内联缩放，不重建视图树）

struct SettingsContainer: View {
    @ObservedObject var model: AppModel
    @ObservedObject var prefs: Preferences
    @ObservedObject var vm: SettingsModel
    var openPlans: () -> Void

    private var factor: Double { min(1.5, max(0.8, prefs.settingsScale)) }

    var body: some View {
        SettingsView(model: model, prefs: prefs, vm: vm, openPlans: openPlans)
            .scaleEffect(factor, anchor: .topLeading)
            .frame(width: 420 * factor, height: 600 * factor, alignment: .topLeading)
    }
}

// MARK: - 独立窗口控制器

final class PanelWindowController: NSWindowController {
    static func make<Content: View>(title: String, view: Content, size: NSSize) -> PanelWindowController {
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(size)
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .normal
        return PanelWindowController(window: window)
    }
}
