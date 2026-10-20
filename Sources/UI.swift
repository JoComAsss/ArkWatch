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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(window.title)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 44, alignment: .leading)
                Text("\(AppModel.formatAFP(window.used)) / \(AppModel.formatAFP(window.quota)) AFP")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(window.percentText)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(window.ratio >= 0.9 ? .red : .primary)
            }
            ProgressLine(ratio: window.ratio)
            if !resetText.isEmpty {
                Text(resetText)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - 登录视图模型

final class LoginModel: ObservableObject {
    @Published var phone = ""
    @Published var code = ""
    @Published var secondsLeft = 0
    @Published var message: String?
    @Published var isError = false
    @Published var demoCode: String?

    private var timer: Timer?
    private var expiry: Date?

    var normalizedPhone: String { phone.filter(\.isNumber) }

    var phoneIsValid: Bool {
        let p = normalizedPhone
        guard p.count == 11, p.hasPrefix("1") else { return false }
        let second = p[p.index(after: p.startIndex)]
        return "3456789".contains(second)
    }

    var canSend: Bool { secondsLeft == 0 }
    var canLogin: Bool { demoCode != nil && !code.isEmpty && phoneIsValid }

    func sendCode() {
        guard phoneIsValid else {
            message = "请输入正确的 11 位手机号"
            isError = true
            return
        }
        let generated = String(format: "%06d", Int.random(in: 0...999_999))
        demoCode = generated
        expiry = Date().addingTimeInterval(300)
        code = ""
        message = "演示验证码：\(generated)（5 分钟内有效）"
        isError = false
        secondsLeft = 60
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            guard let self else { return }
            if self.secondsLeft <= 1 {
                self.secondsLeft = 0
                t.invalidate()
            } else {
                self.secondsLeft -= 1
            }
        }
        timer?.tolerance = 0.2
    }

    /// 校验通过后写入登录态
    func submit(to model: AppModel) {
        guard phoneIsValid else {
            message = "请输入正确的 11 位手机号"
            isError = true
            return
        }
        guard let demoCode else {
            message = "请先获取验证码"
            isError = true
            return
        }
        if let expiry, Date() > expiry {
            message = "验证码已过期，请重新获取"
            isError = true
            return
        }
        guard code.trimmingCharacters(in: .whitespaces) == demoCode else {
            message = "验证码不正确"
            isError = true
            return
        }
        model.login(phone: normalizedPhone)
        reset()
    }

    func reset() {
        phone = ""
        code = ""
        demoCode = nil
        expiry = nil
        message = nil
        isError = false
        secondsLeft = 0
        timer?.invalidate()
    }
}

// MARK: - 登录面板

struct LoginView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var vm: LoginModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill").foregroundStyle(Color.accentColor)
                Text("登录 ArkWatch").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("手机号 + 验证码")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                TextField("手机号", text: $vm.phone)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))

                HStack(spacing: 8) {
                    TextField("6 位验证码", text: $vm.code)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .onSubmit { vm.submit(to: model) }

                    Button(vm.secondsLeft > 0 ? "\(vm.secondsLeft)s 后重发" : "获取验证码") {
                        vm.sendCode()
                    }
                    .controlSize(.regular)
                    .disabled(vm.secondsLeft > 0)
                    .frame(width: 108)
                }

                if let message = vm.message {
                    Text(message)
                        .font(.system(size: 10))
                        .foregroundStyle(vm.isError ? .red : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    vm.submit(to: model)
                } label: {
                    Text("登录").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(!vm.canLogin)
            }

            Divider()

            Text("演示模式：验证码由本机生成并显示在界面上，仅用于本地身份校验，不会发送短信。登录状态保存在钥匙串，重启后自动恢复，直到你点击「退出登录」。")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 400)
    }
}

// MARK: - 主面板

struct PopoverView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var prefs: Preferences
    @ObservedObject var loginVM: LoginModel
    var openSettings: () -> Void
    var quit: () -> Void

    var planBadge: String {
        guard let plan = model.plan else { return model.isLoggedIn ? "未绑定" : "未登录" }
        return "\(plan.plan == "CodingPlan" ? "Coding" : "Agent") \(plan.planType)"
    }

    var body: some View {
        if !model.isLoggedIn {
            LoginView(model: model, vm: loginVM)
        } else {
            dashboard
        }
    }

    private var dashboard: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()

            if let snapshot = model.snapshot {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(snapshot.windows) { window in
                        WindowRow(window: window)
                    }
                }
            } else if model.isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在读取用量…").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
            } else {
                unboundState
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

            if !model.usageRows.isEmpty {
                Divider()
                usageSection
            }

            Divider()
            footer
        }
        .padding(12)
        .frame(width: 400)
    }

    private var unboundState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.activeAccount.map { "已登录 \($0.maskedPhone)" } ?? "未登录")
                .font(.system(size: 11, weight: .medium))
            Text("该手机号尚未绑定 AK/SK，绑定后即可读取套餐与用量。")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("去绑定") { openSettings() }
                .controlSize(.small)
        }
        .padding(.vertical, 6)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.fill")
                .foregroundStyle(Color.accentColor)
                .font(.system(size: 12))
            Text("ArkWatch").font(.system(size: 12, weight: .semibold))

            Text(planBadge)
                .font(.system(size: 9, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.12), in: Capsule())

            Spacer()

            Menu {
                if let account = model.activeAccount {
                    Text("当前账号：\(account.maskedPhone)")
                }
                Divider()
                Button("设置…") { openSettings() }
                Button("退出登录") {
                    model.logout()
                    loginVM.reset()
                }
            } label: {
                HStack(spacing: 3) {
                    Text(model.activeAccount?.maskedPhone ?? "账号")
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 8))
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button {
                model.refresh(force: true)
            } label: {
                Image(systemName: model.isLoading ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .help("立即刷新")

            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape").font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .help("设置")
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

// MARK: - 设置视图模型

final class SettingsModel: ObservableObject {
    @Published var bindingPhone: String?
    @Published var bindAK = ""
    @Published var bindSK = ""
    @Published var bindNote = ""
    @Published var verifyMessage = ""
    @Published var verifying = false

    func startBind(phone: String, currentAK: String, currentNote: String) {
        bindingPhone = phone
        bindAK = currentAK
        bindSK = ""
        bindNote = currentNote
        verifyMessage = ""
        verifying = false
    }

    func cancel() {
        bindingPhone = nil
        bindAK = ""
        bindSK = ""
        bindNote = ""
        verifyMessage = ""
    }

    func test(model: AppModel, phone: String) async {
        verifying = true
        var sk = bindSK
        if sk.isEmpty, let account = model.store.account(phone: phone) {
            sk = model.secretKey(for: account) ?? ""
        }
        let result = await model.verify(ak: bindAK, sk: sk)
        await MainActor.run {
            self.verifyMessage = result
            self.verifying = false
        }
    }

    func save(model: AppModel, phone: String) {
        model.bindCredentials(phone: phone, ak: bindAK, sk: bindSK, name: "", note: bindNote)
        cancel()
    }
}

// MARK: - 设置 / 账号管理

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var prefs: Preferences
    @ObservedObject var vm: SettingsModel
    var closeWindow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("账号").font(.system(size: 13, weight: .semibold))
                Spacer()
                if let session = model.session {
                    Text("已登录 \(model.activeAccount?.maskedPhone ?? session.phone)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Button("退出登录") {
                        model.logout()
                        closeWindow()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                }
            }

            if model.accounts.isEmpty {
                Text("还没有账号。关闭本窗口，在菜单栏面板用手机号 + 验证码登录后即可绑定 AK/SK。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 6) {
                    ForEach(model.accounts) { account in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(account.maskedPhone).font(.system(size: 12, design: .monospaced))
                                    if account.phone == model.session?.phone {
                                        Text("当前")
                                            .font(.system(size: 8))
                                            .padding(.horizontal, 4)
                                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                                    }
                                }
                                Text(account.ak.isEmpty ? "未绑定 AK" : "AK \(account.ak)")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(account.ak.isEmpty ? .red : .secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button(account.ak.isEmpty ? "绑定 AK" : "编辑 AK") {
                                vm.startBind(phone: account.phone, currentAK: account.ak, currentNote: account.note)
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 10))
                            Button("删除") {
                                model.deleteAccount(account)
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            Divider()

            Text("通用").font(.system(size: 13, weight: .semibold))

            HStack {
                Text("刷新间隔").font(.system(size: 11))
                Spacer()
                Picker("", selection: $prefs.refreshSeconds) {
                    Text("30 秒").tag(30)
                    Text("60 秒").tag(60)
                    Text("2 分钟").tag(120)
                    Text("5 分钟").tag(300)
                }
                .labelsHidden()
                .frame(width: 110)
            }

            HStack {
                Text("菜单栏显示").font(.system(size: 11))
                Spacer()
                Picker("", selection: $prefs.displayMode) {
                    Text("剩余 %").tag("remainingPercent")
                    Text("已用 %").tag("usedPercent")
                    Text("剩余 AFP").tag("remainingAFP")
                }
                .labelsHidden()
                .frame(width: 110)
            }

            Toggle("开机自动启动", isOn: $prefs.launchAtLogin)
                .font(.system(size: 11))
                .toggleStyle(.switch)
                .controlSize(.small)

            Divider()

            Text("手机号仅作为本机登录标识；AK/SK 用于调用方舟 OpenAPI，Secret Key 保存在系统钥匙串。")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 420, alignment: .topLeading)
        .sheet(item: Binding(
            get: { vm.bindingPhone.map(BindingPhone.init) },
            set: { if $0 == nil { vm.cancel() } }
        )) { wrapper in
            bindForm(phone: wrapper.phone)
        }
    }

    private func bindForm(phone: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("绑定 AK/SK").font(.system(size: 13, weight: .semibold))
            Text(phone).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)

            TextField("Access Key ID", text: $vm.bindAK)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))

            SecureField("Secret Access Key（留空则不修改）", text: $vm.bindSK)
                .textFieldStyle(.roundedBorder)

            TextField("备注（可选）", text: $vm.bindNote)
                .textFieldStyle(.roundedBorder)

            if !vm.verifyMessage.isEmpty {
                Text(vm.verifyMessage)
                    .font(.system(size: 10))
                    .foregroundStyle(vm.verifyMessage.hasPrefix("连接成功") ? .green : .red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button(vm.verifying ? "测试中…" : "测试连接") {
                    Task { await vm.test(model: model, phone: phone) }
                }
                .disabled(vm.verifying || vm.bindAK.isEmpty)
                .controlSize(.small)

                Spacer()

                Button("取消") { vm.cancel() }
                    .controlSize(.small)

                Button("保存") { vm.save(model: model, phone: phone) }
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
                    .disabled(vm.bindAK.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 380)
    }
}

/// String 包装为 Identifiable，供 sheet(item:) 使用
struct BindingPhone: Identifiable {
    let phone: String
    var id: String { phone }
    init(_ phone: String) { self.phone = phone }
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
