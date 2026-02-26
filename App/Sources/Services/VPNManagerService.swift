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

    func install(profile: VPNProfile, mode: TunnelMode) async throws {
        let manager = try await loadOrCreateManager()
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = Self.tunnelBundleIdentifier
        proto.serverAddress = profile.endpoint.host
        proto.providerConfiguration = try TunnelProviderConfigurationBuilder.makeConfiguration(
            profile: profile,
            mode: mode
        )

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

struct MDMAutoBindConfig {
    var enabled: Bool
    var endpointURL: String
    var deviceIdentifier: String
    var apiToken: String
    var timeoutSeconds: TimeInterval = 15
}

struct MDMAutoBindResult {
    var accepted: Bool
    var message: String
    var requestID: String?
}

enum MDMAutoBindError: LocalizedError {
    case disabled
    case missingEndpoint
    case missingDeviceIdentifier
    case invalidEndpoint
    case rejected(statusCode: Int, message: String)
    case serverRejected(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .disabled:
            return "MDM 自动下发未启用"
        case .missingEndpoint:
            return "请填写 MDM API 地址"
        case .missingDeviceIdentifier:
            return "请填写设备标识（UDID/Serial）"
        case .invalidEndpoint:
            return "MDM API 地址无效"
        case let .rejected(statusCode, message):
            let tail = message.isEmpty ? "" : " - \(message)"
            return "MDM 接口拒绝请求（HTTP \(statusCode)\(tail)）"
        case let .serverRejected(message):
            return "MDM 接口拒绝请求：\(message)"
        case let .transport(message):
            return "请求 MDM 接口失败：\(message)"
        }
    }
}

struct MDMAutoBindService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func submitPerAppBinding(
        profile: VPNProfile,
        tunnelBundleID: String,
        export: PerAppMDMExport,
        bundleIDs: [String],
        config: MDMAutoBindConfig
    ) async throws -> MDMAutoBindResult {
        guard config.enabled else {
            throw MDMAutoBindError.disabled
        }

        let endpoint = config.endpointURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !endpoint.isEmpty else {
            throw MDMAutoBindError.missingEndpoint
        }

        let deviceIdentifier = config.deviceIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !deviceIdentifier.isEmpty else {
            throw MDMAutoBindError.missingDeviceIdentifier
        }

        guard
            let url = URL(string: endpoint),
            let scheme = url.scheme?.lowercased(),
            scheme == "https" || scheme == "http"
        else {
            throw MDMAutoBindError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = config.timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !config.apiToken.isEmpty {
            request.setValue("Bearer \(config.apiToken)", forHTTPHeaderField: "Authorization")
        }

        let payload = MDMAutoBindRequest(
            profileName: profile.name,
            vpnUUID: export.vpnUUID,
            tunnelBundleID: tunnelBundleID,
            deviceIdentifier: deviceIdentifier,
            bundleIDs: bundleIDs,
            mobileConfigXML: export.mobileConfigXML,
            settingsCommandJSON: export.settingsCommandJSON,
            installProfileDeviceCommandPlist: export.installProfileDeviceCommandPlist,
            settingsDeviceCommandPlist: export.settingsDeviceCommandPlist
        )
        request.httpBody = try JSONEncoder().encode(payload)

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw MDMAutoBindError.transport("无效响应")
            }

            let bodyMessage = sanitizeBodyMessage(data)
            guard (200 ..< 300).contains(httpResponse.statusCode) else {
                throw MDMAutoBindError.rejected(statusCode: httpResponse.statusCode, message: bodyMessage)
            }

            if data.isEmpty {
                return MDMAutoBindResult(
                    accepted: true,
                    message: "MDM 请求已提交",
                    requestID: nil
                )
            }

            if let envelope = try? JSONDecoder().decode(MDMAutoBindResponseEnvelope.self, from: data) {
                let accepted = envelope.accepted ?? true
                let message = envelope.message ?? "MDM 请求已提交"
                let requestID = envelope.requestID ?? envelope.requestId
                if !accepted {
                    throw MDMAutoBindError.serverRejected(message)
                }
                return MDMAutoBindResult(accepted: accepted, message: message, requestID: requestID)
            }

            let fallbackMessage = bodyMessage.isEmpty ? "MDM 请求已提交" : bodyMessage
            return MDMAutoBindResult(accepted: true, message: fallbackMessage, requestID: nil)
        } catch let error as MDMAutoBindError {
            throw error
        } catch {
            throw MDMAutoBindError.transport(error.localizedDescription)
        }
    }

    private func sanitizeBodyMessage(_ data: Data) -> String {
        guard let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 300 {
            return trimmed
        }
        return String(trimmed.prefix(300))
    }
}

private struct MDMAutoBindRequest: Encodable {
    var action = "per_app_vpn_bind"
    var profileName: String
    var vpnUUID: String
    var tunnelBundleID: String
    var deviceIdentifier: String
    var bundleIDs: [String]
    var mobileConfigXML: String
    var settingsCommandJSON: String
    var installProfileDeviceCommandPlist: String
    var settingsDeviceCommandPlist: String
    var requestedAt: String

    init(
        profileName: String,
        vpnUUID: String,
        tunnelBundleID: String,
        deviceIdentifier: String,
        bundleIDs: [String],
        mobileConfigXML: String,
        settingsCommandJSON: String,
        installProfileDeviceCommandPlist: String,
        settingsDeviceCommandPlist: String
    ) {
        self.profileName = profileName
        self.vpnUUID = vpnUUID
        self.tunnelBundleID = tunnelBundleID
        self.deviceIdentifier = deviceIdentifier
        self.bundleIDs = bundleIDs
        self.mobileConfigXML = mobileConfigXML
        self.settingsCommandJSON = settingsCommandJSON
        self.installProfileDeviceCommandPlist = installProfileDeviceCommandPlist
        self.settingsDeviceCommandPlist = settingsDeviceCommandPlist
        self.requestedAt = ISO8601DateFormatter().string(from: Date())
    }
}

private struct MDMAutoBindResponseEnvelope: Decodable {
    var accepted: Bool?
    var message: String?
    var requestID: String?
    var requestId: String?
}
