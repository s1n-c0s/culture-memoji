import SwiftUI
import AppKit

public extension Notification.Name {
    static let copyCurrentAvatarRequested = Notification.Name("copyCurrentAvatarRequested")
    static let saveImageRequested = Notification.Name("saveImageRequested")
    static let resetCameraAndPoseRequested = Notification.Name("resetCameraAndPoseRequested")
    static let toggleSidebarRequested = Notification.Name("toggleSidebarRequested")
    static let toggleFullScreenRequested = Notification.Name("toggleFullScreenRequested")
    static let toggleSidebarTabRequested = Notification.Name("toggleSidebarTabRequested")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        // Global key monitor for shortcuts
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let isC = event.keyCode == 8 || event.charactersIgnoringModifiers?.lowercased() == "c"
            let hasControl = event.modifierFlags.contains(.control)
            let hasCommand = event.modifierFlags.contains(.command)
            let hasOption = event.modifierFlags.contains(.option)
            
            if isC && (hasControl || hasCommand) {
                // If user is currently typing/selecting text in a text view, allow normal text copy
                if let responder = NSApp.keyWindow?.firstResponder {
                    if let textView = responder as? NSTextView, textView.selectedRange().length > 0 {
                        return event
                    }
                }
                NotificationCenter.default.post(name: .copyCurrentAvatarRequested, object: nil)
                return nil
            }
            
            // Tab key (keyCode 48) toggles between Character and Emote tabs
            let isTab = event.keyCode == 48 && !hasCommand && !hasControl && !hasOption
            if isTab {
                // Don't intercept if an editor sheet or modal window is open
                if NSApp.keyWindow?.attachedSheet != nil || NSApp.modalWindow != nil {
                    return event
                }
                NotificationCenter.default.post(name: .toggleSidebarTabRequested, object: nil)
                return nil
            }
            
            return event
        }
    }
}

@main
public struct CultureMemojiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    public init() {}
    
    public var body: some Scene {
        WindowGroup("Memoji Studio") {
            ContentView()
                .frame(minWidth: 880, minHeight: 560)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .saveItem) {
                Button("Save / Download Image...") {
                    NotificationCenter.default.post(name: .saveImageRequested, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
            }
            
            CommandGroup(replacing: .pasteboard) {
                Button("Copy Character / Emote") {
                    NotificationCenter.default.post(name: .copyCurrentAvatarRequested, object: nil)
                }
                .keyboardShortcut("c", modifiers: .command)
                
                Button("Copy Character / Emote (Control+C)") {
                    NotificationCenter.default.post(name: .copyCurrentAvatarRequested, object: nil)
                }
                .keyboardShortcut("c", modifiers: .control)
            }
            
            CommandGroup(after: .sidebar) {
                Button("Toggle Sidebar") {
                    NotificationCenter.default.post(name: .toggleSidebarRequested, object: nil)
                }
                .keyboardShortcut("\\", modifiers: .command)
                
                Button("Switch Character / Emote Tab") {
                    NotificationCenter.default.post(name: .toggleSidebarTabRequested, object: nil)
                }
                .keyboardShortcut(.tab, modifiers: [])
                
                Button("Toggle Full Screen") {
                    NotificationCenter.default.post(name: .toggleFullScreenRequested, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.control, .command])
                
                Divider()
                
                Button("Reset Camera Framing & Pose") {
                    NotificationCenter.default.post(name: .resetCameraAndPoseRequested, object: nil)
                }
                .keyboardShortcut("0", modifiers: .command)
            }
            
            CommandGroup(replacing: .help) {
                Button("About Memoji Studio") {
                    NSApp.orderFrontStandardAboutPanel(nil)
                }
                Divider()
                Button("Open macOS Memoji Settings...") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Users-and-Groups-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }
}
