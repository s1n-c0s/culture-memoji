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
        // Use a strong container that auto-sizes correctly
        let container = FlippedView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        
        if let avtView = AvatarKitBridge.shared.createAVTView(frame: .zero, avatar: avatar) {
            avtView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(avtView)
            NSLayoutConstraint.activate([
                avtView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                avtView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                avtView.topAnchor.constraint(equalTo: container.topAnchor),
                avtView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
            context.coordinator.avtView = avtView
            context.coordinator.currentAvatar = avatar
            context.coordinator.currentPose = activePoseName
            
            if let pose = activePoseName {
                // Apply initial pose after a brief delay to allow 3D scene to load
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    AvatarKitBridge.shared.applyStickerPose(
                        named: pose,
                        to: avtView,
                        animojiNamed: isAnimoji ? animojiName : nil,
                        duration: 0.0
                    )
                }
            }
        }
        
        return container
    }
    
    public func updateNSView(_ nsView: NSView, context: Context) {
        guard let avtView = context.coordinator.avtView else { return }
        
        // Update avatar if reference changed
        if context.coordinator.currentAvatar !== avatar {
            context.coordinator.currentAvatar = avatar
            AvatarKitBridge.shared.setAvatar(avatar, on: avtView)
        }
        
        // Update pose if changed (including clearing back to nil)
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
            // If pose is cleared (nil), the avatar stays in last pose — reset by cycling avatar
            // This is fine UX behaviour (neutral reset button is shown to user separately)
        }
    }
    
    public class Coordinator {
        var avtView: NSView?
        var currentAvatar: AnyObject?
        var currentPose: String?
    }
}

/// NSView subclass that flips coordinate system, needed for correct AVTView layout on macOS.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
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
        let container = FlippedView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        
        if let recordView = AvatarKitBridge.shared.createAVTRecordView(frame: .zero, avatar: avatar) {
            recordView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(recordView)
            NSLayoutConstraint.activate([
                recordView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                recordView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                recordView.topAnchor.constraint(equalTo: container.topAnchor),
                recordView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
            context.coordinator.recordView = recordView
            context.coordinator.currentAvatar = avatar
            
            // Start face tracking after brief layout pass
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                AvatarKitBridge.shared.startCameraPreview(on: recordView)
            }
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
