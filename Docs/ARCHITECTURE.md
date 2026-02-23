# Architecture

## 1. 模块设计

- `App`：用户交互与 VPN 生命周期管理。
- `Shared`：协议解析、配置模型、Xray 配置构建。
- `PacketTunnel`：Network Extension，负责 TUN 网络设置与代理引擎生命周期。

## 2. 数据流

1. 用户输入 `vmess://...` 或通过深链/剪贴板导入。
2. `VMessURLParser` 解析为 `VMessEndpoint`。
3. 组装成 `VPNProfile` 并持久化到 `App Group UserDefaults`（敏感 VMess ID 存 Keychain）。
4. `TunnelProviderConfigurationBuilder` 序列化到 `providerConfiguration`。
5. `PacketTunnelProvider` 读取 profile 并生成 Xray JSON。
6. `XrayEngine` 启动 Xray 与 tun2socks，建立 TUN -> SOCKS -> VMess 链路。

## 3. Per-App VPN 说明

- 代码中提供了 Per-App 配置生成能力（MDM Profile XML、Settings JSON、设备命令 plist 模板）。
- 真正的按应用路由在 iOS 上由系统受管能力控制，建议走 MDM 下发。
- App 内“按应用模式”不会直接发起全局隧道，而是提示通过 MDM 完成 VPNUUID 绑定。

## 4. 连接策略增强

- `On-Demand`：在 `NETunnelProviderManager` 层开启自动连接。
- `Bypass LAN`：通过 `excludedRoutes` 排除私网段，避免局域网流量进入隧道。
- `Endpoint Probe`：主 App 侧 TCP 可达性探测，用于连接前预检。

## 5. 真实核心实现

`Extension/Sources/XrayEngine.swift`

- 使用 `dlsym` 动态绑定 `libXray` 的 C 接口：
  - `CGoRunXrayFromJSON`
  - `CGoStopXray`
- 使用 `Tun2SocksKit` 启动 tun2socks 转发循环。
- 若核心未链接，会返回明确错误而不是静默失败。

## 6. 安全建议

- 继续将其余敏感字段迁移到 Keychain（目前已覆盖 VMess 用户 ID）。
- 增加节点连通性检测与重试策略。
- 对 MDM 导出内容做签名与发布流程控制。
