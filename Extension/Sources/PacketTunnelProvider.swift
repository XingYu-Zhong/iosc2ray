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

                let profile = try TunnelProviderConfigurationBuilder.decodeProfile(
                    from: tunnelProtocol.providerConfiguration
                )

                let settings = makeNetworkSettings(profile: profile)
                try await setTunnelNetworkSettings(settings)

                let xrayJSON = try XrayConfigBuilder.build(profile: profile)
                try engine.start(xrayJSON: xrayJSON)
                TunnelRuntimeDiagnostics.clearLastStartError()

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
