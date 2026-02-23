import Foundation

enum XrayConfigBuilder {
    static func build(profile: VPNProfile) throws -> String {
        let endpoint = profile.endpoint
        let useTLS = endpoint.tls.lowercased() == "tls"

        var streamSettings: [String: Any] = [
            "network": endpoint.network
        ]

        if endpoint.network == "ws" {
            var wsSettings: [String: Any] = [:]
            if let path = endpoint.path {
                wsSettings["path"] = path
            }
            if let host = endpoint.hostHeader {
                wsSettings["headers"] = ["Host": host]
            }
            streamSettings["wsSettings"] = wsSettings
        }

        if useTLS {
            var tlsSettings: [String: Any] = ["allowInsecure": false]
            if let sni = endpoint.sni {
                tlsSettings["serverName"] = sni
            }
            streamSettings["security"] = "tls"
            streamSettings["tlsSettings"] = tlsSettings
        } else {
            streamSettings["security"] = "none"
        }

        let config: [String: Any] = [
            "log": [
                "loglevel": "warning"
            ],
            "inbounds": [
                [
                    "tag": "socks-in",
                    "port": 10808,
                    "listen": "127.0.0.1",
                    "protocol": "socks",
                    "settings": [
                        "udp": true,
                        "auth": "noauth"
                    ]
                ]
            ],
            "outbounds": [
                [
                    "tag": "proxy",
                    "protocol": "vmess",
                    "settings": [
                        "vnext": [
                            [
                                "address": endpoint.host,
                                "port": endpoint.port,
                                "users": [
                                    [
                                        "id": endpoint.id,
                                        "alterId": endpoint.alterId,
                                        "security": endpoint.security
                                    ]
                                ]
                            ]
                        ]
                    ],
                    "streamSettings": streamSettings
                ],
                [
                    "tag": "direct",
                    "protocol": "freedom"
                ],
                [
                    "tag": "block",
                    "protocol": "blackhole"
                ]
            ],
            "routing": [
                "domainStrategy": "AsIs",
                "rules": [
                    [
                        "type": "field",
                        "ip": ["geoip:private"],
                        "outboundTag": "direct"
                    ]
                ]
            ],
            "dns": [
                "servers": profile.dnsServers
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}
