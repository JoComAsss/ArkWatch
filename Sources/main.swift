import AppKit
import SwiftUI
import Combine

extension Notification.Name {
    static let arkWatchAddAccount = Notification.Name("ArkWatchAddAccount")
}

// MARK: - 菜单栏应用

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var model: AppModel!
    private var settingsWC: PanelWindowController?
    private var plansWC: PanelWindowController?
    private let settingsVM = SettingsModel()
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.target = self
            button.action = #selector(togglePopover(_:))
        }

        let root = PopoverView(model: model,
                               prefs: model.prefs,
                               openSettings: { [weak self] in self?.showSettings() },
                               openAddAccount: { [weak self] in self?.showAddAccount() },
                               quit: { NSApp.terminate(nil) })
        popover.contentViewController = NSHostingController(rootView: root)
        popover.behavior = .transient
        popover.animates = false

        model.$statusLabel
            .combineLatest(model.$statusValue)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.updateStatusItem() }
            .store(in: &cancellables)
        updateStatusItem()

        // 数据量变化会改变面板高度，按 SwiftUI 的理想尺寸重设 popover 大小
        model.objectWillChange
            .receive(on: RunLoop.main)
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.resizePopover() }
            .store(in: &cancellables)
        resizePopover()
    }

    private func resizePopover() {
        guard let view = popover.contentViewController?.view else { return }
        view.layoutSubtreeIfNeeded()
        let size = view.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        popover.contentSize = NSSize(width: ceil(size.width), height: ceil(size.height))
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        button.attributedTitle = Self.makeStatusTitle(label: model.statusLabel, value: model.statusValue)
        button.toolTip = tooltip()
    }

    /// 菜单栏标题：空标签时单行；否则左上角小字说明 + 下方数值
    static func makeStatusTitle(label: String, value: String) -> NSAttributedString {
        if label.isEmpty {
            return NSAttributedString(string: value, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.labelColor
            ])
        }
        let para = NSMutableParagraphStyle()
        para.alignment = .left
        para.minimumLineHeight = 9
        para.maximumLineHeight = 9
        let attr = NSMutableAttributedString(string: label, attributes: [
            .font: NSFont.systemFont(ofSize: 8, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: para
        ])
        attr.append(NSAttributedString(string: "\n" + value, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: para
        ]))
        return attr
    }

    private func tooltip() -> String {
        guard let account = model.activeAccount else { return "ArkWatch · 未登录" }
        var text = "ArkWatch · \(account.name)"
        if let snapshot = model.snapshot, let month = snapshot.window("monthly") {
            text += String(format: "\n本月 %.0f / %.0f AFP", month.used, month.quota)
            if let reset = month.resetTime {
                text += "\n重置 \(reset.formatted(date: .abbreviated, time: .shortened))"
            }
        }
        if let plan = model.plan {
            text += "\n\(plan.plan) \(plan.planType) · \(plan.status)"
        }
        if let error = model.errorMessage { text += "\n⚠︎ \(error)" }
        return text
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        resizePopover()
        model.refresh()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func showPlans() {
        popover.performClose(nil)
        let view = PlansView(model: model, openConsole: { [weak self] in self?.openPlanConsole() })
        if plansWC == nil {
            plansWC = PanelWindowController.make(title: "火山方舟套餐", view: view,
                                                 size: NSSize(width: 500, height: 560))
        } else {
            plansWC?.contentViewController = NSHostingController(rootView: view)
        }
        plansWC?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openPlanConsole() {
        NSWorkspace.shared.open(PlanCatalog.consoleURL)
    }

    func showSettings() {
        popover.performClose(nil)
        if settingsWC == nil {
            settingsWC = PanelWindowController.make(
                title: "ArkWatch 设置",
                view: SettingsView(model: model, prefs: model.prefs, vm: settingsVM,
                                   openPlans: { [weak self] in self?.showPlans() }),
                size: NSSize(width: 420, height: 560))
        } else {
            settingsWC?.contentViewController = NSHostingController(
                rootView: SettingsView(model: model, prefs: model.prefs, vm: settingsVM,
                                       openPlans: { [weak self] in self?.showPlans() }))
        }
        settingsWC?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showAddAccount() {
        showSettings()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationCenter.default.post(name: .arkWatchAddAccount, object: nil)
        }
    }
}

// MARK: - 命令行工具

func runSelfTestAndExit() -> Never {
    exit(SignatureSelfTest.run() ? 0 : 1)
}

func runProbeAndExit() -> Never {
    let env = ProcessInfo.processInfo.environment
    guard let ak = env["ARK_AK"], let sk = env["ARK_SK"] else {
        FileHandle.standardError.write(Data("用法：ARK_AK=xxx ARK_SK=yyy ArkWatch --probe\n".utf8))
        exit(2)
    }
    let client = ArkClient(ak: ak, sk: sk)
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        do {
            if let plan = try await client.fetchActivePlan() {
                print("套餐    : \(plan.plan) \(plan.planType) 状态 \(plan.status) 到期 \(plan.endTime ?? "-")")
            }
            let afp = try await client.fetchAFP()
            print("\n窗口\t已用\t配额\t占比")
            for w in afp.windows {
                print(String(format: "%@\t%.1f\t%.1f\t%.1f%%", w.title, w.used, w.quota, w.ratio * 100))
            }
            let rows = try await client.fetchUsage()
            print("\n今日模型用量（Token）")
            for row in rows.prefix(20) {
                print(String(format: "%-40@ %12.0f %@", row.model, row.usage, row.billingType))
            }
        } catch {
            FileHandle.standardError.write(Data("错误：\(error.localizedDescription)\n".utf8))
            exit(1)
        }
        semaphore.signal()
    }
    semaphore.wait()
    exit(0)
}

// MARK: - 入口

let arguments = CommandLine.arguments
if arguments.contains("--selftest") { runSelfTestAndExit() }
if arguments.contains("--probe") { runProbeAndExit() }
if arguments.contains("--help") {
    print("""
    ArkWatch - 火山方舟用量监控

      --selftest            校验 AK/SK 签名实现
      --probe               命令行查询用量（需 ARK_AK / ARK_SK 环境变量）
      --help                显示帮助
    """)
    exit(0)
}

if let idx = arguments.firstIndex(of: "--render"), idx + 1 < arguments.count {
    runRenderAndExit(path: arguments[idx + 1], demo: arguments.contains("--demo"))
}

func runRenderAndExit(path: String, demo: Bool) -> Never {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    let model = AppModel()
    if demo { model.loadDemoData() }
    let view = PopoverView(model: model, prefs: model.prefs,
                           openSettings: {}, openAddAccount: {}, quit: {})
    let hosting = NSHostingView(rootView: view)
    hosting.frame = NSRect(x: 0, y: 0, width: 400, height: demo ? 360 : 190)
    hosting.layoutSubtreeIfNeeded()
    let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless],
                          backing: .buffered, defer: false)
    window.contentView = hosting
    window.orderFrontRegardless()
    RunLoop.main.run(until: Date().addingTimeInterval(1.2))
    hosting.layoutSubtreeIfNeeded()
    guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
        FileHandle.standardError.write(Data("渲染失败\n".utf8)); exit(1)
    }
    hosting.cacheDisplay(in: hosting.bounds, to: rep)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("编码失败\n".utf8)); exit(1)
    }
    try? png.write(to: URL(fileURLWithPath: path))
    print("rendered -> \(path)")
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
