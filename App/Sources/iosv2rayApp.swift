import SwiftUI

@main
struct iosv2rayApp: App {
    @StateObject private var viewModel = VPNViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .onOpenURL { url in
                    viewModel.handleIncomingURL(url)
                }
        }
    }
}
