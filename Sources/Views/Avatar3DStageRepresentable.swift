import SwiftUI
import AppKit

/// Controller for inspecting and capturing the live 3D stage viewport
@MainActor
public final class StageViewController: ObservableObject {
    weak var avtView: NSView?
    
    public init() {}
    
    /// Snapshots the live 3D viewport exactly as currently rendered (including camera angle, FOV, and pose)
    public func captureSnapshot(preferredSize: CGSize? = nil) -> NSImage? {
        guard let view = avtView else { return nil }
        
        let targetSize: CGSize
        if let size = preferredSize, size.width > 0 && size.height > 0 {
            targetSize = size
        } else {
            let boundsSize = view.bounds.size
            if boundsSize.width > 0 && boundsSize.height > 0 {
                // Crisp 2x retina snapshot (at least 1024px for sharp export)
                let scale = max(2.0, 1024.0 / max(boundsSize.width, boundsSize.height))
                targetSize = CGSize(
                    width: (boundsSize.width * scale).rounded(),
                    height: (boundsSize.height * scale).rounded()
                )
            } else {
                targetSize = CGSize(width: 1024, height: 1024)
            }
        }
        
        return AvatarKitBridge.shared.snapshot(view: view, size: targetSize)
    }
}

/// Wraps Apple's AVTView (3D interactive SceneKit/VFX viewport) for SwiftUI.
public struct Avatar3DStageRepresentable: NSViewRepresentable {
    public let avatar: AnyObject?
    public let activePoseName: String?
    public let isAnimoji: Bool
    public let animojiName: String?
    public let clone: Bool
    public let mutationId: UUID?
    public let stageController: StageViewController?
    
    public init(
        avatar: AnyObject?,
        activePoseName: String? = nil,
        isAnimoji: Bool = false,
        animojiName: String? = nil,
        clone: Bool = true,
        mutationId: UUID? = nil,
        stageController: StageViewController? = nil
    ) {
        self.avatar = avatar
        self.activePoseName = activePoseName
        self.isAnimoji = isAnimoji
        self.animojiName = animojiName
        self.clone = clone
        self.mutationId = mutationId
        self.stageController = stageController
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
        
        guard let avtView = AvatarKitBridge.shared.createAVTView(frame: container.bounds, avatar: nil) else {
            return container
        }
        
        // Set avatar with clone flag
        if let avatar = avatar {
            AvatarKitBridge.shared.setAvatar(avatar, on: avtView, clone: clone)
        }
        
        // autoresizingMask keeps AVTView filling its container across resize events
        avtView.autoresizingMask = [.width, .height]
        container.addSubview(avtView)
        
        stageController?.avtView = avtView
        context.coordinator.stageController = stageController
        context.coordinator.avtView = avtView
        context.coordinator.currentAvatar = avatar
        context.coordinator.currentPose = activePoseName
        context.coordinator.lastMutationId = mutationId
        
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
        
        if let sc = stageController, sc.avtView !== avtView {
            sc.avtView = avtView
            context.coordinator.stageController = sc
        }
        
        // Ensure avtView always matches the container's bounds during frame changes / full screen
        if nsView.bounds.size.width > 0 && nsView.bounds.size.height > 0 && avtView.frame != nsView.bounds {
            avtView.frame = nsView.bounds
        }
        
        // Update avatar only when the actual object reference changes
        if context.coordinator.currentAvatar !== avatar {
            context.coordinator.currentAvatar = avatar
            context.coordinator.currentPose = activePoseName
            
            // 1. Purge any lingering sticker props / camera offsets from previous avatar
            AvatarKitBridge.shared.resetToNeutralPose(on: avtView, duration: 0.0)
            
            // 2. Set the newly selected avatar instance
            AvatarKitBridge.shared.setAvatar(avatar, on: avtView, clone: clone)
            
            // 3. Immediately apply the current active emote to the new character
            if let pose = activePoseName {
                DispatchQueue.main.async {
                    guard context.coordinator.currentAvatar === avatar else { return }
                    AvatarKitBridge.shared.applyStickerPose(
                        named: pose,
                        to: avtView,
                        animojiNamed: isAnimoji ? animojiName : nil,
                        duration: 0.0
                    )
                }
            } else {
                AvatarKitBridge.shared.resetToNeutralPose(on: avtView, duration: 0.0)
            }
        } else if context.coordinator.currentPose != activePoseName {
            // Update pose when changed (including nil = clear back to neutral)
            context.coordinator.currentPose = activePoseName
            if let pose = activePoseName {
                AvatarKitBridge.shared.applyStickerPose(
                    named: pose,
                    to: avtView,
                    animojiNamed: isAnimoji ? animojiName : nil,
                    duration: 0.18
                )
            } else {
                AvatarKitBridge.shared.resetToNeutralPose(on: avtView, duration: 0.18)
            }
        }
    }
    
    public static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stageController?.avtView = nil
        coordinator.stageController = nil
        if let avtView = coordinator.avtView {
            AvatarKitBridge.shared.setAvatar(nil, on: avtView)
            coordinator.avtView = nil
            coordinator.currentAvatar = nil
        }
    }
    
    public class Coordinator {
        weak var stageController: StageViewController?
        var avtView: NSView?
        var currentAvatar: AnyObject?
        var currentPose: String?
        var lastMutationId: UUID?
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
