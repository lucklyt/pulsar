import SwiftUI

public struct PulsarApp: App {
    public init() {}

    public var body: some Scene {
        WindowGroup {
            MainView()
                .frame(minWidth: 1000, minHeight: 650)
                .navigationTitle("Pulsar")
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1200, height: 750)
        .commands {
            SidebarCommands()
            CommandGroup(replacing: .appInfo) {
                Button("关于 Pulsar") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            NSApplication.AboutPanelOptionKey.applicationName: "Pulsar",
                            NSApplication.AboutPanelOptionKey.version: "2.0.8",
                            NSApplication.AboutPanelOptionKey.credits: NSAttributedString(string: "Pulsar - The pulsing heart of native gRPC testing on macOS.\nDesigned for high-speed microservices & gRPC streaming.")
                        ]
                    )
                }
            }
        }
    }
}
