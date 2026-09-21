import Foundation
import AppKit
import simd

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
        
        // Stabilize camera controller orbit target and up-vector
        stabilizeCameraController(on: view)
        
        // Set comfortable uncropped default FOV (46.0) so the model never touches viewport edges
        setCameraFieldOfView(46.0, on: view)
        
        return view
    }
    
    /// Stabilizes the camera controller by locking orbit target to the avatar head center (0, 10, 0),
    /// fixing world up-vector to (0, 1, 0), clearing roll/gimbal flip, and disabling hit-test target drift.
    public func stabilizeCameraController(on view: NSView, centerTarget: SIMD3<Float> = SIMD3<Float>(0, 10, 0)) {
        let camCtrlSel = NSSelectorFromString("defaultCameraController")
        guard view.responds(to: camCtrlSel),
              let camCtrl = (view as AnyObject).perform(camCtrlSel)?.takeUnretainedValue() else { return }
        
        // 1. Disable hit-test target snapping so mouse clicks on face/mesh don't move orbit center
        (camCtrl as AnyObject).setValue(false, forKey: "automaticTarget")
        (camCtrl as AnyObject).setValue(false, forKey: "isTargetFromHitTest")
        
        // 2. Stop any ongoing inertia
        let stopSel = NSSelectorFromString("stopInertia")
        if camCtrl.responds(to: stopSel) {
            _ = (camCtrl as AnyObject).perform(stopSel)
        }
        
        // 3. Clear roll/tilt
        let clearRollSel = NSSelectorFromString("clearRoll")
        if camCtrl.responds(to: clearRollSel) {
            _ = (camCtrl as AnyObject).perform(clearRollSel)
        }
        
        // 4. Reset internal orientation state
        let resetStateSel = NSSelectorFromString("_resetOrientationState")
        if camCtrl.responds(to: resetStateSel) {
            _ = (camCtrl as AnyObject).perform(resetStateSel)
        }
        
        // 5. Lock target to head center
        typealias VecFunc = @convention(c) (AnyObject, Selector, SIMD3<Float>) -> Void
        let setTargetSel = NSSelectorFromString("setTarget:")
        if let m = class_getInstanceMethod(type(of: camCtrl), setTargetSel) {
            unsafeBitCast(method_getImplementation(m), to: VecFunc.self)(camCtrl, setTargetSel, centerTarget)
        }
        
        // 6. Lock up and worldUp to true vertical
        let setUpSel = NSSelectorFromString("setUp:")
        if let m = class_getInstanceMethod(type(of: camCtrl), setUpSel) {
            unsafeBitCast(method_getImplementation(m), to: VecFunc.self)(camCtrl, setUpSel, SIMD3<Float>(0, 1, 0))
        }
        let setWorldUpSel = NSSelectorFromString("setWorldUp:")
        if let m = class_getInstanceMethod(type(of: camCtrl), setWorldUpSel) {
            unsafeBitCast(method_getImplementation(m), to: VecFunc.self)(camCtrl, setWorldUpSel, SIMD3<Float>(0, 1, 0))
        }
        
        // 7. Ensure active pointOfView has zero roll (no diagonal tilt)
        let povSel = NSSelectorFromString("pointOfView")
        if view.responds(to: povSel),
           let pov = (view as AnyObject).perform(povSel)?.takeUnretainedValue() {
            typealias PosFunc = @convention(c) (AnyObject, Selector) -> SIMD3<Float>
            let mEuler = class_getInstanceMethod(type(of: pov), NSSelectorFromString("eulerAngles"))
            let mSetEuler = class_getInstanceMethod(type(of: pov), NSSelectorFromString("setEulerAngles:"))
            if let mE = mEuler, let mSE = mSetEuler {
                var e = unsafeBitCast(method_getImplementation(mE), to: PosFunc.self)(pov, NSSelectorFromString("eulerAngles"))
                if abs(abs(e.z) - Float.pi) < 0.5 {
                    e.x = Float.pi - e.x
                    e.y = e.y + Float.pi
                    e.z = 0
                } else {
                    e.z = 0
                }
                unsafeBitCast(method_getImplementation(mSE), to: VecFunc.self)(pov, NSSelectorFromString("setEulerAngles:"), e)
            }
        }
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
    /// ensuring the camera rotation axis remains stable and upright.
    public func applyStickerPose(named stickerName: String, to view: NSView, animojiNamed: String? = nil, duration: Double = 0.25) {
        guard let cfg = stickerConfiguration(named: stickerName, animojiNamed: animojiNamed) else {
            return // Pose not found — silently skip to avoid crash
        }
        
        // Stabilize camera controller before transition begins to halt any ongoing drags/inertia
        stabilizeCameraController(on: view)
        
        let transSel = NSSelectorFromString("transitionToStickerConfiguration:duration:completionHandler:")
        guard view.responds(to: transSel),
              let method = class_getInstanceMethod(type(of: view), transSel) else { return }
        
        typealias TransFunc = @convention(c) (AnyObject, Selector, AnyObject?, Double, (@convention(block) () -> Void)?) -> Void
        let callable = unsafeBitCast(method_getImplementation(method), to: TransFunc.self)
        callable(view, transSel, cfg, duration, { [weak self] in
            // Re-stabilize camera controller on the newly attached sticker camera
            self?.stabilizeCameraController(on: view)
        })
    }
    
    /// Smoothly transitions back to neutral pose, restores canonical frontal camera framing,
    /// and stabilizes the camera controller axis so future rotations remain upright.
    public func resetToNeutralPose(on view: NSView, duration: Double = 0.25) {
        stabilizeCameraController(on: view)
        
        let transSel = NSSelectorFromString("transitionToStickerConfiguration:duration:completionHandler:")
        guard view.responds(to: transSel),
              let method = class_getInstanceMethod(type(of: view), transSel) else { return }
        
        typealias TransFunc = @convention(c) (AnyObject, Selector, AnyObject?, Double, (@convention(block) () -> Void)?) -> Void
        let callable = unsafeBitCast(method_getImplementation(method), to: TransFunc.self)
        callable(view, transSel, nil, duration, { [weak self] in
            // Restore canonical front camera framing: pos (0, 15, 59.59), rot (-1, 0, 0, 0.06951647)
            let povSel = NSSelectorFromString("pointOfView")
            if let pov = (view as AnyObject).perform(povSel)?.takeUnretainedValue() {
                typealias VecFunc = @convention(c) (AnyObject, Selector, SIMD3<Float>) -> Void
                typealias RotFunc = @convention(c) (AnyObject, Selector, SIMD4<Float>) -> Void
                let mSetPos = class_getInstanceMethod(type(of: pov), NSSelectorFromString("setPosition:"))
                if let m = mSetPos {
                    unsafeBitCast(method_getImplementation(m), to: VecFunc.self)(pov, NSSelectorFromString("setPosition:"), SIMD3<Float>(0, 15, 59.59))
                }
                let mSetRot = class_getInstanceMethod(type(of: pov), NSSelectorFromString("setRotation:"))
                if let m = mSetRot {
                    unsafeBitCast(method_getImplementation(m), to: RotFunc.self)(pov, NSSelectorFromString("setRotation:"), SIMD4<Float>(-1.0, 0.0, 0.0, 0.06951647))
                }
            }
            self?.setCameraFieldOfView(46.0, on: view)
            self?.stabilizeCameraController(on: view)
        })
    }
    
    /// Explicitly resets the camera framing, position, and orientation back to the canonical front view
    public func resetCameraFraming(on view: NSView) {
        resetToNeutralPose(on: view, duration: 0.25)
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
        if view.responds(to: sel),
           let method = class_getInstanceMethod(type(of: view), sel) {
            typealias SnapFunc = @convention(c) (AnyObject, Selector, CGSize) -> AnyObject?
            let callable = unsafeBitCast(method_getImplementation(method), to: SnapFunc.self)
            if let img = callable(view, sel, size) as? NSImage {
                return img
            }
        }
        
        let snapSel = NSSelectorFromString("snapshot")
        if view.responds(to: snapSel),
           let method = class_getInstanceMethod(type(of: view), snapSel) {
            typealias FallbackFunc = @convention(c) (AnyObject, Selector) -> AnyObject?
            let callable = unsafeBitCast(method_getImplementation(method), to: FallbackFunc.self)
            if let img = callable(view, snapSel) as? NSImage {
                return img
            }
        }
        
        return nil
    }
    
    // Reusable offscreen view and sticker cache for fast posed sticker snapshots
    private var reusableSnapshotView: NSView?
    private let posedStickerCache = NSCache<NSString, NSImage>()
    
    /// Clears cached posed sticker images (e.g. after customizing an avatar)
    public func clearPosedStickerCache() {
        posedStickerCache.removeAllObjects()
    }
    
    /// Snapshots an avatar in a specific sticker pose with transparent background
    public func snapshot(
        avatar: AnyObject,
        poseName: String?,
        animojiNamed: String? = nil,
        size: CGSize = CGSize(width: 512, height: 512)
    ) -> NSImage? {
        guard let pose = poseName, !pose.isEmpty, pose != "neutral" else {
            return snapshot(avatar: avatar, size: size, scale: 2.0)
        }
        
        // Check cache first (instant)
        let cacheKey = "\(UInt(bitPattern: ObjectIdentifier(avatar)))_\(pose)_\(animojiNamed ?? "memoji")_\(Int(size.width))" as NSString
        if let cached = posedStickerCache.object(forKey: cacheKey) {
            return cached
        }
        
        guard let cfg = stickerConfiguration(named: pose, animojiNamed: animojiNamed),
              let viewCls = avtViewClass as? NSView.Type else {
            return snapshot(avatar: avatar, size: size, scale: 2.0)
        }
        
        // Lazy-create or reuse the offscreen snapshot AVTView
        let view: NSView
        if let existing = reusableSnapshotView {
            view = existing
            if view.frame.size != size {
                view.frame = NSRect(origin: .zero, size: size)
            }
        } else {
            view = viewCls.init(frame: NSRect(origin: .zero, size: size))
            reusableSnapshotView = view
        }
        
        setAvatar(avatar, on: view, clone: false)
        
        let transSel = NSSelectorFromString("transitionToStickerConfiguration:duration:completionHandler:")
        if view.responds(to: transSel),
           let method = class_getInstanceMethod(type(of: view), transSel) {
            typealias TransFunc = @convention(c) (AnyObject, Selector, AnyObject?, Double, (@convention(block) () -> Void)?) -> Void
            let callable = unsafeBitCast(method_getImplementation(method), to: TransFunc.self)
            callable(view, transSel, cfg, 0.0, nil)
        }
        
        let snapSel = NSSelectorFromString("snapshotWithSize:")
        guard view.responds(to: snapSel),
              let method = class_getInstanceMethod(type(of: view), snapSel) else {
            return snapshot(avatar: avatar, size: size, scale: 2.0)
        }
        
        typealias SnapFunc = @convention(c) (AnyObject, Selector, CGSize) -> AnyObject?
        let callable = unsafeBitCast(method_getImplementation(method), to: SnapFunc.self)
        if let rendered = callable(view, snapSel, size) as? NSImage {
            posedStickerCache.setObject(rendered, forKey: cacheKey)
            return rendered
        }
        
        return snapshot(avatar: avatar, size: size, scale: 2.0)
    }
}
