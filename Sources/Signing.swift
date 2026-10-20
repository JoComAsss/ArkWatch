import Foundation
import CryptoKit

/// 火山引擎（Volcengine）AK/SK 签名，遵循官方《签名方法》规范。
/// 算法与官方测试向量一致（见 --selftest）。
struct VolcSigner {
    let ak: String
    let sk: String
    let host: String
    let region: String
    let service: String

    static func timestamp(_ date: Date) -> (full: String, short: String) {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let full = f.string(from: date)
        return (full, String(full.prefix(8)))
    }

    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    static func sha256Hex(_ string: String) -> String {
        hex(Data(SHA256.hash(data: Data(string.utf8))))
    }

    static func hmac(_ key: Data, _ message: String) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: SymmetricKey(data: key)))
    }

    func signature(action: String,
                   version: String,
                   body: Data,
                   date: Date,
                   method: String = "POST",
                   headerNames: [String] = ["host", "x-content-sha256", "x-date"]) -> (signature: String, canonical: String, stringToSign: String, payloadHash: String, xDate: String, scope: String) {
        let (xDate, shortDate) = Self.timestamp(date)
        let payloadHash = Self.hex(Data(SHA256.hash(data: body)))
        let query = "Action=\(action)&Version=\(version)"

        let headerValues: [String: String] = ["host": host,
                                              "x-content-sha256": payloadHash,
                                              "x-date": xDate]
        let canonicalHeaders = headerNames
            .map { "\($0):\(headerValues[$0] ?? "")\n" }
            .joined()
        let signedHeaders = headerNames.joined(separator: ";")
        // canonicalHeaders 自身以 \n 结尾，再拼接一次换行即形成一个空行
        let canonicalRequest = [method, "/", query, canonicalHeaders, signedHeaders, payloadHash]
            .joined(separator: "\n")
        let scope = "\(shortDate)/\(region)/\(service)/request"
        let stringToSign = ["HMAC-SHA256", xDate, scope, Self.sha256Hex(canonicalRequest)]
            .joined(separator: "\n")

        let kDate = Self.hmac(Data(sk.utf8), shortDate)
        let kRegion = Self.hmac(kDate, region)
        let kService = Self.hmac(kRegion, service)
        let kSigning = Self.hmac(kService, "request")
        let signature = Self.hex(Self.hmac(kSigning, stringToSign))
        return (signature, canonicalRequest, stringToSign, payloadHash, xDate, scope)
    }

    func signedRequest(action: String,
                       version: String = "2024-01-01",
                       body: Data,
                       date: Date = Date()) -> URLRequest {
        let (xDate, shortDate) = Self.timestamp(date)
        let query = "Action=\(action)&Version=\(version)"
        let signed = signature(action: action, version: version, body: body, date: date)
        _ = shortDate
        let signedHeaders = "host;x-content-sha256;x-date"
        let authorization = "HMAC-SHA256 Credential=\(ak)/\(signed.scope), SignedHeaders=\(signedHeaders), Signature=\(signed.signature)"
        let payloadHash = signed.payloadHash

        var request = URLRequest(url: URL(string: "https://\(host)/?\(query)")!)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 20
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        request.setValue(xDate, forHTTPHeaderField: "X-Date")
        request.setValue(payloadHash, forHTTPHeaderField: "X-Content-Sha256")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}

/// 自检：使用官方文档中的测试向量校验签名实现
enum SignatureSelfTest {
    static func run() -> Bool {
        let ak = "AKLTYWViMTVmZGYzM2E0NDI5Mzk2MDZjNjFmMjc2MjRjMzg"
        let sk = "WkRZeE1EQmxPVGhsWWpWak5HVmtNbUUxTXpZeU9UVXlOMlE1TmpZeVlqTQ=="
        let signer = VolcSigner(ak: ak, sk: sk, host: "billing.volcengineapi.com",
                                region: "cn-beijing", service: "billing")
        var comps = DateComponents()
        comps.year = 2025; comps.month = 3; comps.day = 29
        comps.hour = 18; comps.minute = 9; comps.second = 37
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = utc.date(from: comps)! // 2025-03-29T18:09:37Z
        let expected = "1eda9e7e6b1728151a8e8791fdaf67cfbd28bd5c80d0fce2eb208746cf483105"

        let signed = signer.signature(action: "QueryBalanceAcct",
                                      version: "2022-01-01",
                                      body: Data(),
                                      date: date,
                                      method: "GET",
                                      headerNames: ["host", "x-date"])
        let okDate = signed.xDate == "20250329T180937Z"
        let okSig = signed.signature == expected
        print("X-Date   : \(signed.xDate) \(okDate ? "PASS" : "FAIL")")
        print("Signature: \(signed.signature) \(okSig ? "PASS" : "FAIL")")
        if !okSig {
            print("---- CanonicalRequest ----")
            print(signed.canonical)
            print("---- StringToSign ----")
            print(signed.stringToSign)
        }
        print(okDate && okSig ? "SELFTEST PASS" : "SELFTEST FAIL")
        return okDate && okSig
    }
}
