import Foundation

enum ProfileStoreError: LocalizedError {
    case profileNotFound

    var errorDescription: String? {
        switch self {
        case .profileNotFound:
            return "指定配置不存在"
        }
    }
}

actor ProfileStore {
    static let shared = ProfileStore()

    private let storageKey = "vpn.profiles"
    private let suiteName = "group.com.zxy.iosv2ray"
    private let vmessIDPlaceholder = "__KEYCHAIN__"
    private let secretStore = KeychainSecretStore(service: "com.zxy.iosv2ray.vmess")

    private var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    func allProfiles() -> [VPNProfile] {
        loadStoredProfiles().map { profile in
            var hydrated = profile
            if hydrated.endpoint.id == vmessIDPlaceholder,
               let secret = try? secretStore.getString(account: vmessIDAccount(for: hydrated.id)) {
                hydrated.endpoint.id = secret
            }
            return hydrated
        }
    }

    func upsert(_ profile: VPNProfile) throws -> [VPNProfile] {
        try secretStore.setString(profile.endpoint.id, account: vmessIDAccount(for: profile.id))

        var profiles = loadStoredProfiles()
        var storable = profile
        storable.endpoint.id = vmessIDPlaceholder

        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = storable
        } else {
            profiles.append(storable)
        }

        try persist(profiles.map(redactedProfile(_:)))
        return allProfiles()
    }

    func delete(profileID: UUID) throws -> [VPNProfile] {
        var profiles = loadStoredProfiles()
        let originalCount = profiles.count
        profiles.removeAll { $0.id == profileID }
        guard profiles.count != originalCount else {
            throw ProfileStoreError.profileNotFound
        }

        try secretStore.delete(account: vmessIDAccount(for: profileID))
        try persist(profiles.map(redactedProfile(_:)))
        return allProfiles()
    }

    func profile(by id: UUID) -> VPNProfile? {
        allProfiles().first { $0.id == id }
    }

    private func persist(_ profiles: [VPNProfile]) throws {
        let data = try JSONEncoder().encode(profiles)
        defaults.set(data, forKey: storageKey)
    }

    private func loadStoredProfiles() -> [VPNProfile] {
        guard
            let data = defaults.data(forKey: storageKey),
            let profiles = try? JSONDecoder().decode([VPNProfile].self, from: data)
        else {
            return []
        }
        return profiles
    }

    private func redactedProfile(_ profile: VPNProfile) -> VPNProfile {
        var redacted = profile
        redacted.endpoint.id = vmessIDPlaceholder
        return redacted
    }

    private func vmessIDAccount(for profileID: UUID) -> String {
        "vmess.endpoint.id.\(profileID.uuidString)"
    }
}
