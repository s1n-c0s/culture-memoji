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
                // Crisp retina snapshot preserving exact viewport aspect ratio
                let minDim = min(boundsSize.width, boundsSize.height)
                let scale = max(2.0, 1024.0 / minDim)
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

/// An NSImageView that passes all mouse and hit-test events through to underlying views,
/// ensuring interactive 3D rotation and controls continue functioning uninterrupted.
private final class PassthroughImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}

/// Wraps Apple's AVTView (3D interactive SceneKit/VFX viewport) for SwiftUI.
public struct Avatar3DStageRepresentable: NSViewRepresentable {
    public let avatarId: String?
    public let avatar: AnyObject?
    public let activePoseName: String?
    public let isAnimoji: Bool
    public let animojiName: String?
    public let clone: Bool
    public let mutationId: UUID?
    public let stageController: StageViewController?
    public let onDoubleTap: (() -> Void)?
    
    public init(
        avatarId: String? = nil,
        avatar: AnyObject?,
        activePoseName: String? = nil,
        isAnimoji: Bool = false,
        animojiName: String? = nil,
        clone: Bool = true,
        mutationId: UUID? = nil,
        stageController: StageViewController? = nil,
        onDoubleTap: (() -> Void)? = nil
    ) {
        self.avatarId = avatarId
        self.avatar = avatar
        self.activePoseName = activePoseName
        self.isAnimoji = isAnimoji
        self.animojiName = animojiName
        self.clone = clone
        self.mutationId = mutationId
        self.stageController = stageController
        self.onDoubleTap = onDoubleTap
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
        context.coordinator.currentAvatarId = avatarId
        context.coordinator.currentPose = activePoseName
        context.coordinator.lastMutationId = mutationId
        context.coordinator.onDoubleTap = onDoubleTap
        context.coordinator.wasTracking = FaceTrackingManager.shared.isRunning
        
        let doubleClick = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleClick(_:)))
        doubleClick.numberOfClicksRequired = 2
        doubleClick.delaysPrimaryMouseButtonEvents = false
        doubleClick.delegate = context.coordinator
        avtView.addGestureRecognizer(doubleClick)
        
        // Apply initial pose after one runloop pass with smooth transition animation
        if let pose = activePoseName {
            DispatchQueue.main.async {
                AvatarKitBridge.shared.applyStickerPose(
                    named: pose,
                    to: avtView,
                    animojiNamed: isAnimoji ? animojiName : nil,
                    duration: 0.25
                )
            }
        }
        
        return container
    }
    
    public func updateNSView(_ nsView: NSView, context: Context) {
        guard let avtView = context.coordinator.avtView else { return }
        context.coordinator.onDoubleTap = onDoubleTap
        
        if let sc = stageController, sc.avtView !== avtView {
            sc.avtView = avtView
            context.coordinator.stageController = sc
        }
        
        // Ensure avtView always matches the container's bounds during frame changes / full screen
        if nsView.bounds.size.width > 0 && nsView.bounds.size.height > 0 && avtView.frame != nsView.bounds {
            avtView.frame = nsView.bounds
        }
        
        // Update avatar when avatarId or avatar instance changes
        let avatarChanged = context.coordinator.currentAvatarId != avatarId || context.coordinator.currentAvatar !== avatar
        if avatarChanged {
            context.coordinator.currentAvatarId = avatarId
            context.coordinator.currentAvatar = avatar
            context.coordinator.currentPose = activePoseName
            
            // Clean up any existing fade overlay in flight
            if let oldOverlay = context.coordinator.currentFadeOverlay {
                oldOverlay.layer?.removeAllAnimations()
                oldOverlay.removeFromSuperview()
                context.coordinator.currentFadeOverlay = nil
            }
            
            // Capture snapshot of previous avatar for smooth crossfade transition
            var overlay: PassthroughImageView? = nil
            let boundsSize = avtView.bounds.size
            if boundsSize.width > 0 && boundsSize.height > 0,
               let prevSnapshot = AvatarKitBridge.shared.snapshot(view: avtView, size: boundsSize) {
                let imgView = PassthroughImageView(frame: avtView.bounds)
                imgView.image = prevSnapshot
                imgView.imageScaling = .scaleAxesIndependently
                imgView.autoresizingMask = [.width, .height]
                imgView.wantsLayer = true
                imgView.alphaValue = 1.0
                nsView.addSubview(imgView, positioned: .above, relativeTo: avtView)
                context.coordinator.currentFadeOverlay = imgView
                overlay = imgView
            }
            
            // Set the newly selected avatar instance (cleans previous puppet and restores default framing)
            AvatarKitBridge.shared.setAvatar(avatar, on: avtView, clone: clone)
            
            // Always smoothly transition the new avatar into the pose or canonical neutral
            let targetId = avatarId
            DispatchQueue.main.async {
                guard context.coordinator.currentAvatarId == targetId else { return }
                if FaceTrackingManager.shared.isRunning {
                    AvatarKitBridge.shared.resetToNeutralPose(on: avtView, duration: 0.0)
                    FaceTrackingManager.shared.updateTargetView(avtView)
                } else if let pose = activePoseName {
                    AvatarKitBridge.shared.applyStickerPose(
                        named: pose,
                        to: avtView,
                        animojiNamed: isAnimoji ? animojiName : nil,
                        duration: 0.25
                    )
                } else {
                    AvatarKitBridge.shared.resetToNeutralPose(on: avtView, duration: 0.25)
                }
            }
            
            // Animate crossfade overlay fading out smoothly
            if let activeOverlay = overlay {
                let coordinator = context.coordinator
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.25)
                CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
                CATransaction.setCompletionBlock {
                    activeOverlay.removeFromSuperview()
                    if coordinator.currentFadeOverlay === activeOverlay {
                        coordinator.currentFadeOverlay = nil
                    }
                }
                activeOverlay.animator().alphaValue = 0.0
                CATransaction.commit()
            }
        } else if context.coordinator.lastMutationId != mutationId {
            // Explicit stage reset / mutation requested (e.g. from Reset button)
            context.coordinator.lastMutationId = mutationId
            context.coordinator.currentPose = activePoseName
            if activePoseName == nil {
                AvatarKitBridge.shared.resetCameraFraming(on: avtView, duration: 0.25)
            } else if let pose = activePoseName {
                AvatarKitBridge.shared.applyStickerPose(
                    named: pose,
                    to: avtView,
                    animojiNamed: isAnimoji ? animojiName : nil,
                    duration: 0.25
                )
            }
        } else {
            let isTracking = FaceTrackingManager.shared.isRunning
            let trackingChanged = context.coordinator.wasTracking != isTracking
            if trackingChanged {
                fileLog(String(format: "[STAGE] updateNSView — trackingChanged: %d → %d", context.coordinator.wasTracking ? 1 : 0, isTracking ? 1 : 0))
                context.coordinator.wasTracking = isTracking
                if isTracking {
                    // Tracking just started — if an emote was already selected and NOT yet playing, attach it
                    if let pose = activePoseName, !pose.isEmpty, pose != "neutral",
                       FaceTrackingManager.shared.activeEmoteName != pose {
                        fileLog(String(format: "[STAGE] updateNSView — tracking started, attaching emote '%@'", pose))
                        FaceTrackingManager.shared.playEmote(
                            named: pose, on: avtView,
                            isAnimoji: isAnimoji, animojiName: animojiName
                        )
                    }
                } else {
                    // Tracking stopped — clean up emote overlay and restore static pose
                    FaceTrackingManager.shared.cancelEmote(on: avtView, animated: false)
                    if let pose = activePoseName, !pose.isEmpty, pose != "neutral" {
                        AvatarKitBridge.shared.applyStickerPose(
                            named: pose,
                            to: avtView,
                            animojiNamed: isAnimoji ? animojiName : nil,
                            duration: 0.25
                        )
                    } else {
                        AvatarKitBridge.shared.resetToNeutralPose(on: avtView, duration: 0.25)
                    }
                }
            }
            
            if context.coordinator.currentPose != activePoseName {
                fileLog(String(format: "[STAGE] updateNSView — poseChanged: '%@' → '%@', isTracking=%d",
                      context.coordinator.currentPose ?? "nil", activePoseName ?? "nil",
                      FaceTrackingManager.shared.isRunning ? 1 : 0))
                // Update pose when changed (including nil = clear back to neutral)
                context.coordinator.currentPose = activePoseName
                if FaceTrackingManager.shared.isRunning {
                    // Live tracking is active — blend emote and attach 3D element emojis persistently
                    if let pose = activePoseName, !pose.isEmpty, pose != "neutral" {
                        FaceTrackingManager.shared.playEmote(
                            named: pose, on: avtView,
                            isAnimoji: isAnimoji, animojiName: animojiName
                        )
                    } else {
                        // Clearing emote while tracking — cancel active emote overlay
                        FaceTrackingManager.shared.cancelEmote(on: avtView)
                    }
                } else if let pose = activePoseName {
                    AvatarKitBridge.shared.applyStickerPose(
                        named: pose,
                        to: avtView,
                        animojiNamed: isAnimoji ? animojiName : nil,
                        duration: 0.25
                    )
                } else {
                    AvatarKitBridge.shared.resetToNeutralPose(on: avtView, duration: 0.25)
                }
            }
        }
    }
    
    public static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.currentFadeOverlay?.removeFromSuperview()
        coordinator.currentFadeOverlay = nil
        coordinator.stageController?.avtView = nil
        coordinator.stageController = nil
        if let avtView = coordinator.avtView {
            AvatarKitBridge.shared.setAvatar(nil, on: avtView)
            coordinator.avtView = nil
            coordinator.currentAvatar = nil
            coordinator.currentAvatarId = nil
        }
    }
    
    @MainActor
    public final class Coordinator: NSObject, NSGestureRecognizerDelegate {
        weak var stageController: StageViewController?
        var avtView: NSView?
        var currentAvatar: AnyObject?
        var currentAvatarId: String?
        var currentPose: String?
        var wasTracking: Bool = false
        var lastMutationId: UUID?
        var onDoubleTap: (() -> Void)?
        fileprivate var currentFadeOverlay: PassthroughImageView?
        
        @objc func handleDoubleClick(_ sender: NSClickGestureRecognizer) {
            if sender.state == .ended {
                onDoubleTap?()
            }
        }
        
        public func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: NSGestureRecognizer) -> Bool {
            return true
        }
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
