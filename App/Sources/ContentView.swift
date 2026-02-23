import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: VPNViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section("连接状态") {
                    LabeledContent("状态", value: viewModel.statusText)
                    if !viewModel.lastError.isEmpty {
                        Text(viewModel.lastError)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                Section("已保存配置") {
                    Picker("选择配置", selection: $viewModel.selectedProfileID) {
                        Text("未选择").tag(Optional<UUID>.none)
                        ForEach(viewModel.profiles) { profile in
                            Text(profile.name).tag(Optional(profile.id))
                        }
                    }

                    Button("加载选中配置") {
                        viewModel.loadSelectedProfileToForm()
                    }

                    HStack {
                        Button("保存/更新") {
                            Task { await viewModel.saveCurrentProfile() }
                        }

                        Button("删除") {
                            Task { await viewModel.deleteSelectedProfile() }
                        }
                        .foregroundStyle(.red)
                    }
                }

                Section("VMess") {
                    TextField("vmess://...", text: $viewModel.vmessLink, axis: .vertical)
                    TextField("配置名称（可选）", text: $viewModel.profileName)
                    HStack {
                        Button("导入 VMess") {
                            viewModel.importVMess()
                        }
                        Button("从剪贴板导入") {
                            viewModel.importVMessFromClipboard()
                        }
                    }
                }

                Section("高级") {
                    TextField("DNS（逗号分隔）", text: $viewModel.dnsCSV)
                    Picker("模式", selection: $viewModel.mode) {
                        Text("全局 VPN").tag(TunnelMode.fullDevice)
                        Text("按应用 VPN (MDM)").tag(TunnelMode.perAppManaged)
                    }
                    .pickerStyle(.segmented)

                    Toggle("On-Demand 自动连接", isOn: $viewModel.onDemandEnabled)
                    Toggle("绕行局域网(LAN)", isOn: $viewModel.bypassLAN)

                    TextField(
                        "按应用 Bundle ID（逗号分隔）",
                        text: $viewModel.perAppBundleIDsCSV,
                        axis: .vertical
                    )

                    if viewModel.mode == .perAppManaged {
                        Text(viewModel.perAppModeHint)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                Section("操作") {
                    Button("连接") {
                        Task { await viewModel.connect() }
                    }
                    Button("断开") {
                        Task { await viewModel.disconnect() }
                    }
                    Button("测试节点连通性") {
                        Task { await viewModel.testEndpointReachability() }
                    }
                    if !viewModel.probeText.isEmpty {
                        Text(viewModel.probeText)
                            .font(.footnote)
                    }

                    if viewModel.mode == .perAppManaged {
                        Button("生成 MDM Per-App 配置") {
                            viewModel.exportMDMProfile()
                        }
                    }
                }

                if !viewModel.exportedMDMProfile.isEmpty {
                    Section("MDM 配置 XML") {
                        Button("复制 MDM 配置 XML") {
                            viewModel.copyText(viewModel.exportedMDMProfile, label: "MDM 配置 XML")
                        }
                        Text(viewModel.exportedMDMProfile)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                    }
                }

                if !viewModel.exportedMDMSettingsCommand.isEmpty {
                    Section("MDM Settings 命令(JSON)") {
                        Button("复制 Settings(JSON)") {
                            viewModel.copyText(viewModel.exportedMDMSettingsCommand, label: "Settings(JSON)")
                        }
                        Text(viewModel.exportedMDMSettingsCommand)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                    }
                }

                if !viewModel.exportedMDMInstallProfileCommand.isEmpty {
                    Section("设备命令 InstallProfile(plist)") {
                        Button("复制 InstallProfile(plist)") {
                            viewModel.copyText(viewModel.exportedMDMInstallProfileCommand, label: "InstallProfile(plist)")
                        }
                        Text(viewModel.exportedMDMInstallProfileCommand)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                    }
                }

                if !viewModel.exportedMDMSettingsDeviceCommand.isEmpty {
                    Section("设备命令 Settings(plist)") {
                        Button("复制 Settings(plist)") {
                            viewModel.copyText(viewModel.exportedMDMSettingsDeviceCommand, label: "Settings(plist)")
                        }
                        Text(viewModel.exportedMDMSettingsDeviceCommand)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                    }
                }

                if !viewModel.copyStatusText.isEmpty {
                    Section("复制状态") {
                        Text(viewModel.copyStatusText)
                            .font(.footnote)
                            .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle("iosv2ray")
        }
    }
}
