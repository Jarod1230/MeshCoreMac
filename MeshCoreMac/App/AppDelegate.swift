// MeshCoreMac/App/AppDelegate.swift
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func switchToAccessoryMode() {
        NSApp.setActivationPolicy(.accessory)
        NSApp.hide(nil)
    }
}
