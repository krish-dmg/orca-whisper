import AppKit
import SwiftUI

final class MainWindowController: NSObject, NSWindowDelegate {
    static let shared = MainWindowController()

    private(set) var window: NSWindow?

    private override init() {
        super.init()
        setupWindow()
    }

    private func setupWindow() {
        let mainView = MainWindowView()
        let hostingController = NSHostingController(rootView: mainView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Orca Whisper"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.setContentSize(NSSize(width: 820, height: 600))
        window.minSize = NSSize(width: 720, height: 500)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.titlebarAppearsTransparent = false
        window.center()

        self.window = window
    }

    func showWindow() {
        guard let window = window else { return }
        if !AppSettings.shared.showDockIcon {
            NSApp.setActivationPolicy(.regular)
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hideWindow() {
        window?.orderOut(nil)
        if !AppSettings.shared.showDockIcon {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func toggleWindow() {
        guard let window = window else { return }
        if window.isVisible && NSApp.isActive {
            hideWindow()
        } else {
            showWindow()
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hideWindow()
        return false
    }
}
