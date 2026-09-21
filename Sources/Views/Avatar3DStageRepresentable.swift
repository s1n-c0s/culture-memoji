import SwiftUI
import AppKit

/// Wraps Apple's AVTView (3D interactive SceneKit/VFX viewport) for SwiftUI.
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
        // Plain NSView container — DO NOT set wantsLayer or FlippedView.
        // AVTView is already layer-backed (wantsLayer=true, isFlipped=false internally),
        // and putting it inside a flipped or extra-layer container breaks its Metal renderer.
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        container.autoresizesSubviews = true
        
        guard let avtView = AvatarKitBridge.shared.createAVTView(frame: container.bounds, avatar: avatar) else {
            return container
        }
        
        // autoresizingMask keeps AVTView filling its container across resize events
        avtView.autoresizingMask = [.width, .height]
        container.addSubview(avtView)
        
        context.coordinator.avtView = avtView
        context.coordinator.currentAvatar = avatar
        context.coordinator.currentPose = activePoseName
        
        // Apply initial pose after one runloop pass to allow the Metal scene to load
        if let pose = activePoseName {
            DispatchQueue.main.async {
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
        
        // Ensure avtView always matches the container's bounds during frame changes / full screen
        if nsView.bounds.size.width > 0 && nsView.bounds.size.height > 0 && avtView.frame != nsView.bounds {
            avtView.frame = nsView.bounds
        }
        
        // Update avatar only when the actual object reference changes
        if context.coordinator.currentAvatar !== avatar {
            context.coordinator.currentAvatar = avatar
            AvatarKitBridge.shared.setAvatar(avatar, on: avtView)
        }
        
        // Update pose when changed (including nil = clear back to neutral)
        if context.coordinator.currentPose != activePoseName {
            context.coordinator.currentPose = activePoseName
            if let pose = activePoseName {
                AvatarKitBridge.shared.applyStickerPose(
                    named: pose,
                    to: avtView,
                    animojiNamed: isAnimoji ? animojiName : nil,
                    duration: 0.35
                )
            }
        }
    }
    
    public static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let avtView = coordinator.avtView {
            AvatarKitBridge.shared.setAvatar(nil, on: avtView)
            coordinator.avtView = nil
            coordinator.currentAvatar = nil
        }
    }
    
    public class Coordinator {
        var avtView: NSView?
        var currentAvatar: AnyObject?
        var currentPose: String?
    }
}

/// Wraps Apple's AVTRecordView (live face-tracking camera mirror) for SwiftUI.
public struct LiveFaceMirrorRepresentable: NSViewRepresentable {
    public let avatar: AnyObject?
    
    public init(avatar: AnyObject?) {
        self.avatar = avatar
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    public func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        
        guard let recordView = AvatarKitBridge.shared.createAVTRecordView(frame: container.bounds, avatar: avatar) else {
            return container
        }
        
        recordView.autoresizingMask = [.width, .height]
        container.addSubview(recordView)
        context.coordinator.recordView = recordView
        context.coordinator.currentAvatar = avatar
        
        // Start camera face-tracking after one runloop pass
        DispatchQueue.main.async {
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
