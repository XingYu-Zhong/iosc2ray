import Foundation
import NetworkExtension

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let engine: XrayEngine = XrayEngineFactory.make()

    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        Task {
            do {
                guard let tunnelProtocol = protocolConfiguration as? NETunnelProviderProtocol else {
                    throw NSError(
                        domain: "iosv2ray.packettunnel",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "无效的 Tunnel 协议配置"]
                    )
                }

                let runtimeConfig = try TunnelProviderConfigurationBuilder.decodeRuntimeConfig(
                    from: tunnelProtocol.providerConfiguration
                )
                let profile = runtimeConfig.profile
                let mode = runtimeConfig.mode

                if mode == .perAppManaged {
                    guard let appRules, !appRules.isEmpty else {
                        throw NSError(
                            domain: "iosv2ray.packettunnel",
                            code: 2,
                            userInfo: [
                                NSLocalizedDescriptionKey: "按应用模式未检测到系统下发的 appRules。请先通过 MDM 下发 App-Layer VPN 并绑定 VPNUUID。"
                            ]
                        )
                    }
                }

                let settings = makeNetworkSettings(profile: profile)
                try await setTunnelNetworkSettings(settings)

                let xrayJSON = try XrayConfigBuilder.build(profile: profile)
                try engine.start(xrayJSON: xrayJSON)
                TunnelRuntimeDiagnostics.clearLastStartError()

                NSLog("[PacketTunnel] tunnel mode = \(mode.rawValue)")
                if let appRules, !appRules.isEmpty {
                    NSLog("[PacketTunnel] Per-App rules count = \(appRules.count)")
                }

                completionHandler(nil)
            } catch {
                TunnelRuntimeDiagnostics.writeLastStartError(error)
                NSLog("[PacketTunnel] startTunnel failed: \(error.localizedDescription)")
                completionHandler(error)
            }
        }
    }

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        engine.stop()
        completionHandler()
    }

    override func handleAppMessage(
        _ messageData: Data,
        completionHandler: ((Data?) -> Void)? = nil
    ) {
        completionHandler?(messageData)
    }

    private func makeNetworkSettings(profile: VPNProfile) -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: profile.endpoint.host)

        let ipv4 = NEIPv4Settings(
            addresses: ["172.19.0.2"],
            subnetMasks: ["255.255.255.0"]
        )
        ipv4.includedRoutes = [NEIPv4Route.default()]

        if profile.bypassLAN {
            ipv4.excludedRoutes = [
                NEIPv4Route(destinationAddress: "10.0.0.0", subnetMask: "255.0.0.0"),
                NEIPv4Route(destinationAddress: "172.16.0.0", subnetMask: "255.240.0.0"),
                NEIPv4Route(destinationAddress: "192.168.0.0", subnetMask: "255.255.0.0"),
                NEIPv4Route(destinationAddress: "127.0.0.0", subnetMask: "255.0.0.0")
            ]
        }

        settings.ipv4Settings = ipv4

        let ipv6 = NEIPv6Settings(
            addresses: ["fd12:3456:789a::2"],
            networkPrefixLengths: [NSNumber(value: 64)]
        )
        ipv6.includedRoutes = [NEIPv6Route.default()]
        if profile.bypassLAN {
            ipv6.excludedRoutes = [
                NEIPv6Route(destinationAddress: "::1", networkPrefixLength: NSNumber(value: 128)),
                NEIPv6Route(destinationAddress: "fc00::", networkPrefixLength: NSNumber(value: 7)),
                NEIPv6Route(destinationAddress: "fe80::", networkPrefixLength: NSNumber(value: 10))
            ]
        }
        settings.ipv6Settings = ipv6

        let dnsSettings = NEDNSSettings(servers: profile.dnsServers)
        dnsSettings.matchDomains = [""]
        settings.dnsSettings = dnsSettings

        settings.mtu = 1500
        return settings
    }

    private func setTunnelNetworkSettings(_ settings: NEPacketTunnelNetworkSettings) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.setTunnelNetworkSettings(settings) { error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: ())
            }
        }
    }
}
