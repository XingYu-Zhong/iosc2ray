import Foundation

enum TunnelMode: String, Codable, CaseIterable {
    case fullDevice
    case perAppManaged
}

struct VMessEndpoint: Codable, Equatable {
    var host: String
    var port: Int
    var id: String
    var alterId: Int
    var security: String
    var network: String
    var tls: String
    var sni: String?
    var hostHeader: String?
    var path: String?
    var remark: String?
}

struct VPNProfile: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var endpoint: VMessEndpoint
    var dnsServers: [String]
    var perAppBundleIDs: [String]
    var onDemandEnabled: Bool
    var bypassLAN: Bool

    init(
        id: UUID = UUID(),
        name: String,
        endpoint: VMessEndpoint,
        dnsServers: [String] = ["1.1.1.1", "8.8.8.8"],
        perAppBundleIDs: [String] = [],
        onDemandEnabled: Bool = false,
        bypassLAN: Bool = true
    ) {
        self.id = id
        self.name = name
        self.endpoint = endpoint
        self.dnsServers = dnsServers
        self.perAppBundleIDs = perAppBundleIDs
        self.onDemandEnabled = onDemandEnabled
        self.bypassLAN = bypassLAN
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case endpoint
        case dnsServers
        case perAppBundleIDs
        case onDemandEnabled
        case bypassLAN
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        endpoint = try container.decode(VMessEndpoint.self, forKey: .endpoint)
        dnsServers = try container.decodeIfPresent([String].self, forKey: .dnsServers) ?? ["1.1.1.1", "8.8.8.8"]
        perAppBundleIDs = try container.decodeIfPresent([String].self, forKey: .perAppBundleIDs) ?? []
        onDemandEnabled = try container.decodeIfPresent(Bool.self, forKey: .onDemandEnabled) ?? false
        bypassLAN = try container.decodeIfPresent(Bool.self, forKey: .bypassLAN) ?? true
    }
}
