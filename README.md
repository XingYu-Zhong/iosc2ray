# iosv2ray

一个 iOS VPN App，支持 VMess、Packet Tunnel、Per-App VPN（受管设备场景）、以及真实 `xray-core + tun2socks` 运行链路。

## 已实现

- 主 App（SwiftUI）
  - 导入 `vmess://` 链接（支持系统深链）
  - 从剪贴板一键导入 VMess 链接
  - 多配置管理（保存 / 选择 / 删除）
  - 管理 VPN 配置（`NETunnelProviderManager`）
  - 启停隧道
  - 支持 On-Demand 自动连接开关
  - 导出 Per-App VPN 的 MDM 产物（Profile XML / Settings JSON / Device Command plist）
  - 节点连通性测试（TCP host:port）
- Packet Tunnel Extension
  - 读取并解析 VMess 配置
  - 下发 TUN 网络设置（默认路由 + DNS）
  - 支持 LAN 绕行（私网路由排除）
  - 启动真实 Xray（`CGoRunXrayFromJSON`）
  - 启动 tun2socks（`Tun2SocksKit`）
- 共享模块
  - VMess URL 解析器（校验 UUID 用户 ID）
  - Profile 模型
  - Provider 配置序列化

## 安全增强

- VMess 用户 ID 不再明文持久化在 `UserDefaults`。
- 配置保存时，敏感 ID 写入 Keychain；本地配置仅存占位符。

## 关键限制（请先确认）

1. iOS 的“按应用走 VPN”属于 Per-App VPN，通常需要 MDM/受管部署场景；普通个人设备上无法由第三方 App 完整替代 MDM 行为。
2. 你需要把 `LibXray.xcframework` 链接到 `PacketTunnel` target（详见 `Docs/REAL_CORE_INTEGRATION.md`），否则会回退到错误提示。

## 目录

- `project.yml`: XcodeGen 工程定义
- `App/`: 主 App 源码
- `Extension/`: Packet Tunnel Extension 源码
- `Shared/`: 主 App 和 Extension 复用代码
- `Scripts/build_libxray_apple_go.sh`: 构建 `LibXray.xcframework`
- `Docs/ARCHITECTURE.md`: 设计说明
- `Docs/REAL_CORE_INTEGRATION.md`: 真实核心接入步骤

## 快速开始

1. 构建 libXray：

```bash
./Scripts/build_libxray_apple_go.sh
```

2. 用 XcodeGen 生成工程：

```bash
xcodegen generate
```

3. 打开 `iosv2ray.xcodeproj`，在 Signing 中配置：
   - App 与 Extension 的 Team
   - `Network Extension` capability
   - `App Groups`（默认 `group.com.zxy.iosv2ray`）

4. 把 `Vendor/LibXray.xcframework` 链接到 `PacketTunnel` target（Do Not Embed）。

5. 在 App 中导入 VMess，先点“测试节点连通性”，再连接。

## 指定应用走 VPN（Per-App）

1. 在“高级设置”选择模式（`全局 VPN` / `按应用 VPN (MDM)`）。模式属于全局设置，不随配置保存。
2. 在 App 里填写目标应用 `Bundle ID` 列表（可用“选择应用”）。
3. 点击 `生成 MDM Per-App 配置`，得到四份内容：
   - `MDM 配置 XML`
   - `MDM Settings 命令`
   - `设备命令 InstallProfile(plist)`
   - `设备命令 Settings(plist)`
4. 将 profile 下发到设备，并在 MDM 侧执行 Settings 命令，把目标应用绑定到同一个 `VPNUUID`。
5. `连接隧道` 可在两种模式下都使用；是否按应用生效取决于设备上的 Per-App 绑定状态。
6. Per-App 绑定只对受管应用生效（由 MDM 安装/管理的应用）。

更多细节见 `Docs/REAL_CORE_INTEGRATION.md`。
