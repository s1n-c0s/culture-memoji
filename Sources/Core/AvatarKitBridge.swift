import Foundation
import AppKit

/// High-level bridge to Apple's system AvatarKit framework.
/// Uses runtime dynamic loading to ensure compatibility and safe execution.
@MainActor
public final class AvatarKitBridge {
    public static let shared = AvatarKitBridge()
    
    private var isFrameworkLoaded = false
    private let avatarKitPath = "/System/Library/PrivateFrameworks/AvatarKit.framework"
    private let avatarPersistencePath = "/System/Library/PrivateFrameworks/AvatarPersistence.framework"
    
    // Cached Class pointers
    private var avtAvatarClass: AnyClass?
    private var avtMemojiClass: AnyClass?
    private var avtAnimojiClass: AnyClass?
    private var avtViewClass: AnyClass?
    private var avtRecordViewClass: AnyClass?
    private var avtStickerConfigurationClass: AnyClass?
    
    private init() {
        loadFrameworksIfNeeded()
    }
    
    @discardableResult
    public func loadFrameworksIfNeeded() -> Bool {
        if isFrameworkLoaded { return true }
        
        _ = Bundle(path: avatarPersistencePath)?.load()
        if let bundle = Bundle(path: avatarKitPath), bundle.load() {
            isFrameworkLoaded = true
            avtAvatarClass = NSClassFromString("AVTAvatar")
            avtMemojiClass = NSClassFromString("AVTMemoji")
            avtAnimojiClass = NSClassFromString("AVTAnimoji")
            avtViewClass = NSClassFromString("AVTView")
            avtRecordViewClass = NSClassFromString("AVTRecordView")
            avtStickerConfigurationClass = NSClassFromString("AVTStickerConfiguration")
            return true
        }
        return false
    }
    
    public var isAvailable: Bool {
        return isFrameworkLoaded && avtAvatarClass != nil
    }
    
    // MARK: - Avatar Creation
    
    /// Loads an avatar from system JSON/binary data representation (from avatars.db)
    public func loadAvatar(fromData data: Data) -> AnyObject? {
        guard let cls = avtAvatarClass else { return nil }
        let sel = NSSelectorFromString("avatarWithDataRepresentation:error:")
        
        typealias InitFunc = @convention(c) (AnyObject, Selector, AnyObject, UnsafeMutablePointer<NSError?>?) -> AnyObject?
        guard let method = class_getClassMethod(cls, sel) else { return nil }
        let callable = unsafeBitCast(method_getImplementation(method), to: InitFunc.self)
        var error: NSError?
        return callable(cls as AnyObject, sel, data as NSData, &error)
    }
    
    /// Loads a neutral Memoji
    public func loadNeutralMemoji() -> AnyObject? {
        guard let cls = avtMemojiClass else { return nil }
        let sel = NSSelectorFromString("neutralMemoji")
        
        typealias NeutralFunc = @convention(c) (AnyObject, Selector) -> AnyObject?
        guard let method = class_getClassMethod(cls, sel) else { return nil }
        let callable = unsafeBitCast(method_getImplementation(method), to: NeutralFunc.self)
        return callable(cls as AnyObject, sel)
    }
    
    /// Creates a completely randomized 3D Memoji
    public func createRandomMemoji() -> AnyObject? {
        guard let memoji = loadNeutralMemoji() else { return nil }
        let randSel = NSSelectorFromString("randomize")
        if (memoji as AnyObject).responds(to: randSel) {
            _ = (memoji as AnyObject).perform(randSel)
        }
        return memoji
    }
    
    /// Gets the data representation (JSON) of any avatar
    public func dataRepresentation(for avatar: AnyObject) -> Data? {
        let sel = NSSelectorFromString("dataRepresentation")
        guard avatar.responds(to: sel) else { return nil }
        return (avatar as AnyObject).perform(sel)?.takeUnretainedValue() as? Data
    }
    
    // MARK: - Animojis
    
    /// List of all built-in Apple Animoji names (e.g. "fox", "robot", "unicorn", "dragon")
    public func animojiNames() -> [String] {
        guard let cls = avtAnimojiClass else { return [] }
        let sel = NSSelectorFromString("animojiNames")
        
        typealias NamesFunc = @convention(c) (AnyObject, Selector) -> [String]?
        guard let method = class_getClassMethod(cls, sel) else { return [] }
        let callable = unsafeBitCast(method_getImplementation(method), to: NamesFunc.self)
        return callable(cls as AnyObject, sel) ?? []
    }
    
    /// Loads an Animoji by name
    public func loadAnimoji(named name: String) -> AnyObject? {
        guard let cls = avtAnimojiClass else { return nil }
        let sel = NSSelectorFromString("animojiNamed:")
        
        typealias AnimojiFunc = @convention(c) (AnyObject, Selector, NSString) -> AnyObject?
        guard let method = class_getClassMethod(cls, sel) else { return nil }
        let callable = unsafeBitCast(method_getImplementation(method), to: AnimojiFunc.self)
        return callable(cls as AnyObject, sel, name as NSString)
    }
    
    /// Gets built-in thumbnail for an Animoji
    public func animojiThumbnail(named name: String) -> NSImage? {
        guard let cls = avtAnimojiClass else { return nil }
        let sel = NSSelectorFromString("thumbnailForAnimojiNamed:options:")
        
        typealias ThumbFunc = @convention(c) (AnyObject, Selector, NSString, AnyObject?) -> AnyObject?
        guard let method = class_getClassMethod(cls, sel) else { return nil }
        let callable = unsafeBitCast(method_getImplementation(method), to: ThumbFunc.self)
        return callable(cls as AnyObject, sel, name as NSString, nil) as? NSImage
    }
    
    // MARK: - Views (AVTView & AVTRecordView)
    
    /// Creates an interactive 3D AVTView for embedding in SwiftUI
    public func createAVTView(frame: NSRect, avatar: AnyObject? = nil) -> NSView? {
        guard let viewCls = avtViewClass as? NSView.Type else { return nil }
        let view = viewCls.init(frame: frame)
        
        // NOTE: Do NOT set wantsLayer or modify the layer here.
        // AVTView has wantsLayer=true and a Metal CALayer already set up internally.
        // Adding another CA layer hierarchy breaks its rendering pipeline.
        
        if let avatar = avatar {
            setAvatar(avatar, on: view)
        }
        
        // Enable continuous rendering for smooth physics and animations
        let contSel = NSSelectorFromString("setRendersContinuously:")
        if view.responds(to: contSel),
           let method = class_getInstanceMethod(type(of: view), contSel) {
            typealias BoolFunc = @convention(c) (AnyObject, Selector, Bool) -> Void
            let callable = unsafeBitCast(method_getImplementation(method), to: BoolFunc.self)
            callable(view, contSel, true)
        }
        
        // Enable interactive 3D camera controls (scroll to zoom, drag to rotate)
        let ctrlSel = NSSelectorFromString("setAllowsCameraControl:")
        if view.responds(to: ctrlSel) {
            _ = (view as AnyObject).perform(ctrlSel, with: true as NSNumber)
        }
        
        // Set comfortable uncropped default FOV (46.0) so the model never touches viewport edges
        setCameraFieldOfView(46.0, on: view)
        
        return view
    }
    
    /// Sets camera field of view on an AVTView to control framing and prevent cropping
    public func setCameraFieldOfView(_ fov: Double, on view: NSView) {
        let povSel = NSSelectorFromString("pointOfView")
        guard let pov = (view as AnyObject).perform(povSel)?.takeUnretainedValue() else { return }
        let camSel = NSSelectorFromString("camera")
        guard let cam = (pov as AnyObject).perform(camSel)?.takeUnretainedValue() else { return }
        (cam as AnyObject).setValue(fov, forKey: "fieldOfView")
    }
    
    /// Creates an AVTRecordView for live camera face-tracking
    public func createAVTRecordView(frame: NSRect, avatar: AnyObject? = nil) -> NSView? {
        guard let viewCls = avtRecordViewClass as? NSView.Type else { return nil }
        let view = viewCls.init(frame: frame)
        
        // NOTE: Do NOT set wantsLayer or modify the layer — same reason as AVTView above.
        
        if let avatar = avatar {
            setAvatar(avatar, on: view)
        }
        
        return view
    }
    
    /// Clones an avatar instance (AVTMemoji or AVTAnimoji) so each view owns an isolated SceneKit/VFX graph
    public func cloneAvatar(_ avatar: AnyObject?) -> AnyObject? {
        guard let avatar = avatar else { return nil }
        let copySel = NSSelectorFromString("copy")
        if (avatar as AnyObject).responds(to: copySel),
           let cloned = (avatar as AnyObject).perform(copySel)?.takeRetainedValue() {
            return cloned
        }
        return avatar
    }
    
    /// Sets an avatar onto an AVTView or AVTRecordView, optionally cloning it to give each view an isolated clone
    public func setAvatar(_ avatar: AnyObject?, on view: NSView, clone: Bool = true) {
        let sel = NSSelectorFromString("setAvatar:")
        guard view.responds(to: sel) else { return }
        let targetAvatar = (avatar != nil && clone) ? cloneAvatar(avatar) : avatar
        _ = (view as AnyObject).perform(sel, with: targetAvatar)
    }
    
    /// Notifies an AVTView that its avatar's attributes changed so it triggers a visual redraw
    public func notifyAvatarDidChange(on view: NSView) {
        let sel = NSSelectorFromString("avatarDidChange")
        if view.responds(to: sel) {
            _ = (view as AnyObject).perform(sel)
        }
    }
    
    /// Starts live camera face-tracking preview on an AVTRecordView
    public func startCameraPreview(on recordView: NSView) {
        let sel = NSSelectorFromString("startPreviewing")
        if recordView.responds(to: sel) {
            _ = (recordView as AnyObject).perform(sel)
        }
    }
    
    /// Stops live camera preview on an AVTRecordView
    public func stopCameraPreview(on recordView: NSView) {
        let sel = NSSelectorFromString("stopPreviewing")
        if recordView.responds(to: sel) {
            _ = (recordView as AnyObject).perform(sel)
        }
    }
    
    // MARK: - Stickers & Poses
    
    /// The two packs that together cover all available Memoji/Animoji poses
    private let stickerPacks = ["stickers", "posesPack"]
    
    /// Lists all sticker names from BOTH the "stickers" and "posesPack" packs,
    /// deduped and in stable order (stickers first, posesPack after).
    public func availableStickerNames(forAnimojiNamed name: String?) -> [String] {
        guard let cls = avtStickerConfigurationClass else { return [] }
        
        var seen = Set<String>()
        var result: [String] = []
        
        for pack in stickerPacks {
            let names: [String]?
            if let animojiName = name {
                let sel = NSSelectorFromString("availableStickerNamesForAnimojiNamed:inStickerPack:")
                typealias Func = @convention(c) (AnyObject, Selector, NSString, NSString) -> [String]?
                guard let method = class_getClassMethod(cls, sel) else { continue }
                names = unsafeBitCast(method_getImplementation(method), to: Func.self)(
                    cls as AnyObject, sel, animojiName as NSString, pack as NSString)
            } else {
                let sel = NSSelectorFromString("availableStickerNamesForMemojiInStickerPack:")
                typealias Func = @convention(c) (AnyObject, Selector, NSString) -> [String]?
                guard let method = class_getClassMethod(cls, sel) else { continue }
                names = unsafeBitCast(method_getImplementation(method), to: Func.self)(
                    cls as AnyObject, sel, pack as NSString)
            }
            for n in (names ?? []) where seen.insert(n).inserted {
                result.append(n)
            }
        }
        
        return result
    }
    
    /// Loads a sticker configuration by name, searching both "stickers" and "posesPack".
    /// Returns nil safely if not found in either pack.
    public func stickerConfiguration(named stickerName: String, animojiNamed: String? = nil) -> AnyObject? {
        guard let cls = avtStickerConfigurationClass else { return nil }
        
        for pack in stickerPacks {
            let cfg: AnyObject?
            if let animoji = animojiNamed {
                let sel = NSSelectorFromString("stickerConfigurationForAnimojiNamed:inStickerPack:stickerName:")
                typealias Func = @convention(c) (AnyObject, Selector, NSString, NSString, NSString) -> AnyObject?
                guard let method = class_getClassMethod(cls, sel) else { continue }
                cfg = unsafeBitCast(method_getImplementation(method), to: Func.self)(
                    cls as AnyObject, sel, animoji as NSString, pack as NSString, stickerName as NSString)
            } else {
                let sel = NSSelectorFromString("stickerConfigurationForMemojiInStickerPack:stickerName:")
                typealias Func = @convention(c) (AnyObject, Selector, NSString, NSString) -> AnyObject?
                guard let method = class_getClassMethod(cls, sel) else { continue }
                cfg = unsafeBitCast(method_getImplementation(method), to: Func.self)(
                    cls as AnyObject, sel, pack as NSString, stickerName as NSString)
            }
            
            if let validCfg = cfg {
                // Pre-load the pose data into memory
                let loadSel = NSSelectorFromString("loadIfNeeded")
                if (validCfg as AnyObject).responds(to: loadSel) {
                    _ = (validCfg as AnyObject).perform(loadSel)
                }
                return validCfg
            }
        }
        
        return nil // Not found in any known pack
    }
    
    /// Smoothly transitions the 3D AVTView to a given sticker pose/expression,
    /// ensuring the camera FOV is calibrated so hands, gestures, and accessories are never cropped.
    public func applyStickerPose(named stickerName: String, to view: NSView, animojiNamed: String? = nil, duration: Double = 0.25) {
        guard let cfg = stickerConfiguration(named: stickerName, animojiNamed: animojiNamed) else {
            return // Pose not found — silently skip to avoid crash
        }
        
        // Calibrate sticker camera FOV so hands and wide gestures don't get cropped
        let camSel = NSSelectorFromString("camera")
        if let stickerCam = (cfg as AnyObject).perform(camSel)?.takeUnretainedValue() {
            let nodeSel = NSSelectorFromString("node")
            if let camNode = (stickerCam as AnyObject).perform(nodeSel)?.takeUnretainedValue() {
                let actualCamSel = NSSelectorFromString("camera")
                if let actualCam = (camNode as AnyObject).perform(actualCamSel)?.takeUnretainedValue() {
                    let currentFov = (actualCam as AnyObject).value(forKey: "fieldOfView") as? Double ?? 31.89
                    // Ensure FOV is at least 42.0 degrees (or ~22% wider) to avoid cropping hands/arms/accessories
                    let uncroppedFov = max(currentFov * 1.22, 42.0)
                    (actualCam as AnyObject).setValue(uncroppedFov, forKey: "fieldOfView")
                }
            }
        }
        
        let transSel = NSSelectorFromString("transitionToStickerConfiguration:duration:completionHandler:")
        guard view.responds(to: transSel),
              let method = class_getInstanceMethod(type(of: view), transSel) else { return }
        
        typealias TransFunc = @convention(c) (AnyObject, Selector, AnyObject?, Double, (@convention(block) () -> Void)?) -> Void
        let callable = unsafeBitCast(method_getImplementation(method), to: TransFunc.self)
        callable(view, transSel, cfg, duration, { [weak self] in
            // Ensure active pointOfView camera maintains uncropped FOV
            let povSel = NSSelectorFromString("pointOfView")
            if let pov = (view as AnyObject).perform(povSel)?.takeUnretainedValue() {
                if let activeCam = (pov as AnyObject).perform(camSel)?.takeUnretainedValue() {
                    let fov = (activeCam as AnyObject).value(forKey: "fieldOfView") as? Double ?? 0
                    if fov < 40.0 {
                        self?.setCameraFieldOfView(42.0, on: view)
                    }
                }
            }
        })
    }
    
    /// Smoothly transitions back to neutral pose and resets camera to uncropped default framing
    public func resetToNeutralPose(on view: NSView, duration: Double = 0.25) {
        let transSel = NSSelectorFromString("transitionToStickerConfiguration:duration:completionHandler:")
        guard view.responds(to: transSel),
              let method = class_getInstanceMethod(type(of: view), transSel) else { return }
        
        typealias TransFunc = @convention(c) (AnyObject, Selector, AnyObject?, Double, (@convention(block) () -> Void)?) -> Void
        let callable = unsafeBitCast(method_getImplementation(method), to: TransFunc.self)
        callable(view, transSel, nil, duration, { [weak self] in
            self?.setCameraFieldOfView(46.0, on: view)
        })
    }
    
    // MARK: - Snapshots & Rendering
    
    /// Snapshots an avatar directly at a specified size and retina scale
    public func snapshot(avatar: AnyObject, size: CGSize, scale: CGFloat = 2.0) -> NSImage? {
        let sel = NSSelectorFromString("snapshotWithSize:scale:options:")
        guard avatar.responds(to: sel),
              let method = class_getInstanceMethod(type(of: avatar), sel) else { return nil }
        
        typealias SnapFunc = @convention(c) (AnyObject, Selector, CGSize, CGFloat, AnyObject?) -> AnyObject?
        let callable = unsafeBitCast(method_getImplementation(method), to: SnapFunc.self)
        return callable(avatar, sel, size, scale, nil) as? NSImage
    }
    
    /// Snapshots the current 3D AVTView state
    public func snapshot(view: NSView, size: CGSize) -> NSImage? {
        let sel = NSSelectorFromString("snapshotWithSize:")
        guard view.responds(to: sel),
              let method = class_getInstanceMethod(type(of: view), sel) else { return nil }
        
        typealias SnapFunc = @convention(c) (AnyObject, Selector, CGSize) -> AnyObject?
        let callable = unsafeBitCast(method_getImplementation(method), to: SnapFunc.self)
        return callable(view, sel, size) as? NSImage
    }
}
