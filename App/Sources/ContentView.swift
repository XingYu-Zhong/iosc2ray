import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ContentView: View {
    var body: some View {
        TabView {
            DashboardTab()
                .tabItem {
                    Label("概览", systemImage: "gauge.with.dots.needle.67percent")
                }

            ProfilesTab()
                .tabItem {
                    Label("配置", systemImage: "tray.full")
                }

            SettingsTab()
                .tabItem {
                    Label("设置", systemImage: "slider.horizontal.3")
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") {
                    KeyboardController.dismiss()
                }
            }
        }
    }
}

private struct DashboardTab: View {
    @EnvironmentObject private var viewModel: VPNViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ScreenBackground {
                VStack(spacing: 16) {
                    statusHero
                    quickActions
                    runtimeSummary
                    probeHistoryCard

                    if !viewModel.lastError.isEmpty {
                        InfoCard(
                            title: "异常信息",
                            symbol: "exclamationmark.triangle.fill",
                            tint: .orange
                        ) {
                            Text(viewModel.lastError)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if !viewModel.probeText.isEmpty {
                        InfoCard(
                            title: "连通性测试",
                            symbol: "waveform.path.ecg",
                            tint: .blue
                        ) {
                            Text(viewModel.probeText)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .navigationTitle("连接概览")
            .navigationBarTitleDisplayMode(.inline)
            .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: viewModel.statusText)
        }
    }

    private var statusHero: some View {
        let status = StatusPresentation(statusText: viewModel.statusText, hasError: !viewModel.lastError.isEmpty)

        return SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("iosv2ray")
                            .font(.title2.weight(.semibold))
                        Text("iOS VMess / VPN 隧道控制中心")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    StatusBadge(status: status, text: viewModel.statusText)
                }

                Text("更新于 \(Date.now.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var quickActions: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "快速操作", symbol: "bolt.fill")

                Button {
                    Task { await viewModel.connect() }
                } label: {
                    Label("连接隧道", systemImage: "power")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryActionButtonStyle())

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        Button {
                            Task { await viewModel.disconnect() }
                        } label: {
                            Label("断开", systemImage: "poweroff")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SecondaryActionButtonStyle())

                        Button {
                            Task { await viewModel.testEndpointReachability() }
                        } label: {
                            Label("测试", systemImage: "waveform.path.ecg")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SecondaryActionButtonStyle())
                    }

                    VStack(spacing: 10) {
                        Button {
                            Task { await viewModel.disconnect() }
                        } label: {
                            Label("断开", systemImage: "poweroff")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SecondaryActionButtonStyle())

                        Button {
                            Task { await viewModel.testEndpointReachability() }
                        } label: {
                            Label("测试", systemImage: "waveform.path.ecg")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SecondaryActionButtonStyle())
                    }
                }
            }
        }
    }

    private var runtimeSummary: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "运行摘要", symbol: "list.bullet.rectangle")

                SummaryRow(title: "当前配置", value: selectedProfileName)
                SummaryRow(title: "运行模式", value: modeText)
                SummaryRow(title: "On-Demand", value: viewModel.onDemandEnabled ? "已开启" : "已关闭")
                SummaryRow(title: "绕行 LAN", value: viewModel.bypassLAN ? "是" : "否")
            }
        }
    }

    private var probeHistoryCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionHeader(title: "测速历史", symbol: "clock.arrow.trianglehead.counterclockwise.rotate.90")

                    if !viewModel.probeHistory.isEmpty {
                        Button("清空") {
                            viewModel.clearProbeHistory()
                        }
                        .buttonStyle(SecondaryActionButtonStyle(tint: .red))
                    }
                }

                if viewModel.probeHistory.isEmpty {
                    Text("暂无测速记录，点击“测试”后会展示最近 20 条结果。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(Array(viewModel.probeHistory.prefix(6))) { item in
                            ProbeHistoryRow(item: item)
                        }
                    }
                }
            }
        }
    }

    private var selectedProfileName: String {
        guard let id = viewModel.selectedProfileID,
              let profile = viewModel.profiles.first(where: { $0.id == id })
        else {
            return "未选择"
        }

        return profile.name
    }

    private var modeText: String {
        switch viewModel.mode {
        case .fullDevice:
            return "全局 VPN"
        case .perAppManaged:
            return "按应用 VPN (MDM)"
        }
    }
}

private struct ProfilesTab: View {
    @EnvironmentObject private var viewModel: VPNViewModel

    var body: some View {
        NavigationStack {
            ScreenBackground {
                VStack(spacing: 16) {
                    savedProfiles
                    importCard
                }
            }
            .navigationTitle("配置管理")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { profileID in
                ProfileDetailView(profileID: profileID)
            }
        }
    }

    private var savedProfiles: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "已保存配置", symbol: "tray.full.fill")

                if viewModel.profiles.isEmpty {
                    Text("暂无配置，先导入一个 VMess 链接。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(viewModel.profiles) { profile in
                            NavigationLink(value: profile.id) {
                                profileRow(profile)
                            }
                            .buttonStyle(.plain)
                            .simultaneousGesture(TapGesture().onEnded {
                                viewModel.selectedProfileID = profile.id
                            })
                        }
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        Button("加载") {
                            viewModel.loadSelectedProfileToForm()
                        }
                        .buttonStyle(SecondaryActionButtonStyle())

                        Button("保存/更新") {
                            Task { await viewModel.saveCurrentProfile() }
                        }
                        .buttonStyle(SecondaryActionButtonStyle())

                        Button("删除") {
                            Task { await viewModel.deleteSelectedProfile() }
                        }
                        .buttonStyle(SecondaryActionButtonStyle(tint: .red))
                    }

                    VStack(spacing: 10) {
                        Button("加载") {
                            viewModel.loadSelectedProfileToForm()
                        }
                        .buttonStyle(SecondaryActionButtonStyle())

                        Button("保存/更新") {
                            Task { await viewModel.saveCurrentProfile() }
                        }
                        .buttonStyle(SecondaryActionButtonStyle())

                        Button("删除") {
                            Task { await viewModel.deleteSelectedProfile() }
                        }
                        .buttonStyle(SecondaryActionButtonStyle(tint: .red))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func profileRow(_ profile: VPNProfile) -> some View {
        let isSelected = viewModel.selectedProfileID == profile.id

        HStack(spacing: 10) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                Text("\(profile.endpoint.host):\(profile.endpoint.port)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(uiColor: .tertiarySystemFill))
        )
    }

    private var importCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "VMess 导入", symbol: "arrow.down.circle.fill")

                LabeledInput(title: "配置名称（可选）") {
                    TextField("例如：办公专线", text: $viewModel.profileName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                LabeledInput(title: "VMess 链接") {
                    TextField("vmess://...", text: $viewModel.vmessLink, axis: .vertical)
                        .lineLimit(3...6)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        Button("导入 VMess") {
                            viewModel.importVMess()
                        }
                        .buttonStyle(SecondaryActionButtonStyle())

                        Button("从剪贴板导入") {
                            viewModel.importVMessFromClipboard()
                        }
                        .buttonStyle(SecondaryActionButtonStyle())
                    }

                    VStack(spacing: 10) {
                        Button("导入 VMess") {
                            viewModel.importVMess()
                        }
                        .buttonStyle(SecondaryActionButtonStyle())

                        Button("从剪贴板导入") {
                            viewModel.importVMessFromClipboard()
                        }
                        .buttonStyle(SecondaryActionButtonStyle())
                    }
                }
            }
        }
    }
}

private struct ProfileDetailView: View {
    @EnvironmentObject private var viewModel: VPNViewModel

    let profileID: UUID

    var body: some View {
        ScreenBackground {
            if let profile {
                VStack(spacing: 16) {
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: profile.name, symbol: "person.crop.square.filled.and.at.rectangle")
                            SummaryRow(title: "地址", value: profile.endpoint.host)
                            SummaryRow(title: "端口", value: "\(profile.endpoint.port)")
                            SummaryRow(title: "传输", value: profile.endpoint.network)
                            SummaryRow(title: "加密", value: profile.endpoint.security)
                            SummaryRow(title: "TLS", value: profile.endpoint.tls.isEmpty ? "关闭" : profile.endpoint.tls)

                            if let sni = profile.endpoint.sni, !sni.isEmpty {
                                SummaryRow(title: "SNI", value: sni)
                            }
                            if let hostHeader = profile.endpoint.hostHeader, !hostHeader.isEmpty {
                                SummaryRow(title: "Host", value: hostHeader)
                            }
                            if let path = profile.endpoint.path, !path.isEmpty {
                                SummaryRow(title: "Path", value: path)
                            }
                        }
                    }

                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "策略设置", symbol: "switch.2")
                            SummaryRow(title: "模式", value: tunnelModeText(profile.mode))
                            SummaryRow(title: "On-Demand", value: profile.onDemandEnabled ? "已开启" : "已关闭")
                            SummaryRow(title: "绕行 LAN", value: profile.bypassLAN ? "是" : "否")
                            SummaryRow(title: "DNS", value: profile.dnsServers.isEmpty ? "-" : profile.dnsServers.joined(separator: ", "))

                            if profile.mode == .perAppManaged {
                                SummaryRow(
                                    title: "Bundle IDs",
                                    value: profile.perAppBundleIDs.isEmpty ? "-" : profile.perAppBundleIDs.joined(separator: ", ")
                                )
                            }
                        }
                    }

                    SurfaceCard {
                        VStack(spacing: 10) {
                            Button {
                                viewModel.selectedProfileID = profile.id
                                viewModel.loadSelectedProfileToForm()
                            } label: {
                                Label("设为当前并加载到编辑器", systemImage: "checkmark.circle")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(SecondaryActionButtonStyle())

                            Button {
                                viewModel.selectedProfileID = profile.id
                                viewModel.loadSelectedProfileToForm()
                                Task { await viewModel.connect() }
                            } label: {
                                Label("使用该配置连接", systemImage: "power")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(PrimaryActionButtonStyle())
                        }
                    }
                }
            } else {
                InfoCard(title: "配置不存在", symbol: "questionmark.circle.fill", tint: .orange) {
                    Text("该配置可能已被删除，请返回配置列表重新选择。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("配置详情")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if profile != nil {
                viewModel.selectedProfileID = profileID
            }
        }
    }

    private var profile: VPNProfile? {
        viewModel.profiles.first(where: { $0.id == profileID })
    }

    private func tunnelModeText(_ mode: TunnelMode) -> String {
        switch mode {
        case .fullDevice:
            return "全局 VPN"
        case .perAppManaged:
            return "按应用 VPN (MDM)"
        }
    }
}

private struct SettingsTab: View {
    @EnvironmentObject private var viewModel: VPNViewModel

    var body: some View {
        NavigationStack {
            ScreenBackground {
                VStack(spacing: 16) {
                    advancedCard
                    mdmCard

                    if !viewModel.copyStatusText.isEmpty {
                        InfoCard(
                            title: "复制状态",
                            symbol: "checkmark.circle.fill",
                            tint: .green
                        ) {
                            Text(viewModel.copyStatusText)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("高级设置")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var advancedCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "网络与模式", symbol: "gearshape.2.fill")

                LabeledInput(title: "DNS（逗号分隔）") {
                    TextField("1.1.1.1,8.8.8.8", text: $viewModel.dnsCSV)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Picker("模式", selection: $viewModel.mode) {
                    Text("全局 VPN").tag(TunnelMode.fullDevice)
                    Text("按应用 VPN (MDM)").tag(TunnelMode.perAppManaged)
                }
                .pickerStyle(.segmented)

                Toggle("On-Demand 自动连接", isOn: $viewModel.onDemandEnabled)
                Toggle("绕行局域网 (LAN)", isOn: $viewModel.bypassLAN)

                LabeledInput(title: "按应用 Bundle ID（逗号分隔）") {
                    TextField("com.example.app,com.company.client", text: $viewModel.perAppBundleIDsCSV, axis: .vertical)
                        .lineLimit(2...4)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                if viewModel.mode == .perAppManaged {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.orange)
                        Text(viewModel.perAppModeHint)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var mdmCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "MDM 导出", symbol: "doc.badge.gearshape")

                if viewModel.mode == .perAppManaged {
                    Button {
                        viewModel.exportMDMProfile()
                    } label: {
                        Label("生成 MDM Per-App 配置", systemImage: "doc.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                } else {
                    Text("切换到“按应用 VPN (MDM)”后可导出。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if !viewModel.exportedMDMProfile.isEmpty {
                    OutputDisclosure(
                        title: "MDM 配置 XML",
                        text: viewModel.exportedMDMProfile,
                        copyLabel: "MDM 配置 XML"
                    )
                }

                if !viewModel.exportedMDMSettingsCommand.isEmpty {
                    OutputDisclosure(
                        title: "MDM Settings 命令 (JSON)",
                        text: viewModel.exportedMDMSettingsCommand,
                        copyLabel: "Settings(JSON)"
                    )
                }

                if !viewModel.exportedMDMInstallProfileCommand.isEmpty {
                    OutputDisclosure(
                        title: "设备命令 InstallProfile (plist)",
                        text: viewModel.exportedMDMInstallProfileCommand,
                        copyLabel: "InstallProfile(plist)"
                    )
                }

                if !viewModel.exportedMDMSettingsDeviceCommand.isEmpty {
                    OutputDisclosure(
                        title: "设备命令 Settings (plist)",
                        text: viewModel.exportedMDMSettingsDeviceCommand,
                        copyLabel: "Settings(plist)"
                    )
                }
            }
        }
    }
}

private struct ScreenBackground<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [
                    Color(uiColor: .systemGroupedBackground),
                    Color(uiColor: .secondarySystemGroupedBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.11))
                .frame(width: 250, height: 250)
                .blur(radius: 30)
                .offset(x: -120, y: -260)

            Circle()
                .fill(Color.cyan.opacity(colorScheme == .dark ? 0.14 : 0.08))
                .frame(width: 220, height: 220)
                .blur(radius: 34)
                .offset(x: 130, y: -190)

            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 108)
            }
            .scrollDismissesKeyboard(.interactively)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct SurfaceCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.05), radius: 14, x: 0, y: 6)
    }
}

private struct SectionHeader: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.headline)
            Spacer()
        }
    }
}

private struct SummaryRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
        }
    }
}

private struct ProbeHistoryRow: View {
    let item: ProbeHistoryItem

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: item.reachable ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(item.reachable ? .green : .red)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(item.host):\(item.port)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(item.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(latencyText)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(item.reachable ? .green : .secondary)
                Text(item.date.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill))
        )
    }

    private var latencyText: String {
        if let latency = item.latencyMS {
            return "\(latency)ms"
        }
        return "--"
    }
}

private struct LabeledInput<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            content
                .padding(10)
                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

private struct InfoCard<Content: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    @ViewBuilder var content: Content

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: symbol)
                        .foregroundStyle(tint)
                    Text(title)
                        .font(.headline)
                }

                content
            }
        }
    }
}

private struct OutputDisclosure: View {
    @EnvironmentObject private var viewModel: VPNViewModel

    let title: String
    let text: String
    let copyLabel: String

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    viewModel.copyText(text, label: copyLabel)
                } label: {
                    Label("复制内容", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryActionButtonStyle())

                ScrollView(.horizontal) {
                    Text(text)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(uiColor: .tertiarySystemFill))
                        )
                }
            }
            .padding(.top, 8)
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
        }
    }
}

private struct StatusBadge: View {
    let status: StatusPresentation
    let text: String

    var body: some View {
        Label(text, systemImage: status.icon)
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(status.tint.opacity(0.15), in: Capsule())
            .foregroundStyle(status.tint)
            .accessibilityLabel("连接状态：\(text)")
    }
}

private struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.accentColor.opacity(configuration.isPressed ? 0.84 : 1))
            )
    }
}

private struct SecondaryActionButtonStyle: ButtonStyle {
    var tint: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .foregroundStyle(tint)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.18 : 0.10))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(tint.opacity(0.22), lineWidth: 1)
            }
    }
}

private struct StatusPresentation {
    let icon: String
    let tint: Color

    init(statusText: String, hasError: Bool) {
        if hasError {
            icon = "exclamationmark.triangle.fill"
            tint = .orange
            return
        }

        switch statusText {
        case "已连接":
            icon = "checkmark.shield.fill"
            tint = .green
        case "连接中", "重连中", "断开中":
            icon = "arrow.triangle.2.circlepath.circle.fill"
            tint = .blue
        default:
            icon = "shield.slash.fill"
            tint = .secondary
        }
    }
}

private enum KeyboardController {
    static func dismiss() {
        #if canImport(UIKit)
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
}
