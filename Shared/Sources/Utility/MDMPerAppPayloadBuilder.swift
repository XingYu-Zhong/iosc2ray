import Foundation

struct PerAppMDMExport {
    var vpnUUID: String
    var mobileConfigXML: String
    var settingsCommandJSON: String
    var settingsDeviceCommandPlist: String
    var installProfileDeviceCommandPlist: String
}

enum MDMPerAppPayloadBuilder {
    static func build(profile: VPNProfile, tunnelBundleID: String) -> PerAppMDMExport {
        let payloadUUID = UUID().uuidString
        let rootUUID = UUID().uuidString
        let vpnUUID = profile.id.uuidString.uppercased()

        let mobileConfigXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>PayloadContent</key>
          <array>
            <dict>
              <key>PayloadDisplayName</key>
              <string>Per-App VPN (\(profile.name))</string>
              <key>PayloadIdentifier</key>
              <string>com.zxy.iosv2ray.vpn.\(payloadUUID)</string>
              <key>PayloadType</key>
              <string>com.apple.vpn.managed.applayer</string>
              <key>PayloadUUID</key>
              <string>\(vpnUUID)</string>
              <key>PayloadVersion</key>
              <integer>1</integer>
              <key>AppLayerVPN</key>
              <dict>
                <key>VPNUUID</key>
                <string>\(vpnUUID)</string>
                <key>VPN</key>
                <dict>
                  <key>ProviderType</key>
                  <string>packet-tunnel</string>
                  <key>ProviderBundleIdentifier</key>
                  <string>\(tunnelBundleID)</string>
                  <key>ServerAddress</key>
                  <string>\(profile.endpoint.host)</string>
                </dict>
              </dict>
            </dict>
          </array>
          <key>PayloadDisplayName</key>
          <string>iosv2ray Per-App VPN</string>
          <key>PayloadIdentifier</key>
          <string>com.zxy.iosv2ray.profile.\(payloadUUID)</string>
          <key>PayloadType</key>
          <string>Configuration</string>
          <key>PayloadUUID</key>
          <string>\(rootUUID)</string>
          <key>PayloadVersion</key>
          <integer>1</integer>
        </dict>
        </plist>
        """

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
