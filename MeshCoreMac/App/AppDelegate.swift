// MeshCoreMac/App/AppDelegate.swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @MainActor
    func applicationDidBecomeActive(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    @MainActor
    func switchToAccessoryMode() {
        NSApp.setActivationPolicy(.accessory)
        NSApp.hide(nil)
    }
}
