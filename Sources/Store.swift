import Foundation
import Security

// MARK: - 账号

struct Account: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var ak: String
    var note: String

    init(id: String = UUID().uuidString, name: String, ak: String, note: String = "") {
        self.id = id
        self.name = name
        self.ak = ak
        self.note = note
    }

    /// 界面统一显示为「用户」
    var displayName: String { L("用户") }

    /// 切换菜单里的区分名：用户 · 尾号
    var menuName: String {
        guard ak.count >= 4 else { return displayName }
        return "\(displayName) · \(ak.suffix(4))"
    }
}

// MARK: - 版本信息

enum AppInfo {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    static var versionText: String { "\(version) (\(build))" }
}

// MARK: - Keychain（保存 Secret Key）

enum Keychain {
    private static let service = "com.joco.arkwatch"

    static func set(_ value: String, account: String) -> Bool {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - 账号仓库

final class AccountStore {
    private(set) var accounts: [Account] = []
    private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("ArkWatch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("accounts.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([Account].self, from: data) else {
            accounts = []
            return
        }
        accounts = list
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        try? data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    @discardableResult
    func add(name: String, ak: String, sk: String, note: String = "") -> Account? {
        let trimmedAK = ak.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSK = sk.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAK.isEmpty, !trimmedSK.isEmpty else { return nil }
        let account = Account(name: name.isEmpty ? String(trimmedAK.prefix(8)) : name,
                              ak: trimmedAK,
                              note: note)
        guard Keychain.set(trimmedSK, account: account.id) else { return nil }
        accounts.append(account)
        save()
        return account
    }

    func update(_ account: Account, sk: String?) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[index] = account
        if let sk, !sk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _ = Keychain.set(sk.trimmingCharacters(in: .whitespacesAndNewlines), account: account.id)
        }
        save()
    }

    func remove(_ account: Account) {
        Keychain.delete(account: account.id)
        accounts.removeAll { $0.id == account.id }
        save()
    }

    func secretKey(for account: Account) -> String? {
        Keychain.get(account: account.id)
    }
}

// MARK: - 偏好设置

final class Preferences: ObservableObject {
    static let shared = Preferences()

    @Published var refreshSeconds: Int {
        didSet { UserDefaults.standard.set(refreshSeconds, forKey: "refreshSeconds") }
    }
    /// remainingPercent / usedPercent / remainingAFP
    @Published var displayMode: String {
        didSet { UserDefaults.standard.set(displayMode, forKey: "displayMode") }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            LaunchAgent.setEnabled(launchAtLogin)
        }
    }

    /// 设置窗口缩放百分比（80 ~ 150）
    @Published var settingsScalePercent: Int {
        didSet { UserDefaults.standard.set(settingsScalePercent, forKey: "settingsScalePercent") }
    }

    /// 菜单栏字号缩放百分比（80 ~ 150）
    @Published var menuBarScalePercent: Int {
        didSet { UserDefaults.standard.set(menuBarScalePercent, forKey: "menuBarScalePercent") }
    }

    var settingsScale: Double { Double(settingsScalePercent) / 100 }
    var menuBarScale: Double { Double(menuBarScalePercent) / 100 }

    /// 菜单栏百分比对应的窗口：daily / weekly / monthly
    @Published var menuBarWindow: String {
        didSet { UserDefaults.standard.set(menuBarWindow, forKey: "menuBarWindow") }
    }

    /// 弹窗显示内容：all / quota / usage
    @Published var popoverSections: String {
        didSet { UserDefaults.standard.set(popoverSections, forKey: "popoverSections") }
    }

    /// 界面语言：zh / en
    @Published var language: String {
        didSet { UserDefaults.standard.set(language, forKey: "language") }
    }

    /// system / light / dark
    @Published var appearanceMode: String {
        didSet { UserDefaults.standard.set(appearanceMode, forKey: "appearanceMode") }
    }

    private init() {
        let defaults = UserDefaults.standard
        let storedRefresh = defaults.integer(forKey: "refreshSeconds")
        refreshSeconds = storedRefresh >= 15 ? storedRefresh : 60
        let storedMode = defaults.string(forKey: "displayMode") ?? "remainingPercent"
        // 归一化历史/异常取值，避免落入 default 分支与选择框显示不一致
        let validModes = ["remainingPercent", "usedPercent", "remainingAFP"]
        displayMode = validModes.contains(storedMode) ? storedMode : "remainingPercent"
        launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        // 兼容旧版本的 Double 键，统一转成百分比整数
        let storedSettingsPercent = defaults.integer(forKey: "settingsScalePercent")
        if storedSettingsPercent > 0 {
            settingsScalePercent = min(150, max(80, storedSettingsPercent))
        } else {
            let legacy = defaults.double(forKey: "settingsScale")
            settingsScalePercent = legacy >= 0.5 ? min(150, max(80, Int((legacy * 100).rounded()))) : 100
        }
        let storedMenuPercent = defaults.integer(forKey: "menuBarScalePercent")
        if storedMenuPercent > 0 {
            menuBarScalePercent = min(130, max(80, storedMenuPercent))
        } else {
            let legacyMenu = defaults.double(forKey: "menuBarScale")
            menuBarScalePercent = legacyMenu >= 0.5 ? min(130, max(80, Int((legacyMenu * 100).rounded()))) : 100
        }
        appearanceMode = defaults.string(forKey: "appearanceMode") ?? "system"
        language = defaults.string(forKey: "language") ?? "zh"
        let storedWindow = defaults.string(forKey: "menuBarWindow") ?? "monthly"
        let validWindows = ["fiveHour", "weekly", "monthly"]
        menuBarWindow = validWindows.contains(storedWindow) ? storedWindow : "monthly"
        popoverSections = defaults.string(forKey: "popoverSections") ?? "all"
    }
}

// MARK: - 开机自启（LaunchAgent，兼容未签名本地构建）

enum LaunchAgent {
    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.joco.arkwatch.plist")
    }

    static func setEnabled(_ enabled: Bool) {
        if enabled {
            guard let executable = Bundle.main.executablePath else { return }
            let plist: [String: Any] = [
                "Label": "com.joco.arkwatch",
                "ProgramArguments": [executable],
                "RunAtLoad": true,
                "KeepAlive": false,
                "ProcessType": "Interactive"
            ]
            guard let data = try? PropertyListSerialization.data(fromPropertyList: plist,
                                                                 format: .xml,
                                                                 options: 0) else { return }
            try? FileManager.default.createDirectory(
                at: plistURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try? data.write(to: plistURL, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: plistURL)
        }
    }
}
