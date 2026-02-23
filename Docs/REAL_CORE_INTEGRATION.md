# Real Core Integration (xray-core + tun2socks)

## 1. Build and place LibXray

Run:

```bash
./Scripts/build_libxray_apple_go.sh
```

This produces:

- `Vendor/LibXray.xcframework`

## 2. Link LibXray to PacketTunnel target

In Xcode, open target `PacketTunnel`:

1. `General` -> `Frameworks, Libraries, and Embedded Content`
2. Add `Vendor/LibXray.xcframework`
3. Set to `Do Not Embed`

## 3. Resolve Swift package dependencies

`project.yml` already declares:

- `Tun2SocksKit`

Regenerate project:

```bash
xcodegen generate
```

Then open Xcode and let SPM resolve.

## 4. Runtime expectations

- `XrayEngine` starts Xray by calling exported C functions (`CGoRunXrayFromJSON` / `CGoStopXray`) via dynamic symbol lookup.
- `Tun2SocksKit` starts the TUN -> SOCKS5 forwarding loop.
- SOCKS inbound is expected at `127.0.0.1:10808` (must match your Xray inbound config).

## 5. Geo data

The engine looks for geo files in this order:

1. App Group container: `group.com.zxy.iosv2ray/geo/`
2. Extension bundle resources
3. Runtime temp directory fallback

To use geo rules requiring external data (`geosite.dat` / `geoip.dat`), provide these files in one of the first two locations.

## 6. Troubleshooting

- Error: `未检测到 libXray 导出符号`
  - Ensure `LibXray.xcframework` is linked to `PacketTunnel` target.
- Error: `未检测到 Tun2SocksKit`
  - Ensure SPM packages resolved after `xcodegen generate`.
- Tunnel exits quickly
  - Check Xray JSON validity and SOCKS inbound port consistency.

## 7. Per-App routing on iOS

- Per-App VPN on iOS is managed deployment.  
- The app exports:
  - AppLayerVPN profile (`MDM 配置 XML`)
  - Settings command template (`MDM Settings 命令`) with `ApplicationAttributes` + `VPNUUID`
  - Device-channel command plist templates (`InstallProfile` / `Settings`)
- Apply both via MDM so only specified bundle IDs use the VPN tunnel.
