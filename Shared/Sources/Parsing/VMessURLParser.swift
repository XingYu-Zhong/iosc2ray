import Foundation

enum VMessParseError: LocalizedError {
    case invalidScheme
    case invalidBase64Payload
    case invalidJSONPayload
    case missingField(String)
    case invalidPort
    case invalidUserID

    var errorDescription: String? {
        switch self {
        case .invalidScheme:
            return "VMess 链接必须以 vmess:// 开头"
        case .invalidBase64Payload:
            return "VMess 链接 Base64 部分无效"
        case .invalidJSONPayload:
            return "VMess 链接 JSON 结构无效"
        case let .missingField(key):
            return "VMess 链接缺少字段: \(key)"
        case .invalidPort:
            return "VMess 链接中的端口无效"
        case .invalidUserID:
            return "VMess 用户 ID 必须是 UUID"
        }
    }
}

enum VMessURLParser {
    static func parse(urlString: String) throws -> VMessEndpoint {
        let normalizedURL: String
        if urlString.hasPrefix("vmess://") {
            normalizedURL = urlString
        } else if urlString.hasPrefix("vemss://") {
            normalizedURL = "vmess://" + urlString.dropFirst("vemss://".count)
        } else {
            throw VMessParseError.invalidScheme
        }

        let encoded = String(normalizedURL.dropFirst("vmess://".count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let payloadData = decodeBase64URLSafe(encoded) else {
            throw VMessParseError.invalidBase64Payload
        }

        guard
            let object = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
        else {
            throw VMessParseError.invalidJSONPayload
        }

        let host = try string("add", in: object)
        let id = try string("id", in: object)
        guard UUID(uuidString: id) != nil else {
            throw VMessParseError.invalidUserID
        }
        let port = try int("port", in: object)
        guard (1 ... 65535).contains(port) else {
            throw VMessParseError.invalidPort
        }

        let alterId = (try? int("aid", in: object)) ?? 0
        let security = object["scy"] as? String ?? "auto"
        let network = object["net"] as? String ?? "tcp"
        let tls = object["tls"] as? String ?? ""

        return VMessEndpoint(
            host: host,
            port: port,
            id: id,
            alterId: alterId,
            security: security,
            network: network,
            tls: tls,
            sni: emptyToNil(object["sni"] as? String),
            hostHeader: emptyToNil(object["host"] as? String),
            path: emptyToNil(object["path"] as? String),
            remark: emptyToNil(object["ps"] as? String)
        )
    }

    private static func string(_ key: String, in object: [String: Any]) throws -> String {
        guard let value = object[key] as? String, !value.isEmpty else {
            throw VMessParseError.missingField(key)
        }
        return value
    }

    private static func int(_ key: String, in object: [String: Any]) throws -> Int {
        if let intValue = object[key] as? Int {
            return intValue
        }

        if let stringValue = object[key] as? String,
           let intValue = Int(stringValue) {
            return intValue
        }

        throw VMessParseError.missingField(key)
    }

    private static func emptyToNil(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func decodeBase64URLSafe(_ input: String) -> Data? {
        let normalized = input
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let paddingCount = (4 - (normalized.count % 4)) % 4
        let padded = normalized + String(repeating: "=", count: paddingCount)
        return Data(base64Encoded: padded)
    }
}
