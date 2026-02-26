import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@main
struct iosv2rayApp: App {
    @StateObject private var viewModel = VPNViewModel()
#if canImport(UIKit)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
#endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .onOpenURL { url in
                    viewModel.handleIncomingURL(url)
                }
#if canImport(UIKit)
                .onAppear {
                    if let actionType = AppDelegate.consumePendingQuickActionType() {
                        Task {
                            await viewModel.handleQuickAction(actionType)
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .vpnQuickActionTriggered)) { note in
                    guard let actionType = note.object as? String else {
                        return
                    }
                    Task {
                        await viewModel.handleQuickAction(actionType)
                    }
                }
#endif
        }
    }
}

#if canImport(UIKit)
private final class AppDelegate: NSObject, UIApplicationDelegate {
    private static var pendingQuickActionType: String?

    static func consumePendingQuickActionType() -> String? {
        let pending = pendingQuickActionType
        pendingQuickActionType = nil
        return pending
    }

    private let quickActionItems: [UIApplicationShortcutItem] = [
        UIApplicationShortcutItem(
            type: VPNQuickActionType.connect,
            localizedTitle: "连接隧道",
            localizedSubtitle: "一键连接 VPN",
            icon: UIApplicationShortcutIcon(systemImageName: "power")
        ),
        UIApplicationShortcutItem(
            type: VPNQuickActionType.disconnect,
            localizedTitle: "断开隧道",
            localizedSubtitle: "一键断开 VPN",
            icon: UIApplicationShortcutIcon(systemImageName: "poweroff")
        )
    ]

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        installQuickActions(on: application)

        if let shortcutItem = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem {
            Self.pendingQuickActionType = shortcutItem.type
            return false
        }

        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        installQuickActions(on: application)
    }

    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(postQuickAction(shortcutItem))
    }

    private func installQuickActions(on application: UIApplication) {
        application.shortcutItems = quickActionItems
    }

    private func postQuickAction(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
        guard shortcutItem.type == VPNQuickActionType.connect || shortcutItem.type == VPNQuickActionType.disconnect else {
            return false
        }

        NotificationCenter.default.post(
            name: .vpnQuickActionTriggered,
            object: shortcutItem.type
        )
        return true
    }
}

private extension Notification.Name {
    static let vpnQuickActionTriggered = Notification.Name("com.zxy.iosv2ray.quickActionTriggered")
}
#endif
