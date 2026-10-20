import Foundation
import Security

// MARK: - 账号（手机号身份 + 绑定的 AK/SK）

struct Account: Codable, Identifiable, Equatable {
    var id: String
    var phone: String
    var name: String
    var ak: String
    var note: String
    var createdAt: Date

    init(id: String = UUID().uuidString,
         phone: String,
         name: String = "",
         ak: String = "",
         note: String = "",
         createdAt: Date = Date()) {
        self.id = id
        self.phone = phone
        self.name = name
        self.ak = ak
        self.note = note
        self.createdAt = createdAt
    }

    /// 兼容旧版本 accounts.json（没有 phone / createdAt 字段）
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        phone = try c.decodeIfPresent(String.self, forKey: .phone) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        ak = try c.decodeIfPresent(String.self, forKey: .ak) ?? ""
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    var maskedPhone: String {
        guard phone.count == 11 else { return phone.isEmpty ? "未绑定手机号" : phone }
        let start = phone.prefix(3)
        let end = phone.suffix(4)
        return "\(start)****\(end)"
    }

    var hasCredentials: Bool { !ak.isEmpty && !phone.isEmpty }
}

// MARK: - 会话（登录态，保留到用户主动退出）

struct Session: Codable, Equatable {
    var phone: String
    var token: String
    var loginAt: Date
}

// MARK: - Keychain

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

    func account(phone: String) -> Account? {
        accounts.first { $0.phone == phone }
    }

    /// 登录时确保该手机号有账号记录
    @discardableResult
    func ensureAccount(phone: String) -> Account {
        if let existing = account(phone: phone) { return existing }
        let account = Account(phone: phone, name: phone)
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

// MARK: - 登录态存取

enum SessionStore {
    private static let key = "session"
    private static let service = "com.joco.arkwatch.session"

    static func save(_ session: Session) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        _ = Keychain.set(String(data: data, encoding: .utf8) ?? "", account: key)
    }

    static func load() -> Session? {
        guard let raw = Keychain.get(account: key), let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    static func clear() {
        Keychain.delete(account: key)
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

    private init() {
        let defaults = UserDefaults.standard
        let storedRefresh = defaults.integer(forKey: "refreshSeconds")
        refreshSeconds = storedRefresh >= 15 ? storedRefresh : 60
        displayMode = defaults.string(forKey: "displayMode") ?? "remainingPercent"
        launchAtLogin = defaults.bool(forKey: "launchAtLogin")
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
