import SwiftUI
import AppKit

public struct Avatar3DStageRepresentable: NSViewRepresentable {
    public let avatar: AnyObject?
    public let activePoseName: String?
    public let isAnimoji: Bool
    public let animojiName: String?
    
    public init(
        avatar: AnyObject?,
        activePoseName: String? = nil,
        isAnimoji: Bool = false,
        animojiName: String? = nil
    ) {
        self.avatar = avatar
        self.activePoseName = activePoseName
        self.isAnimoji = isAnimoji
        self.animojiName = animojiName
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    public func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        
        if let avtView = AvatarKitBridge.shared.createAVTView(frame: container.bounds, avatar: avatar) {
            avtView.autoresizingMask = [.width, .height]
            container.addSubview(avtView)
            context.coordinator.avtView = avtView
            context.coordinator.currentAvatar = avatar
            
            if let pose = activePoseName {
                AvatarKitBridge.shared.applyStickerPose(
                    named: pose,
                    to: avtView,
                    animojiNamed: isAnimoji ? animojiName : nil,
                    duration: 0.0
                )
            }
        }
        
        return container
    }
    
    public func updateNSView(_ nsView: NSView, context: Context) {
        guard let avtView = context.coordinator.avtView else { return }
        
        // Update avatar if changed
        if context.coordinator.currentAvatar !== avatar {
            context.coordinator.currentAvatar = avatar
            AvatarKitBridge.shared.setAvatar(avatar, on: avtView)
        }
        
        // Update pose if changed
        if context.coordinator.currentPose != activePoseName {
            context.coordinator.currentPose = activePoseName
            if let pose = activePoseName {
                AvatarKitBridge.shared.applyStickerPose(
                    named: pose,
                    to: avtView,
                    animojiNamed: isAnimoji ? animojiName : nil,
                    duration: 0.3
                )
            }
        }
    }
    
    public class Coordinator {
        var avtView: NSView?
        var currentAvatar: AnyObject?
        var currentPose: String?
    }
}

public struct LiveFaceMirrorRepresentable: NSViewRepresentable {
    public let avatar: AnyObject?
    
    public init(avatar: AnyObject?) {
        self.avatar = avatar
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    public func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        
        if let recordView = AvatarKitBridge.shared.createAVTRecordView(frame: container.bounds, avatar: avatar) {
            recordView.autoresizingMask = [.width, .height]
            container.addSubview(recordView)
            context.coordinator.recordView = recordView
            
            // Start face tracking
            AvatarKitBridge.shared.startCameraPreview(on: recordView)
        }
        
        return container
    }
    
    public func updateNSView(_ nsView: NSView, context: Context) {
        guard let recordView = context.coordinator.recordView else { return }
        if context.coordinator.currentAvatar !== avatar {
            context.coordinator.currentAvatar = avatar
            AvatarKitBridge.shared.setAvatar(avatar, on: recordView)
        }
    }
    
    public static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let recordView = coordinator.recordView {
            AvatarKitBridge.shared.stopCameraPreview(on: recordView)
        }
    }
    
    public class Coordinator {
        var recordView: NSView?
        var currentAvatar: AnyObject?
    }
}
