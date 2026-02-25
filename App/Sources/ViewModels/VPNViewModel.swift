import Foundation
import NetworkExtension
#if canImport(UIKit)
import UIKit
#endif

struct ProbeHistoryItem: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let host: String
    let port: Int
    let latencyMS: Int?
    let reachable: Bool
    let message: String

    init(
        id: UUID = UUID(),
        date: Date = .now,
        host: String,
        port: Int,
        latencyMS: Int?,
        reachable: Bool,
        message: String
    ) {
        self.id = id
        self.date = date
        self.host = host
        self.port = port
        self.latencyMS = latencyMS
        self.reachable = reachable
        self.message = message
    }
}

@MainActor
final class VPNViewModel: ObservableObject {
    @Published var vmessLink = ""
    @Published var profileName = ""
    @Published var dnsCSV = "1.1.1.1,8.8.8.8"
    @Published var perAppBundleIDsCSV = ""
    @Published var mode: TunnelMode = .fullDevice
    @Published var onDemandEnabled = false
    @Published var bypassLAN = true
    @Published var statusText = "未连接"
    @Published var lastError = ""
    @Published var exportedMDMProfile = ""
    @Published var exportedMDMSettingsCommand = ""
    @Published var exportedMDMSettingsDeviceCommand = ""
    @Published var exportedMDMInstallProfileCommand = ""
    @Published var perAppModeHint = "按应用 VPN 需通过 MDM 下发（受管设备/受管应用）。"
    @Published var probeText = ""
    @Published var probeHistory: [ProbeHistoryItem] = []
    @Published var copyStatusText = ""

    @Published var profiles: [VPNProfile] = []
    @Published var selectedProfileID: UUID?

    private let managerService = VPNManagerService()
    private let profileStore = ProfileStore.shared
    private let probeService = EndpointProbeService()
    private var parsedEndpoint: VMessEndpoint?
    private var awaitingConnectResult = false

    init() {
        managerService.startObservingStatus { [weak self] status, disconnectError in
            Task { @MainActor in
                self?.statusText = VPNViewModel.describe(status)
                if let disconnectError, !disconnectError.isEmpty {
                    self?.lastError = disconnectError
                }

                guard let self else { return }
                switch status {
                case .connected:
                    self.awaitingConnectResult = false
                    self.lastError = ""
                case .disconnected:
                    if self.awaitingConnectResult {
                        self.awaitingConnectResult = false
                        if self.lastError.isEmpty {
                            self.lastError = self.connectionFailureHint()
                        }
                    }
                default:
                    break
                }
            }
        }

        Task {
            do {
                let status = try await managerService.currentStatus()
                statusText = VPNViewModel.describe(status)
            } catch {
                lastError = error.localizedDescription
            }

            await loadProfiles()
        }
    }

    func handleIncomingURL(_ url: URL) {
        guard url.scheme?.lowercased() == "vmess" else {
            return
        }

        vmessLink = url.absoluteString
        importVMess()
    }

    func importVMess() {
        do {
            let endpoint = try VMessURLParser.parse(urlString: vmessLink)
            parsedEndpoint = endpoint

            if profileName.isEmpty {
                profileName = endpoint.remark ?? "vmess-\(endpoint.host)"
            }
            lastError = ""
            probeText = ""
            exportedMDMProfile = ""
            exportedMDMSettingsCommand = ""
            exportedMDMSettingsDeviceCommand = ""
            exportedMDMInstallProfileCommand = ""
            copyStatusText = ""
        } catch {
            lastError = error.localizedDescription
        }
    }

    func importVMessFromClipboard() {
#if canImport(UIKit)
        guard let raw = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else {
            lastError = "剪贴板为空"
            return
        }

        guard let link = extractVMessLink(from: raw) else {
            lastError = "剪贴板中未找到 vmess:// 链接"
            return
        }

        vmessLink = link
        importVMess()
#else
        lastError = "当前平台不支持剪贴板导入"
#endif
    }

    func loadSelectedProfileToForm() {
        guard
            let selectedProfileID,
            let profile = profiles.first(where: { $0.id == selectedProfileID })
        else {
            return
        }

        parsedEndpoint = profile.endpoint
        profileName = profile.name
        dnsCSV = profile.dnsServers.joined(separator: ",")
        perAppBundleIDsCSV = profile.perAppBundleIDs.joined(separator: ",")
        mode = profile.mode
        onDemandEnabled = profile.onDemandEnabled
        bypassLAN = profile.bypassLAN
        lastError = ""
        probeText = ""
    }

    func saveCurrentProfile() async {
        do {
            let profile = try profileFromForm(preferExistingID: selectedProfileID)
            profiles = try await profileStore.upsert(profile)
            selectedProfileID = profile.id
            lastError = ""
        } catch {
            lastError = error.localizedDescription
        }
    }

    func deleteSelectedProfile() async {
        do {
            guard let selectedProfileID else {
                throw NSError(
                    domain: "iosv2ray.viewmodel",
                    code: 10,
                    userInfo: [NSLocalizedDescriptionKey: "请先选择一个配置"]
                )
            }

            profiles = try await profileStore.delete(profileID: selectedProfileID)
            self.selectedProfileID = profiles.first?.id
            if self.selectedProfileID != nil {
                loadSelectedProfileToForm()
            } else {
                clearForm()
            }
            lastError = ""
        } catch {
            lastError = error.localizedDescription
        }
    }

    func connect() async {
#if targetEnvironment(simulator)
        lastError = "iOS 模拟器不支持 Network Extension 隧道连接。请在真机上测试“连接隧道”。"
#else
        do {
            awaitingConnectResult = true
            let profile: VPNProfile
            if let selectedProfileID,
               let existing = profiles.first(where: { $0.id == selectedProfileID }) {
                profile = existing
            } else {
                profile = try profileFromForm(preferExistingID: nil)
            }

            try validateSecret(profile: profile)
            try validatePerAppRuntimeMode(profile: profile)

            try await managerService.install(profile: profile)
            try await managerService.connect()
            scheduleConnectResultTimeoutCheck()
            lastError = ""
        } catch {
            awaitingConnectResult = false
            lastError = formatConnectError(error)
        }
#endif
    }

    func testEndpointReachability() async {
        do {
            let endpoint = try currentEndpointForProbe()
            probeText = "测试中..."
            let result = await probeService.probe(host: endpoint.host, port: endpoint.port)
            if let latency = result.latencyMS {
                probeText = "\(result.message)，延迟 \(latency)ms"
            } else {
                probeText = result.message
            }

            appendProbeHistory(
                ProbeHistoryItem(
                    host: endpoint.host,
                    port: endpoint.port,
                    latencyMS: result.latencyMS,
                    reachable: result.reachable,
                    message: result.message
                )
            )
        } catch {
            probeText = "测试失败: \(error.localizedDescription)"
            appendProbeHistory(
                ProbeHistoryItem(
                    host: "未知",
                    port: 0,
                    latencyMS: nil,
                    reachable: false,
                    message: "测试失败: \(error.localizedDescription)"
                )
            )
        }
    }

    func disconnect() async {
        do {
            try await managerService.disconnect()
            lastError = ""
        } catch {
            lastError = error.localizedDescription
        }
    }

    func exportMDMProfile() {
        do {
            let profile = try profileFromForm(preferExistingID: selectedProfileID)
            guard profile.mode == .perAppManaged else {
                throw NSError(
                    domain: "iosv2ray.viewmodel",
                    code: 11,
                    userInfo: [NSLocalizedDescriptionKey: "仅按应用模式可导出 MDM Per-App 配置"]
                )
            }
            guard !profile.perAppBundleIDs.isEmpty else {
                throw NSError(
                    domain: "iosv2ray.viewmodel",
                    code: 12,
                    userInfo: [NSLocalizedDescriptionKey: "请至少填写一个应用 Bundle ID"]
                )
            }

            let export = MDMPerAppPayloadBuilder.build(
                profile: profile,
                tunnelBundleID: VPNManagerService.tunnelBundleIdentifier
            )
            exportedMDMProfile = export.mobileConfigXML
            exportedMDMSettingsCommand = export.settingsCommandJSON
            exportedMDMSettingsDeviceCommand = export.settingsDeviceCommandPlist
            exportedMDMInstallProfileCommand = export.installProfileDeviceCommandPlist
            lastError = ""
        } catch {
            lastError = error.localizedDescription
        }
    }

    func copyText(_ text: String, label: String) {
#if canImport(UIKit)
        UIPasteboard.general.string = text
        copyStatusText = "已复制: \(label)"
#else
        copyStatusText = "当前平台不支持复制"
#endif
    }

    func clearProbeHistory() {
        probeHistory.removeAll()
    }

    private func loadProfiles() async {
        profiles = await profileStore.allProfiles()
        if selectedProfileID == nil {
            selectedProfileID = profiles.first?.id
        }
    }

    private func clearForm() {
        vmessLink = ""
        profileName = ""
        dnsCSV = "1.1.1.1,8.8.8.8"
        perAppBundleIDsCSV = ""
        mode = .fullDevice
        onDemandEnabled = false
        bypassLAN = true
        parsedEndpoint = nil
        exportedMDMProfile = ""
        exportedMDMSettingsCommand = ""
        exportedMDMSettingsDeviceCommand = ""
        exportedMDMInstallProfileCommand = ""
        copyStatusText = ""
    }

    private func appendProbeHistory(_ item: ProbeHistoryItem) {
        probeHistory.insert(item, at: 0)
        if probeHistory.count > 20 {
            probeHistory.removeLast(probeHistory.count - 20)
        }
    }

    private func profileFromForm(preferExistingID: UUID?) throws -> VPNProfile {
        let endpoint: VMessEndpoint
        if let parsedEndpoint {
            endpoint = parsedEndpoint
        } else {
            endpoint = try VMessURLParser.parse(urlString: vmessLink)
            parsedEndpoint = endpoint
        }

        let bundleIDs = normalizeBundleIDs(parseCSV(perAppBundleIDsCSV))
        for bundleID in bundleIDs {
            if !isValidBundleID(bundleID) {
                throw NSError(
                    domain: "iosv2ray.viewmodel",
                    code: 13,
                    userInfo: [NSLocalizedDescriptionKey: "Bundle ID 格式非法: \(bundleID)"]
                )
            }
        }

        return VPNProfile(
            id: preferExistingID ?? UUID(),
            name: profileName.isEmpty ? (endpoint.remark ?? "iosv2ray") : profileName,
            endpoint: endpoint,
            dnsServers: parseCSV(dnsCSV),
            perAppBundleIDs: bundleIDs,
            mode: mode,
            onDemandEnabled: onDemandEnabled,
            bypassLAN: bypassLAN
        )
    }

    private func currentEndpointForProbe() throws -> VMessEndpoint {
        if let selectedProfileID,
           let existing = profiles.first(where: { $0.id == selectedProfileID }) {
            return existing.endpoint
        }

        if let parsedEndpoint {
            return parsedEndpoint
        }

        return try VMessURLParser.parse(urlString: vmessLink)
    }

    private func validateSecret(profile: VPNProfile) throws {
        if profile.endpoint.id == "__KEYCHAIN__" {
            throw NSError(
                domain: "iosv2ray.viewmodel",
                code: 14,
                userInfo: [NSLocalizedDescriptionKey: "配置密钥丢失，请重新导入 VMess 后保存"]
            )
        }
    }

    private func validatePerAppRuntimeMode(profile: VPNProfile) throws {
        guard profile.mode == .perAppManaged else {
            return
        }

        throw NSError(
            domain: "iosv2ray.viewmodel",
            code: 15,
            userInfo: [
                NSLocalizedDescriptionKey: "按应用模式不能在 App 内直接发起全局隧道。请先在 MDM 下发 Per-App VPN profile，并通过 VPNUUID 将目标应用绑定到该隧道。"
            ]
        )
    }

    private func connectionFailureHint() -> String {
        var hints: [String] = ["VPN 隧道启动失败。"]

        #if targetEnvironment(simulator)
        hints.append("当前是 iOS 模拟器，模拟器不支持 Packet Tunnel。")
        #endif

        hints.append("请在真机测试，并确认 PacketTunnel 已链接 LibXray.xcframework。")
        return hints.joined(separator: " ")
    }

    private func scheduleConnectResultTimeoutCheck() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            await self?.validateConnectResultIfNeeded()
        }
    }

    private func validateConnectResultIfNeeded() async {
        guard awaitingConnectResult else {
            return
        }

        do {
            let status = try await managerService.currentStatus()
            statusText = VPNViewModel.describe(status)

            switch status {
            case .connected:
                awaitingConnectResult = false
                lastError = ""
            case .connecting, .reasserting, .disconnecting:
                break
            case .disconnected, .invalid:
                awaitingConnectResult = false
                if lastError.isEmpty {
                    lastError = connectionFailureHint()
                }
            @unknown default:
                awaitingConnectResult = false
                if lastError.isEmpty {
                    lastError = connectionFailureHint()
                }
            }
        } catch {
            awaitingConnectResult = false
            if lastError.isEmpty {
                lastError = "\(connectionFailureHint()) \(error.localizedDescription)"
            }
        }
    }

    private func formatConnectError(_ error: Error) -> String {
        let nsError = error as NSError
        let raw = nsError.localizedDescription
        let normalized = raw.lowercased()

        if normalized.contains("permission") || normalized.contains("not entitled") || normalized.contains("entitle") {
            return "系统拒绝 VPN 权限（\(raw)）。请确认 App 与 PacketTunnel 都已启用 Network Extensions (Packet Tunnel)，并使用支持该能力的开发者账号与描述文件重签名安装。"
        }

        return raw
    }

    private func parseCSV(_ input: String) -> [String] {
        input
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func normalizeBundleIDs(_ bundleIDs: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []
        for bundleID in bundleIDs {
            let key = bundleID.lowercased()
            if seen.insert(key).inserted {
                normalized.append(bundleID)
            }
        }
        return normalized
    }

    private func extractVMessLink(from text: String) -> String? {
        if text.hasPrefix("vmess://") || text.hasPrefix("vemss://") {
            return text
        }

        let parts = text.components(separatedBy: .whitespacesAndNewlines)
        for part in parts {
            if part.hasPrefix("vmess://") || part.hasPrefix("vemss://") {
                return part
            }
        }
        return nil
    }

    private func isValidBundleID(_ bundleID: String) -> Bool {
        let pattern = "^[A-Za-z0-9\\-]+(\\.[A-Za-z0-9\\-]+)+$"
        return bundleID.range(of: pattern, options: .regularExpression) != nil
    }

    private static func describe(_ status: NEVPNStatus) -> String {
        switch status {
        case .invalid:
            return "无效"
        case .disconnected:
            return "未连接"
        case .connecting:
            return "连接中"
        case .connected:
            return "已连接"
        case .reasserting:
            return "重连中"
        case .disconnecting:
            return "断开中"
        @unknown default:
            return "未知"
        }
    }
}
