import Foundation

// MARK: - 数据模型

struct AFPWindow: Identifiable {
    let id: String
    let title: String
    let used: Double
    let quota: Double
    let resetTime: Date?
    let startTime: Date?

    var ratio: Double { quota > 0 ? min(1, max(0, used / quota)) : 0 }
    var remaining: Double { max(0, quota - used) }
    var percentText: String { String(format: "%.1f%%", ratio * 100) }
    var hasQuota: Bool { quota > 0 }
}

struct AFPSnapshot {
    var planType: String
    var windows: [AFPWindow]

    func window(_ id: String) -> AFPWindow? { windows.first { $0.id == id } }
}

struct PlanInfo {
    var plan: String        // AgentPlan / CodingPlan
    var planType: String    // Small / Medium / Large / Max / Lite / Pro
    var status: String      // Running / Expired
    var startTime: String?
    var endTime: String?
    var autoRenew: Bool?
}

struct UsageRow: Identifiable {
    var id: String { "\(model)|\(unit)|\(billingType)" }
    let model: String
    let unit: String
    let billingType: String   // WithinPlan / OutsideOfPlan
    let usage: Double
    let time: Date?
}

enum ArkError: LocalizedError {
    case http(Int, String)
    case api(String, String)
    case noPlan
    case badPayload(String)

    var errorDescription: String? {
        switch self {
        case .http(let code, let msg): return "HTTP \(code)：\(msg)"
        case .api(let code, let msg): return "\(code)：\(msg)"
        case .noPlan: return "当前账号未查询到生效中的套餐"
        case .badPayload(let msg): return "响应解析失败：\(msg)"
        }
    }
}

// MARK: - 客户端

final class ArkClient {
    static let host = "ark.cn-beijing.volcengineapi.com"

    let ak: String
    let sk: String
    private let session: URLSession

    init(ak: String, sk: String) {
        self.ak = ak
        self.sk = sk
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 25
        self.session = URLSession(configuration: config)
    }

    // MARK: 底层调用

    private func rawCall(_ action: String, body: [String: Any]) async throws -> [String: Any] {
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let signer = VolcSigner(ak: ak, sk: sk, host: Self.host,
                                region: "cn-beijing", service: "ark")
        let request = signer.signedRequest(action: action, body: bodyData)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ArkError.http(0, "网络请求失败：\(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else {
            throw ArkError.http(0, "无 HTTP 响应")
        }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        if let error = (json?["ResponseMetadata"] as? [String: Any])?["Error"] as? [String: Any] {
            let code = error["Code"] as? String ?? "Unknown"
            let message = error["Message"] as? String ?? ""
            if code.contains("Signature") { throw ArkError.api(code, "\(message)（请检查 AK/SK 是否正确、系统时间是否准确）") }
            throw ArkError.api(code, message)
        }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw ArkError.http(http.statusCode, String(text.prefix(200)))
        }
        guard let json else { throw ArkError.badPayload("非 JSON 响应") }
        return json
    }

    private func result(_ action: String, body: [String: Any] = [:]) async throws -> [String: Any] {
        let json = try await rawCall(action, body: body)
        return (json["Result"] as? [String: Any]) ?? json
    }

    // MARK: AFP 额度

    func fetchAFP() async throws -> AFPSnapshot {
        let res = try await result("GetAFPUsage")

        func parse(_ key: String, _ title: String, _ id: String) -> AFPWindow? {
            guard let dict = res[key] as? [String: Any] else { return nil }
            return AFPWindow(id: id,
                             title: title,
                             used: num(dict["Used"]) ?? 0,
                             quota: num(dict["Quota"]) ?? 0,
                             resetTime: date(dict["ResetTime"]),
                             startTime: date(dict["SubscribeTime"]))
        }

        var windows: [AFPWindow] = []
        if let w = parse("AFPFiveHour", "5 小时", "fiveHour") { windows.append(w) }
        if let w = parse("AFPDaily", "今日", "daily") { windows.append(w) }
        if let w = parse("AFPWeekly", "本周", "weekly") { windows.append(w) }
        if let w = parse("AFPMonthly", "本月", "monthly") { windows.append(w) }
        guard !windows.isEmpty else { throw ArkError.badPayload("GetAFPUsage 未返回 AFPF* 字段") }

        let planType = (res["PlanType"] as? String)
            ?? ((try? JSONSerialization.jsonObject(with: JSONSerialization.data(withJSONObject: res))) as? [String: Any])?["PlanType"] as? String
            ?? ""
        return AFPSnapshot(planType: planType, windows: windows)
    }

    // MARK: 套餐信息

    func fetchPlan(_ plan: String) async throws -> PlanInfo {
        let res = try await result("GetPersonalPlan", body: ["Plan": plan])
        return PlanInfo(plan: plan,
                        planType: res["PlanType"] as? String ?? "-",
                        status: res["Status"] as? String ?? "-",
                        startTime: res["StartTime"] as? String,
                        endTime: res["EndTime"] as? String,
                        autoRenew: res["AutoRenew"] as? Bool)
    }

    /// 依次尝试 AgentPlan / CodingPlan，返回生效中的那个
    func fetchActivePlan() async throws -> PlanInfo? {
        var lastError: Error?
        for plan in ["AgentPlan", "CodingPlan"] {
            do {
                let info = try await fetchPlan(plan)
                if info.status == "Running" { return info }
                if plan == "AgentPlan" { lastError = ArkError.noPlan }
            } catch {
                lastError = error
            }
        }
        if let lastError { throw lastError }
        return nil
    }

    // MARK: 模型用量明细

    func fetchUsage(for day: Date = Date()) async throws -> [UsageRow] {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = .current
        fmt.dateFormat = "yyyy-MM-dd"
        let dayString = fmt.string(from: day)

        let res = try await result("GetUsageDetails", body: [
            "QueryInterval": "Day",
            "Filter": ["StartTime": dayString, "EndTime": dayString]
        ])

        guard let details = res["Details"] as? [[String: Any]] else { return [] }
        var rows: [UsageRow] = []
        for item in details {
            let model = item["ObjectName"] as? String ?? "unknown"
            let usage = num(item["Usage"]) ?? 0
            if usage <= 0 { continue }
            rows.append(UsageRow(model: model,
                                 unit: item["Unit"] as? String ?? "Tokens",
                                 billingType: item["BillingType"] as? String ?? "WithinPlan",
                                 usage: usage,
                                 time: date(item["Time"])))
        }
        return rows.sorted { $0.usage > $1.usage }
    }

    /// 支持的模型列表（可选，用于展示）
    func fetchModels() async throws -> [String] {
        let res = try await result("ListArkAgentPlanModel", body: ["Edition": "personal"])
        let datas = res["Datas"] as? [[String: Any]] ?? []
        return datas.compactMap { $0["ModelID"] as? String }
    }

    // MARK: 工具

    private func num(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let s = any as? String { return Double(s) }
        if let n = any as? NSNumber { return n.doubleValue }
        return nil
    }

    private func date(_ any: Any?) -> Date? {
        guard let ms = num(any), ms > 0 else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }
}
