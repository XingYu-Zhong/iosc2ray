import Foundation
@preconcurrency import NetworkExtension

actor VPNManagerService {
    static var tunnelBundleIdentifier: String {
        if let bundleID = Bundle.main.bundleIdentifier, !bundleID.isEmpty {
            return "\(bundleID).PacketTunnel"
        }
        return "com.zxy.iosv2ray.PacketTunnel"
    }

    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?
    private var statusUpdateHandler: ((NEVPNStatus, String?) -> Void)?

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
        TunnelRuntimeDiagnostics.clearLastStartError()
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

    nonisolated func startObservingStatus(onUpdate: @escaping (NEVPNStatus, String?) -> Void) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let manager = try await self.loadOrCreateManager()
                await self.observeStatusIfNeeded(for: manager, onUpdate: onUpdate)
            } catch {
                onUpdate(.invalid, error.localizedDescription)
            }
        }
    }

    private func observeStatusIfNeeded(
        for manager: NETunnelProviderManager,
        onUpdate: ((NEVPNStatus, String?) -> Void)? = nil
    ) {
        if let onUpdate {
            statusUpdateHandler = onUpdate
        }

        if statusObserver != nil {
            let status = manager.connection.status
            emitStatus(status, disconnectError: resolveDisconnectError(for: status))
            return
        }

        let initialStatus = manager.connection.status
        emitStatus(initialStatus, disconnectError: resolveDisconnectError(for: initialStatus))

        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: manager.connection,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let status = manager.connection.status
            Task { [weak self] in
                guard let self else { return }
                let disconnectError = await self.resolveDisconnectError(for: status)
                await self.emitStatus(status, disconnectError: disconnectError)
            }
        }
    }

    private func emitStatus(_ status: NEVPNStatus, disconnectError: String? = nil) {
        statusUpdateHandler?(status, disconnectError)
    }

    private func resolveDisconnectError(for status: NEVPNStatus) -> String? {
        guard status == .disconnected || status == .invalid else {
            return nil
        }
        return TunnelRuntimeDiagnostics.readLastStartError()
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
