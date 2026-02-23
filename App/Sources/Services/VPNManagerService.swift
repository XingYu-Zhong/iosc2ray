import Foundation
@preconcurrency import NetworkExtension

actor VPNManagerService {
    static let tunnelBundleIdentifier = "com.zxy.iosv2ray.PacketTunnel"

    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?

    func install(profile: VPNProfile) async throws {
        let manager = try await loadOrCreateManager()
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = Self.tunnelBundleIdentifier
        proto.serverAddress = profile.endpoint.host
        proto.providerConfiguration = try TunnelProviderConfigurationBuilder.makeConfiguration(profile: profile)

        manager.protocolConfiguration = proto
        manager.localizedDescription = "iosv2ray: \(profile.name)"
        manager.isEnabled = true
        manager.isOnDemandEnabled = profile.onDemandEnabled
        manager.onDemandRules = profile.onDemandEnabled ? [NEOnDemandRuleConnect()] : []

        try await savePreferences(manager)
        self.manager = manager
        observeStatusIfNeeded(for: manager)
    }

    func connect() async throws {
        let manager = try await loadOrCreateManager()
        try await loadPreferences(manager)
        observeStatusIfNeeded(for: manager)
        try manager.connection.startVPNTunnel()
    }

    func disconnect() async throws {
        let manager = try await loadOrCreateManager()
        manager.connection.stopVPNTunnel()
    }

    func currentStatus() async throws -> NEVPNStatus {
        let manager = try await loadOrCreateManager()
        return manager.connection.status
    }

    nonisolated func startObservingStatus(onUpdate: @escaping (NEVPNStatus) -> Void) {
        Task { [weak self] in
            guard let self else { return }
            let manager = try? await self.loadOrCreateManager()
            if let manager {
                await self.observeStatusIfNeeded(for: manager, onUpdate: onUpdate)
            }
        }
    }

    private func observeStatusIfNeeded(
        for manager: NETunnelProviderManager,
        onUpdate: ((NEVPNStatus) -> Void)? = nil
    ) {
        if statusObserver != nil {
            return
        }

        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: manager.connection,
            queue: .main
        ) { _ in
            onUpdate?(manager.connection.status)
        }
    }

    private func loadOrCreateManager() async throws -> NETunnelProviderManager {
        if let manager {
            return manager
        }

        let allManagers = try await loadAllManagers()
        if let existing = allManagers.first {
            self.manager = existing
            return existing
        }

        let created = NETunnelProviderManager()
        self.manager = created
        return created
    }

    private func loadAllManagers() async throws -> [NETunnelProviderManager] {
        try await withCheckedThrowingContinuation { continuation in
            NETunnelProviderManager.loadAllFromPreferences { managers, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: managers ?? [])
            }
        }
    }

    private func savePreferences(_ manager: NETunnelProviderManager) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            manager.saveToPreferences { error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: ())
            }
        }
    }

    private func loadPreferences(_ manager: NETunnelProviderManager) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            manager.loadFromPreferences { error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: ())
            }
        }
    }
}
