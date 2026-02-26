import Foundation

enum ProviderConfigKeys {
    static let profileData = "profileData"
    static let xrayJSON = "xrayJSON"
    static let tunnelMode = "tunnelMode"
}

struct TunnelRuntimeConfig {
    var profile: VPNProfile
    var mode: TunnelMode
}

enum TunnelRuntimeDiagnostics {
    static let appGroupID = "group.com.zxy.iosv2ray"

    private static let messageKey = "tunnel.runtime.lastStartError.message"
    private static let domainKey = "tunnel.runtime.lastStartError.domain"
    private static let codeKey = "tunnel.runtime.lastStartError.code"
    private static let timestampKey = "tunnel.runtime.lastStartError.timestamp"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func clearLastStartError() {
        guard let defaults else { return }
        defaults.removeObject(forKey: messageKey)
        defaults.removeObject(forKey: domainKey)
        defaults.removeObject(forKey: codeKey)
        defaults.removeObject(forKey: timestampKey)
    }

    static func writeLastStartError(_ error: Error) {
        guard let defaults else { return }
        let nsError = error as NSError
        defaults.set(nsError.localizedDescription, forKey: messageKey)
        defaults.set(nsError.domain, forKey: domainKey)
        defaults.set(nsError.code, forKey: codeKey)
        defaults.set(Date().timeIntervalSince1970, forKey: timestampKey)
    }

    static func readLastStartError(maxAge: TimeInterval = 45) -> String? {
        guard let defaults else { return nil }
        guard let message = defaults.string(forKey: messageKey), !message.isEmpty else {
            return nil
        }

        let timestamp = defaults.double(forKey: timestampKey)
        if timestamp > 0 {
            let age = Date().timeIntervalSince1970 - timestamp
            if age > maxAge {
                return nil
            }
        }

        let domain = defaults.string(forKey: domainKey) ?? ""
        let code = defaults.object(forKey: codeKey) as? Int
        guard !domain.isEmpty, let code else {
            return message
        }
        return "\(message) [\(domain):\(code)]"
    }
}

enum TunnelProviderConfigurationBuilder {
    static func makeConfiguration(
        profile: VPNProfile,
        mode: TunnelMode = .fullDevice
    ) throws -> [String: Any] {
        let profileData = try JSONEncoder().encode(profile)
        let profileJSONString = String(decoding: profileData, as: UTF8.self)
        let xrayJSON = try XrayConfigBuilder.build(profile: profile)

        return [
            ProviderConfigKeys.profileData: profileJSONString,
            ProviderConfigKeys.xrayJSON: xrayJSON,
            ProviderConfigKeys.tunnelMode: mode.rawValue
        ]
    }

    static func decodeRuntimeConfig(from providerConfiguration: [String: Any]?) throws -> TunnelRuntimeConfig {
        guard
            let providerConfiguration,
            let profileJSONString = providerConfiguration[ProviderConfigKeys.profileData] as? String,
            let profileData = profileJSONString.data(using: .utf8)
        else {
            throw NSError(
                domain: "iosv2ray.providerConfig",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "缺少 VPN Profile 配置"]
            )
        }
        let profile = try JSONDecoder().decode(VPNProfile.self, from: profileData)
        let modeRawValue = providerConfiguration[ProviderConfigKeys.tunnelMode] as? String
        let mode = TunnelMode(rawValue: modeRawValue ?? "") ?? .fullDevice
        return TunnelRuntimeConfig(profile: profile, mode: mode)
    }

    static func decodeProfile(from providerConfiguration: [String: Any]?) throws -> VPNProfile {
        try decodeRuntimeConfig(from: providerConfiguration).profile
    }
}
