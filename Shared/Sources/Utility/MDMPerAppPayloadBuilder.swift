import Foundation

struct PerAppMDMExport {
    var vpnUUID: String
    var mobileConfigXML: String
    var settingsCommandJSON: String
    var settingsDeviceCommandPlist: String
    var installProfileDeviceCommandPlist: String
}

enum MDMPerAppPayloadBuilder {
    static func build(profile: VPNProfile, tunnelBundleID: String) throws -> PerAppMDMExport {
        let payloadUUID = UUID().uuidString
        let rootUUID = UUID().uuidString
        let vpnUUID = profile.id.uuidString.uppercased()
        let providerConfiguration = try TunnelProviderConfigurationBuilder.makeConfiguration(
            profile: profile,
            mode: .perAppManaged
        )

        let vpnPayload: [String: Any] = [
            "PayloadDisplayName": "Per-App VPN (\(profile.name))",
            "PayloadIdentifier": "com.zxy.iosv2ray.vpn.\(payloadUUID)",
            "PayloadType": "com.apple.vpn.managed.applayer",
            "PayloadUUID": vpnUUID,
            "PayloadVersion": 1,
            // App-Layer VPN inherits all VPN payload fields at top-level.
            "VPNType": "VPN",
            "VPNSubType": tunnelBundleID,
            "UserDefinedName": "iosv2ray Per-App VPN (\(profile.name))",
            "VPNUUID": vpnUUID,
            "OnDemandMatchAppEnabled": true,
            // VendorConfig is delivered to the provider as NETunnelProviderProtocol.providerConfiguration.
            "VendorConfig": providerConfiguration,
            "VPN": [
                "ProviderType": "packet-tunnel",
                "ProviderBundleIdentifier": tunnelBundleID,
                "RemoteAddress": profile.endpoint.host,
                "AuthenticationMethod": "None"
            ]
        ]

        let rootPayload: [String: Any] = [
            "PayloadContent": [vpnPayload],
            "PayloadDisplayName": "iosv2ray Per-App VPN",
            "PayloadIdentifier": "com.zxy.iosv2ray.profile.\(payloadUUID)",
            "PayloadType": "Configuration",
            "PayloadUUID": rootUUID,
            "PayloadVersion": 1
        ]

        guard let mobileConfigXML = toXMLPlist(rootPayload) else {
            throw NSError(
                domain: "iosv2ray.mdm",
                code: 21,
                userInfo: [NSLocalizedDescriptionKey: "生成 mobileconfig 失败"]
            )
        }

        let settingsItems = profile.perAppBundleIDs.map { bundleID in
            [
                "Item": "ApplicationAttributes",
                "Identifier": bundleID,
                "Attributes": [
                    "VPNUUID": vpnUUID
                ]
            ]
        }

        let settingsCommand: [String: Any] = [
            "RequestType": "Settings",
            "Settings": settingsItems
        ]

        let settingsCommandJSON: String
        if let data = try? JSONSerialization.data(withJSONObject: settingsCommand, options: [.prettyPrinted, .sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            settingsCommandJSON = json
        } else {
            settingsCommandJSON = "{}"
        }

        let settingsDeviceCommandPlist = buildSettingsDeviceCommandPlist(
            settingsItems: settingsItems,
            commandUUID: "com.zxy.iosv2ray.settings.\(payloadUUID)"
        )
        let installProfileDeviceCommandPlist = buildInstallProfileDeviceCommandPlist(
            mobileConfigXML: mobileConfigXML,
            commandUUID: "com.zxy.iosv2ray.installprofile.\(payloadUUID)"
        )

        return PerAppMDMExport(
            vpnUUID: vpnUUID,
            mobileConfigXML: mobileConfigXML,
            settingsCommandJSON: settingsCommandJSON,
            settingsDeviceCommandPlist: settingsDeviceCommandPlist,
            installProfileDeviceCommandPlist: installProfileDeviceCommandPlist
        )
    }

    private static func buildSettingsDeviceCommandPlist(
        settingsItems: [[String: Any]],
        commandUUID: String
    ) -> String {
        let commandBody: [String: Any] = [
            "RequestType": "Settings",
            "Settings": settingsItems
        ]

        let envelope: [String: Any] = [
            "CommandUUID": commandUUID,
            "Command": commandBody
        ]

        return toXMLPlist(envelope) ?? "{}"
    }

    private static func buildInstallProfileDeviceCommandPlist(
        mobileConfigXML: String,
        commandUUID: String
    ) -> String {
        let payloadData = Data(mobileConfigXML.utf8)
        let command: [String: Any] = [
            "RequestType": "InstallProfile",
            "Payload": payloadData
        ]

        let envelope: [String: Any] = [
            "CommandUUID": commandUUID,
            "Command": command
        ]

        return toXMLPlist(envelope) ?? "{}"
    }

    private static func toXMLPlist(_ object: Any) -> String? {
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: object,
            format: .xml,
            options: 0
        ) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
