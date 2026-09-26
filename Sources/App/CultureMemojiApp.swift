import SwiftUI
import AppKit

public extension Notification.Name {
    static let copyCurrentAvatarRequested = Notification.Name("copyCurrentAvatarRequested")
    static let resetCameraAndPoseRequested = Notification.Name("resetCameraAndPoseRequested")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        // Global key monitor for Control+C and Command+C
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let isC = event.keyCode == 8 || event.charactersIgnoringModifiers?.lowercased() == "c"
            let hasControl = event.modifierFlags.contains(.control)
            let hasCommand = event.modifierFlags.contains(.command)
            
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
