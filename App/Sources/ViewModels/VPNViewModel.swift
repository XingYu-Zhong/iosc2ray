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

struct PerAppPresetApp: Identifiable, Equatable {
    let name: String
    let bundleID: String

    var id: String {
        bundleID.lowercased()
    }
}

enum VPNQuickActionType {
    static let connect = "com.zxy.iosv2ray.connect"
    static let disconnect = "com.zxy.iosv2ray.disconnect"
}

@MainActor
final class VPNViewModel: ObservableObject {
    @Published var vmessLink = ""
    @Published var profileName = ""
    @Published var dnsCSV = "1.1.1.1,8.8.8.8"
    @Published var perAppBundleIDsCSV = ""
    @Published var mode: TunnelMode = .fullDevice {
        didSet {
            persistGlobalMode()
            if mode != .perAppManaged {
                isWaitingPerAppRules = false
                perAppAutoRetryTask?.cancel()
                perAppAutoRetryTask = nil
                connectionNotice = ""
            }
        }
    }
    @Published var onDemandEnabled = false
    @Published var bypassLAN = true
    @Published var statusText = "未连接"
    @Published var lastError = ""
    @Published var connectionNotice = ""
    @Published var mdmAutoBindEnabled = false {
        didSet {
            persistMDMAutoBindSettings()
        }
    }
    @Published var mdmAutoBindEndpoint = "" {
        didSet {
            persistMDMAutoBindSettings()
        }
    }
    @Published var mdmAutoBindDeviceIdentifier = "" {
        didSet {
            persistMDMAutoBindSettings()
        }
    }
    @Published var mdmAutoBindToken = "" {
        didSet {
            persistMDMAutoBindToken()
        }
    }
    @Published var mdmAutoBindStatus = ""
    @Published var exportedMDMProfile = ""
    @Published var exportedMDMSettingsCommand = ""
    @Published var exportedMDMSettingsDeviceCommand = ""
    @Published var exportedMDMInstallProfileCommand = ""
    @Published var perAppModeHint = "模式是全局设置（不随配置保存）。选择按应用后，请等待 MDM 下发规则再连接。"
    @Published var probeText = ""
    @Published var probeHistory: [ProbeHistoryItem] = []
    @Published var copyStatusText = ""
    @Published var isSearchingAppStore = false
    @Published var appStoreSearchStatus = ""
    @Published var appStoreSearchResults: [AppStoreAppResult] = []

    @Published var profiles: [VPNProfile] = []
    @Published var selectedProfileID: UUID?

    let perAppPresetApps: [PerAppPresetApp] = [
        PerAppPresetApp(name: "Google", bundleID: "com.google.GoogleMobile"),
        PerAppPresetApp(name: "Google Chrome", bundleID: "com.google.chrome.ios"),
        PerAppPresetApp(name: "Gmail", bundleID: "com.google.Gmail"),
        PerAppPresetApp(name: "YouTube", bundleID: "com.google.ios.youtube"),
        PerAppPresetApp(name: "Google Maps", bundleID: "com.google.Maps"),
        PerAppPresetApp(name: "Google Drive", bundleID: "com.google.Drive"),
        PerAppPresetApp(name: "Google Photos", bundleID: "com.google.photos"),
        PerAppPresetApp(name: "Google Gemini", bundleID: "com.google.gemini"),
        PerAppPresetApp(name: "ChatGPT", bundleID: "com.openai.chat"),
        PerAppPresetApp(name: "Perplexity", bundleID: "ai.perplexity.app"),
        PerAppPresetApp(name: "X", bundleID: "com.atebits.Tweetie2"),
        PerAppPresetApp(name: "Telegram", bundleID: "ph.telegra.Telegraph"),
        PerAppPresetApp(name: "Instagram", bundleID: "com.burbn.instagram"),
        PerAppPresetApp(name: "TikTok", bundleID: "com.zhiliaoapp.musically"),
        PerAppPresetApp(name: "Discord", bundleID: "com.hammerandchisel.discord"),
        PerAppPresetApp(name: "PayPal", bundleID: "com.yourcompany.PPClient"),
        PerAppPresetApp(name: "Polymtrade", bundleID: "co.median.ios.brjbmo"),
        PerAppPresetApp(name: "Polymarket", bundleID: "com.polymarket.ios-app"),
        PerAppPresetApp(name: "Bitget", bundleID: "com.bitget.exchange.global"),
        PerAppPresetApp(name: "Safari", bundleID: "com.apple.mobilesafari"),
        PerAppPresetApp(name: "Mail", bundleID: "com.apple.mobilemail"),
        PerAppPresetApp(name: "App Store", bundleID: "com.apple.AppStore"),
        PerAppPresetApp(name: "Files", bundleID: "com.apple.DocumentsApp"),
        PerAppPresetApp(name: "WeChat", bundleID: "com.tencent.xin"),
        PerAppPresetApp(name: "QQ", bundleID: "com.tencent.mqq"),
        PerAppPresetApp(name: "钉钉", bundleID: "com.alibaba.DingTalk")
    ]

    private let managerService = VPNManagerService()
    private let mdmAutoBindService = MDMAutoBindService()
    private let profileStore = ProfileStore.shared
    private let probeService = EndpointProbeService()
    private let appStoreLookupService = AppStoreLookupService()
    private let mdmSecretStore = KeychainSecretStore(service: "com.zxy.iosv2ray.mdm")
    private let defaults = UserDefaults(suiteName: TunnelRuntimeDiagnostics.appGroupID) ?? .standard
    private var parsedEndpoint: VMessEndpoint?
    private var awaitingConnectResult = false
    private var isWaitingPerAppRules = false
    private var perAppAutoRetryTask: Task<Void, Never>?

    private let globalModeKey = "vpn.global.mode"
    private let mdmAutoBindEnabledKey = "mdm.autobind.enabled"
    private let mdmAutoBindEndpointKey = "mdm.autobind.endpoint"
    private let mdmAutoBindDeviceIdentifierKey = "mdm.autobind.deviceIdentifier"
    private let mdmAutoBindTokenAccount = "mdm.autobind.apiToken"

    init() {
        if let rawMode = defaults.string(forKey: globalModeKey),
           let restoredMode = TunnelMode(rawValue: rawMode) {
            mode = restoredMode
        }

        mdmAutoBindEnabled = defaults.bool(forKey: mdmAutoBindEnabledKey)
        mdmAutoBindEndpoint = defaults.string(forKey: mdmAutoBindEndpointKey) ?? ""
        mdmAutoBindDeviceIdentifier = defaults.string(forKey: mdmAutoBindDeviceIdentifierKey) ?? ""
        mdmAutoBindToken = (try? mdmSecretStore.getString(account: mdmAutoBindTokenAccount)) ?? ""

        managerService.startObservingStatus { [weak self] status, disconnectError in
            Task { @MainActor in
                guard let self else { return }
                self.statusText = VPNViewModel.describe(status)

                switch status {
                case .connected:
                    self.awaitingConnectResult = false
                    self.isWaitingPerAppRules = false
                    self.perAppAutoRetryTask?.cancel()
                    self.perAppAutoRetryTask = nil
                    self.lastError = ""
                    self.connectionNotice = ""
                case .disconnected:
                    let triggerMessage = disconnectError?.trimmingCharacters(in: .whitespacesAndNewlines)
                    if self.mode == .perAppManaged,
                       self.isPerAppRuleMissingError(triggerMessage ?? "") {
                        self.enterPerAppRuleWaitingState(detail: triggerMessage)
                        return
                    }

                    if self.awaitingConnectResult {
                        self.awaitingConnectResult = false
                        if let disconnectError, !disconnectError.isEmpty {
                            self.lastError = self.formatConnectErrorMessage(disconnectError)
                        } else if self.lastError.isEmpty {
                            self.lastError = self.connectionFailureHint()
                        }
                    } else if let disconnectError, !disconnectError.isEmpty {
                        self.lastError = self.formatConnectErrorMessage(disconnectError)
                    }
                default:
                    if let disconnectError, !disconnectError.isEmpty {
                        self.lastError = self.formatConnectErrorMessage(disconnectError)
                    }
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
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "vmess" {
            vmessLink = url.absoluteString
            importVMess()
            return
        }

        guard scheme == "iosv2ray" else {
            return
        }

        let hostAction = url.host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let pathAction = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        let action = hostAction.isEmpty ? pathAction : hostAction

        switch action {
        case "connect":
            Task { await handleQuickAction(VPNQuickActionType.connect) }
        case "disconnect":
            Task { await handleQuickAction(VPNQuickActionType.disconnect) }
        default:
            break
        }
    }

    func handleQuickAction(_ actionType: String) async {
        switch actionType {
        case VPNQuickActionType.connect:
            await quickConnect()
        case VPNQuickActionType.disconnect:
            await disconnect()
        default:
            break
        }
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
            isWaitingPerAppRules = false
            perAppAutoRetryTask?.cancel()
            perAppAutoRetryTask = nil
            connectionNotice = ""
            if parsedEndpoint == nil,
               let selectedProfileID,
               let existing = profiles.first(where: { $0.id == selectedProfileID }) {
                parsedEndpoint = existing.endpoint
            }

            let profile = try profileFromForm(preferExistingID: selectedProfileID)

            try validateSecret(profile: profile)

            await submitMDMAutoBindIfNeeded(profile: profile)

            try await managerService.install(profile: profile, mode: mode)
            try await managerService.connect()
            scheduleConnectResultTimeoutCheck()
            lastError = ""
        } catch {
            if mode == .perAppManaged,
               isPerAppRuleMissingError(error.localizedDescription) {
                enterPerAppRuleWaitingState(detail: error.localizedDescription)
                return
            }
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
            isWaitingPerAppRules = false
            perAppAutoRetryTask?.cancel()
            perAppAutoRetryTask = nil
            connectionNotice = ""
            lastError = ""
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func quickConnect() async {
        if profiles.isEmpty {
            await loadProfiles()
        }

        if selectedProfileID == nil, let first = profiles.first {
            selectedProfileID = first.id
        }

        guard selectedProfileID != nil else {
            lastError = "没有可用配置，请先导入并保存一个配置。"
            return
        }

        loadSelectedProfileToForm()
        await connect()
    }

    func exportMDMProfile() {
        do {
            let profile = try profileFromForm(preferExistingID: selectedProfileID)
            guard mode == .perAppManaged else {
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

            let export = try MDMPerAppPayloadBuilder.build(
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

    func selectedPerAppBundleIDs() -> [String] {
        normalizeBundleIDs(parseCSV(perAppBundleIDsCSV))
    }

    func applyPerAppBundleIDs(_ bundleIDs: [String]) {
        let normalized = normalizeBundleIDs(bundleIDs)
        perAppBundleIDsCSV = normalized.joined(separator: ",")
    }

    func removePerAppBundleID(_ bundleID: String) {
        let next = selectedPerAppBundleIDs().filter { $0.caseInsensitiveCompare(bundleID) != .orderedSame }
        applyPerAppBundleIDs(next)
    }

    func resetAppStoreSearch() {
        isSearchingAppStore = false
        appStoreSearchStatus = ""
        appStoreSearchResults = []
    }

    func searchAppStoreApps(keyword: String) async {
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            resetAppStoreSearch()
            return
        }

        isSearchingAppStore = true
        appStoreSearchStatus = "正在搜索 App Store..."
        defer { isSearchingAppStore = false }

        do {
            let results = try await appStoreLookupService.searchApps(query: query)
            appStoreSearchResults = results
            if results.isEmpty {
                appStoreSearchStatus = "没有匹配结果，可尝试英文名、中文名、App Store 链接或直接输入 Bundle ID。"
            } else {
                appStoreSearchStatus = "找到 \(results.count) 个结果，点击可加入。"
            }
        } catch {
            appStoreSearchResults = []
            appStoreSearchStatus = "搜索失败: \(error.localizedDescription)"
        }
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
        onDemandEnabled = false
        bypassLAN = true
        parsedEndpoint = nil
        exportedMDMProfile = ""
        exportedMDMSettingsCommand = ""
        exportedMDMSettingsDeviceCommand = ""
        exportedMDMInstallProfileCommand = ""
        copyStatusText = ""
        resetAppStoreSearch()
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
                let runtimeError = TunnelRuntimeDiagnostics.readLastStartError()
                if mode == .perAppManaged,
                   isPerAppRuleMissingError(runtimeError ?? lastError) {
                    enterPerAppRuleWaitingState(detail: runtimeError ?? lastError)
                    return
                }
                awaitingConnectResult = false
                if lastError.isEmpty {
                    if let runtimeError, !runtimeError.isEmpty {
                        lastError = formatConnectErrorMessage(runtimeError)
                    } else {
                        lastError = connectionFailureHint()
                    }
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
        return formatConnectErrorMessage(nsError.localizedDescription)
    }

    private func formatConnectErrorMessage(_ raw: String) -> String {
        let normalized = raw.lowercased()

        if mode == .perAppManaged,
           normalized.contains("app rules") || normalized.contains("按应用策略") {
            return "按应用规则尚未下发，请等待 MDM 完成下发后再连接。"
        }

        if normalized.contains("permission") || normalized.contains("not entitled") || normalized.contains("entitle") {
            return "系统拒绝 VPN 权限（\(raw)）。请确认 App 与 PacketTunnel 都已启用 Network Extensions (Packet Tunnel)，并使用支持该能力的开发者账号与描述文件重签名安装。"
        }

        return raw
    }

    private func enterPerAppRuleWaitingState(detail: String?) {
        awaitingConnectResult = false
        isWaitingPerAppRules = true
        lastError = ""

        let tail: String
        if let detail, !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            tail = "（系统反馈：\(formatConnectErrorMessage(detail))）"
        } else {
            tail = ""
        }

        connectionNotice = "已选择按应用 VPN，正在等待 MDM 下发规则（appRules）\(tail)\n规则生效后会自动重试连接。"
        startPerAppAutoRetryIfNeeded()
    }

    private func isPerAppRuleMissingError(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("app rules")
            || normalized.contains("apprules")
            || normalized.contains("按应用模式未检测到系统下发的")
            || normalized.contains("按应用策略")
    }

    private func submitMDMAutoBindIfNeeded(profile: VPNProfile) async {
        guard mode == .perAppManaged else {
            return
        }
        guard mdmAutoBindEnabled else {
            return
        }
        guard !profile.perAppBundleIDs.isEmpty else {
            mdmAutoBindStatus = "自动下发已开启，但未选择任何应用。"
            return
        }

        mdmAutoBindStatus = "正在提交自动下发请求..."
        do {
            let export = try MDMPerAppPayloadBuilder.build(
                profile: profile,
                tunnelBundleID: VPNManagerService.tunnelBundleIdentifier
            )
            let result = try await mdmAutoBindService.submitPerAppBinding(
                profile: profile,
                tunnelBundleID: VPNManagerService.tunnelBundleIdentifier,
                export: export,
                bundleIDs: profile.perAppBundleIDs,
                config: currentMDMAutoBindConfig()
            )

            let requestTail = result.requestID.map { "（请求ID: \($0)）" } ?? ""
            mdmAutoBindStatus = "已提交自动下发请求\(requestTail)"
            connectionNotice = "已自动触发 MDM 下发，正在等待规则生效..."
        } catch {
            mdmAutoBindStatus = "自动下发失败: \(error.localizedDescription)"
            connectionNotice = "MDM 自动下发失败：\(error.localizedDescription)"
        }
    }

    private func currentMDMAutoBindConfig() -> MDMAutoBindConfig {
        MDMAutoBindConfig(
            enabled: mdmAutoBindEnabled,
            endpointURL: mdmAutoBindEndpoint,
            deviceIdentifier: mdmAutoBindDeviceIdentifier,
            apiToken: mdmAutoBindToken
        )
    }

    private func startPerAppAutoRetryIfNeeded() {
        guard mdmAutoBindEnabled else {
            return
        }
        guard mode == .perAppManaged else {
            return
        }
        guard isWaitingPerAppRules else {
            return
        }

        perAppAutoRetryTask?.cancel()
        perAppAutoRetryTask = Task { [weak self] in
            guard let self else { return }
            let maxAttempts = 10

            for attempt in 1 ... maxAttempts {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard !Task.isCancelled else { return }
                await self.retryPerAppConnection(attempt: attempt, maxAttempts: maxAttempts)
                guard self.isWaitingPerAppRules else { return }
            }

            guard !Task.isCancelled else { return }
            await self.handlePerAppAutoRetryTimeout()
        }
    }

    private func retryPerAppConnection(attempt: Int, maxAttempts: Int) async {
        guard isWaitingPerAppRules else {
            return
        }

        connectionNotice = "等待 MDM 规则生效，自动重试连接 \(attempt)/\(maxAttempts)..."

        do {
            let profile = try profileFromForm(preferExistingID: selectedProfileID)
            try validateSecret(profile: profile)
            awaitingConnectResult = true
            try await managerService.install(profile: profile, mode: mode)
            try await managerService.connect()
            scheduleConnectResultTimeoutCheck()
        } catch {
            let raw = error.localizedDescription
            if isPerAppRuleMissingError(raw) {
                return
            }

            awaitingConnectResult = false
            isWaitingPerAppRules = false
            perAppAutoRetryTask?.cancel()
            perAppAutoRetryTask = nil
            lastError = formatConnectError(error)
            connectionNotice = ""
        }
    }

    private func handlePerAppAutoRetryTimeout() async {
        guard isWaitingPerAppRules else {
            return
        }
        awaitingConnectResult = false
        connectionNotice = "规则尚未生效，已自动重试多次。MDM 下发完成后会在下次连接尝试中生效。"
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
        for raw in bundleIDs {
            let bundleID = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !bundleID.isEmpty else {
                continue
            }
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

    private func persistGlobalMode() {
        defaults.set(mode.rawValue, forKey: globalModeKey)
    }

    private func persistMDMAutoBindSettings() {
        defaults.set(mdmAutoBindEnabled, forKey: mdmAutoBindEnabledKey)
        defaults.set(
            mdmAutoBindEndpoint.trimmingCharacters(in: .whitespacesAndNewlines),
            forKey: mdmAutoBindEndpointKey
        )
        defaults.set(
            mdmAutoBindDeviceIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
            forKey: mdmAutoBindDeviceIdentifierKey
        )
    }

    private func persistMDMAutoBindToken() {
        do {
            let token = mdmAutoBindToken.trimmingCharacters(in: .whitespacesAndNewlines)
            if token.isEmpty {
                try mdmSecretStore.delete(account: mdmAutoBindTokenAccount)
            } else {
                try mdmSecretStore.setString(token, account: mdmAutoBindTokenAccount)
            }
        } catch {
            mdmAutoBindStatus = "保存 MDM Token 失败: \(error.localizedDescription)"
        }
    }
}
