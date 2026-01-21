import SwiftUI

/// About window view
struct AboutView: View {
    private let appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0"
    private let buildNumber: String = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    private let currentYear: String = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter.string(from: Date())
    }()

    var body: some View {
        VStack(spacing: 16) {
            // App icon
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            // App name
            Text(L10n.App.fullName)
                .font(.title2)
                .fontWeight(.bold)

            // Version
            Text(L10n.About.version(appVersion) + " (\(buildNumber))")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()
                .padding(.horizontal, 40)

            // Description
            Text("Automatic file sync between local directories and external drives")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            // Links
            HStack(spacing: 20) {
                Link(destination: URL(string: "https://github.com")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                        Text(L10n.About.github)
                    }
                }
                .buttonStyle(.link)
            }

            Spacer()

            // Copyright
            Text(L10n.About.copyright(currentYear))
                .font(.caption2)
                .foregroundColor(.secondary)

            // Check for updates
            Button(L10n.About.checkUpdates) {
                checkForUpdates()
            }
            .padding(.bottom, 8)
        }
        .padding(20)
        .frame(width: 300, height: 350)
    }

    private func checkForUpdates() {
        // Placeholder for update check logic
        // Would integrate with Sparkle or similar framework
    }
}

// MARK: - Window Controller

class AboutWindowController {
    private var window: NSWindow?

    func showWindow() {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let aboutView = AboutView()
        let hostingController = NSHostingController(rootView: aboutView)

        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = L10n.About.title
        newWindow.styleMask = [.titled, .closable]
        newWindow.setContentSize(NSSize(width: 300, height: 350))
        newWindow.center()
        newWindow.isReleasedWhenClosed = false

        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeWindow() {
        window?.close()
        window = nil
    }
}

// MARK: - Previews

#if DEBUG
struct AboutView_Previews: PreviewProvider {
    static var previews: some View {
        AboutView()
    }
}
#endif
