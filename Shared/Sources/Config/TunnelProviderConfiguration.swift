import Foundation

enum ProviderConfigKeys {
    static let profileData = "profileData"
    static let xrayJSON = "xrayJSON"
}

enum TunnelProviderConfigurationBuilder {
    static func makeConfiguration(profile: VPNProfile) throws -> [String: Any] {
        let profileData = try JSONEncoder().encode(profile)
        let profileJSONString = String(decoding: profileData, as: UTF8.self)
        let xrayJSON = try XrayConfigBuilder.build(profile: profile)

        return [
            ProviderConfigKeys.profileData: profileJSONString,
            ProviderConfigKeys.xrayJSON: xrayJSON
        ]
    }

    static func decodeProfile(from providerConfiguration: [String: Any]?) throws -> VPNProfile {
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
        return try JSONDecoder().decode(VPNProfile.self, from: profileData)
    }
}
