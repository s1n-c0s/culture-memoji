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
    private var avtStickerGeneratorClass: AnyClass?
    private var avtStickerGeneratorOptionsClass: AnyClass?
    
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
            avtStickerGeneratorClass = NSClassFromString("AVTStickerGenerator")
            avtStickerGeneratorOptionsClass = NSClassFromString("AVTStickerGeneratorOptions")
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
        
        // Set background to clear so it blends seamlessly with the stage
        let bgSel = NSSelectorFromString("setBackgroundColor:")
        if view.responds(to: bgSel) {
            _ = (view as AnyObject).perform(bgSel, with: NSColor.clear)
        }
        
        // Stabilize camera controller orbit target and up-vector
        stabilizeCameraController(on: view)
        
        return view
    }
    
    /// Stabilizes the camera controller by halting inertia, clearing roll tilt,
    /// and disabling hit-test target snapping so mouse clicks on face/mesh don't move orbit center.
    public func stabilizeCameraController(on view: NSView) {
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
        
        let bgSel = NSSelectorFromString("setBackgroundColor:")
        if view.responds(to: bgSel) {
            _ = (view as AnyObject).perform(bgSel, with: NSColor.white)
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
    private let stickerConfigCache = NSCache<NSString, AnyObject>()
    
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
    /// Cached in memory for instant O(1) lookups on future pose switches.
    public func stickerConfiguration(named stickerName: String, animojiNamed: String? = nil) -> AnyObject? {
        let cacheKey = "\(animojiNamed ?? "memoji")_\(stickerName)" as NSString
        if let cached = stickerConfigCache.object(forKey: cacheKey) {
            return cached
        }
        
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
                stickerConfigCache.setObject(validCfg, forKey: cacheKey)
                return validCfg
            }
        }
        
        return nil // Not found in any known pack
    }
    
    /// Pre-warms sticker configurations in background so switching poses is completely lag-free
    public func prewarmStickerConfigurations(forAnimojiNamed name: String?, stickerNames: [String]) {
        Task(priority: .utility) { [weak self] in
            for stickerName in stickerNames.prefix(35) {
                if Task.isCancelled { break }
                _ = self?.stickerConfiguration(named: stickerName, animojiNamed: name)
                await Task.yield()
            }
        }
    }
    
    /// Smoothly transitions the 3D AVTView to a given sticker pose/expression,
    /// ensuring the camera rotation axis remains stable and upright.
    public func applyStickerPose(named stickerName: String, to view: NSView, animojiNamed: String? = nil, duration: Double = 0.18) {
        guard let cfg = stickerConfiguration(named: stickerName, animojiNamed: animojiNamed) else {
            resetToNeutralPose(on: view, duration: duration)
            return
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
    public func resetToNeutralPose(on view: NSView, duration: Double = 0.18) {
        stabilizeCameraController(on: view)
        
        let transSel = NSSelectorFromString("transitionToStickerConfiguration:duration:completionHandler:")
        guard view.responds(to: transSel),
              let method = class_getInstanceMethod(type(of: view), transSel) else { return }
        
        typealias TransFunc = @convention(c) (AnyObject, Selector, AnyObject?, Double, (@convention(block) () -> Void)?) -> Void
        let callable = unsafeBitCast(method_getImplementation(method), to: TransFunc.self)
        callable(view, transSel, nil, duration, { [weak self] in
            self?.stabilizeCameraController(on: view)
        })
    }
    
    /// Smoothly executes scene/node property changes inside a VFXTransaction or SCNTransaction
    private func perform3DTransaction(duration: Double, actions: () -> Void) {
        let transCls: AnyObject.Type? = NSClassFromString("VFXTransaction") ?? NSClassFromString("SCNTransaction")
        if let cls = transCls {
            let beginSel = NSSelectorFromString("begin")
            let durSel = NSSelectorFromString("setAnimationDuration:")
            let commitSel = NSSelectorFromString("commit")
            
            typealias VoidFunc = @convention(c) (AnyObject, Selector) -> Void
            typealias DurFunc = @convention(c) (AnyObject, Selector, Double) -> Void
            
            if let mBegin = class_getClassMethod(cls, beginSel),
               let mDur = class_getClassMethod(cls, durSel),
               let mCommit = class_getClassMethod(cls, commitSel) {
                unsafeBitCast(method_getImplementation(mBegin), to: VoidFunc.self)(cls as AnyObject, beginSel)
                unsafeBitCast(method_getImplementation(mDur), to: DurFunc.self)(cls as AnyObject, durSel, duration)
                actions()
                unsafeBitCast(method_getImplementation(mCommit), to: VoidFunc.self)(cls as AnyObject, commitSel)
                return
            }
        }
        actions()
    }
    
    /// Centers the camera node, target, FOV, and stabilizes orbit controls back to canonical front-view
    public func applyCanonicalCameraFraming(to view: NSView, animated: Bool = true, duration: Double = 0.25) {
        let updateAction = {
            let camCtrlSel = NSSelectorFromString("defaultCameraController")
            if view.responds(to: camCtrlSel),
               let camCtrl = (view as AnyObject).perform(camCtrlSel)?.takeUnretainedValue() {
                (camCtrl as AnyObject).setValue(false, forKey: "automaticTarget")
                (camCtrl as AnyObject).setValue(false, forKey: "isTargetFromHitTest")
                _ = (camCtrl as AnyObject).perform(NSSelectorFromString("stopInertia"))
                _ = (camCtrl as AnyObject).perform(NSSelectorFromString("clearRoll"))
                _ = (camCtrl as AnyObject).perform(NSSelectorFromString("_resetOrientationState"))
                
                let targetSel = NSSelectorFromString("setTarget:")
                if let mTarget = class_getInstanceMethod(type(of: camCtrl), targetSel) {
                    typealias VecFunc = @convention(c) (AnyObject, Selector, SIMD3<Float>) -> Void
                    unsafeBitCast(method_getImplementation(mTarget), to: VecFunc.self)(camCtrl, targetSel, SIMD3<Float>(0, 0, 0))
                }
            }
            
            let povSel = NSSelectorFromString("pointOfView")
            if let pov = (view as AnyObject).perform(povSel)?.takeUnretainedValue() {
                typealias VecFunc = @convention(c) (AnyObject, Selector, SIMD3<Float>) -> Void
                typealias Rot4Func = @convention(c) (AnyObject, Selector, SIMD4<Float>) -> Void
                
                let posSel = NSSelectorFromString("setPosition:")
                if let mPos = class_getInstanceMethod(type(of: pov), posSel) {
                    unsafeBitCast(method_getImplementation(mPos), to: VecFunc.self)(pov, posSel, SIMD3<Float>(0, 15, 59.59))
                }
                
                let rotSel = NSSelectorFromString("setRotation:")
                if let mRot = class_getInstanceMethod(type(of: pov), rotSel) {
                    unsafeBitCast(method_getImplementation(mRot), to: Rot4Func.self)(pov, rotSel, SIMD4<Float>(-1.0, 0.0, 0.0, 0.06951647))
                }
                
                let camSel = NSSelectorFromString("camera")
                if let cam = (pov as AnyObject).perform(camSel)?.takeUnretainedValue() {
                    (cam as AnyObject).setValue(46.0, forKey: "fieldOfView")
                }
            }
            
            // Re-stabilize orientation state against the newly applied camera transform
            if view.responds(to: camCtrlSel),
               let camCtrl = (view as AnyObject).perform(camCtrlSel)?.takeUnretainedValue() {
                _ = (camCtrl as AnyObject).perform(NSSelectorFromString("stopInertia"))
                _ = (camCtrl as AnyObject).perform(NSSelectorFromString("clearRoll"))
                _ = (camCtrl as AnyObject).perform(NSSelectorFromString("_resetOrientationState"))
            }
        }
        
        if animated {
            perform3DTransaction(duration: duration) {
                updateAction()
            }
        } else {
            updateAction()
        }
    }
    
    /// Explicitly resets the camera framing, position, rotation, FOV, and orbit target back to canonical center,
    /// and smoothly transitions any active emote/sticker expression back to neutral pose.
    public func resetCameraFraming(on view: NSView, duration: Double = 0.25) {
        // 1. Immediately apply camera centering for smooth visual feedback from current position
        applyCanonicalCameraFraming(to: view, animated: true, duration: duration)
        
        // 2. Transition sticker pose/accessories back to neutral
        let transSel = NSSelectorFromString("transitionToStickerConfiguration:duration:completionHandler:")
        if view.responds(to: transSel),
           let method = class_getInstanceMethod(type(of: view), transSel) {
            typealias TransFunc = @convention(c) (AnyObject, Selector, AnyObject?, Double, (@convention(block) () -> Void)?) -> Void
            let callable = unsafeBitCast(method_getImplementation(method), to: TransFunc.self)
            callable(view, transSel, nil, duration, { [weak self] in
                // 3. Once sticker transition completes and original pointOfView is restored,
                // re-apply canonical framing to the restored camera node
                self?.applyCanonicalCameraFraming(to: view, animated: false)
            })
        }
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
    
    // Active sticker generator and cache for fast, high-fidelity posed sticker rendering
    private var currentGenerator: (avatarId: ObjectIdentifier, generator: AnyObject)?
    private let posedStickerCache = NSCache<NSString, NSImage>()
    
    /// Clears cached posed sticker images (e.g. after customizing or randomizing an avatar)
    public func clearPosedStickerCache() {
        posedStickerCache.removeAllObjects()
        currentGenerator = nil
    }
    
    /// Retrieves or initializes a native AVTStickerGenerator for the given avatar
    private func stickerGenerator(for avatar: AnyObject) -> AnyObject? {
        let avatarId = ObjectIdentifier(avatar)
        if let current = currentGenerator, current.avatarId == avatarId {
            return current.generator
        }
        
        guard let genCls = avtStickerGeneratorClass else { return nil }
        let allocSel = NSSelectorFromString("alloc")
        guard (genCls as AnyObject).responds(to: allocSel),
              let uninit = (genCls as AnyObject).perform(allocSel)?.takeUnretainedValue() else { return nil }
        
        let genAvatar = cloneAvatar(avatar) ?? avatar
        let initSel = NSSelectorFromString("initWithAvatar:")
        guard let initMethod = class_getInstanceMethod(genCls, initSel) else { return nil }
        typealias InitFunc = @convention(c) (AnyObject, Selector, AnyObject) -> AnyObject?
        guard let gen = unsafeBitCast(method_getImplementation(initMethod), to: InitFunc.self)(uninit, initSel, genAvatar) else {
            return nil
        }
        
        currentGenerator = (avatarId, gen)
        return gen
    }
    
    // Serial task chain to serialize AVTStickerGenerator operations and prevent GPU context collisions
    private var stickerRenderChain: Task<NSImage?, Never>?

    /// Immediately cancels any in-flight background sticker render queue (e.g. when user switches character)
    public func cancelPendingStickerRenders() {
        stickerRenderChain?.cancel()
        stickerRenderChain = nil
    }

    /// Asynchronously generates a high-resolution posed sticker for the given avatar model.
    /// Uses Apple's native AVTStickerGenerator so expressions, morphers, 3D props (birds, stars, clouds),
    /// and tailored camera framing are rendered with 100% fidelity matching the current model.
    public func generateSticker(
        avatar: AnyObject,
        poseName: String?,
        animojiNamed: String? = nil,
        scale: CGFloat = 1.0
    ) async -> NSImage? {
        guard let pose = poseName, !pose.isEmpty, pose != "neutral" else {
            return snapshot(avatar: avatar, size: CGSize(width: 320, height: 320), scale: scale)
        }
        
        let cacheKey = "\(UInt(bitPattern: ObjectIdentifier(avatar)))_\(pose)_\(animojiNamed ?? "memoji")_\(Int(scale * 100))" as NSString
        if let cached = posedStickerCache.object(forKey: cacheKey) {
            return cached
        }
        
        guard let cfg = stickerConfiguration(named: pose, animojiNamed: animojiNamed) else {
            return snapshot(avatar: avatar, size: CGSize(width: 320, height: 320), scale: scale)
        }
        
        // Serialize execution with utility priority and cancellation support
        let prev = stickerRenderChain
        let currentTask = Task(priority: .utility) { [weak self] () -> NSImage? in
            _ = await prev?.value
            if Task.isCancelled { return nil }
            await Task.yield()
            guard let self = self else { return nil }
            return await self.executeGenerateSticker(
                avatar: avatar,
                cfg: cfg,
                cacheKey: cacheKey,
                scale: scale
            )
        }
        stickerRenderChain = currentTask
        return await currentTask.value
    }
    
    private func executeGenerateSticker(
        avatar: AnyObject,
        cfg: AnyObject,
        cacheKey: NSString,
        scale: CGFloat
    ) async -> NSImage? {
        if Task.isCancelled { return nil }
        if let cached = posedStickerCache.object(forKey: cacheKey) {
            return cached
        }
        
        if let gen = stickerGenerator(for: avatar) {
            let genCls: AnyClass = type(of: gen)
            nonisolated(unsafe) let unsafeGen = gen
            nonisolated(unsafe) let unsafeCfg = cfg
            
            // 1. High-DPI options with scale factor
            if let optCls = avtStickerGeneratorOptionsClass {
                let defaultOptSel = NSSelectorFromString("defaultOptions")
                if let options = (optCls as AnyObject).perform(defaultOptSel)?.takeUnretainedValue() {
                    (options as AnyObject).setValue(scale, forKey: "scaleFactor")
                    (options as AnyObject).setValue(scale, forKey: "sizeMultiplier")
                    nonisolated(unsafe) let unsafeOptions = options
                    
                    let optGenSel = NSSelectorFromString("stickerImageWithConfiguration:options:completionHandler:")
                    if gen.responds(to: optGenSel),
                       let method = class_getInstanceMethod(genCls, optGenSel) {
                        typealias OptGenFunc = @convention(c) (AnyObject, Selector, AnyObject, AnyObject, (@convention(block) (AnyObject?) -> Void)?) -> Void
                        let callable = unsafeBitCast(method_getImplementation(method), to: OptGenFunc.self)
                        
                        let img: NSImage? = await withCheckedContinuation { continuation in
                            callable(unsafeGen, optGenSel, unsafeCfg, unsafeOptions, { result in
                                continuation.resume(returning: result as? NSImage)
                            })
                        }
                        if let img = img {
                            posedStickerCache.setObject(img, forKey: cacheKey)
                            return img
                        }
                    }
                }
            }
            
            // 2. Standard sticker generator
            let genSel = NSSelectorFromString("stickerImageWithConfiguration:completionHandler:")
            if gen.responds(to: genSel),
               let method = class_getInstanceMethod(genCls, genSel) {
                typealias GenFunc = @convention(c) (AnyObject, Selector, AnyObject, (@convention(block) (AnyObject?) -> Void)?) -> Void
                let callable = unsafeBitCast(method_getImplementation(method), to: GenFunc.self)
                
                let img: NSImage? = await withCheckedContinuation { continuation in
                    callable(unsafeGen, genSel, unsafeCfg, { result in
                        continuation.resume(returning: result as? NSImage)
                    })
                }
                if let img = img {
                    posedStickerCache.setObject(img, forKey: cacheKey)
                    return img
                }
            }
        }
        
        return snapshot(avatar: avatar, size: CGSize(width: 320, height: 320), scale: scale)
    }
    
    /// Synchronously snapshots an avatar in a specific sticker pose.
    /// Checks memory cache first, or generates via AVTStickerGenerator.
    public func snapshot(
        avatar: AnyObject,
        poseName: String?,
        animojiNamed: String? = nil,
        size: CGSize = CGSize(width: 512, height: 512)
    ) -> NSImage? {
        guard let pose = poseName, !pose.isEmpty, pose != "neutral" else {
            // Render frontal neutral snapshot via offscreen AVTView with canonical stage framing
            if let offscreenView = createAVTView(frame: NSRect(origin: .zero, size: size), avatar: avatar) {
                applyCanonicalCameraFraming(to: offscreenView, animated: false)
                if let snap = snapshot(view: offscreenView, size: size) {
                    return snap
                }
            }
            return snapshot(avatar: avatar, size: size, scale: 2.0)
        }
        
        let cacheKey = "\(UInt(bitPattern: ObjectIdentifier(avatar)))_\(pose)_\(animojiNamed ?? "memoji")_\(Int(size.width))" as NSString
        if let cached = posedStickerCache.object(forKey: cacheKey) {
            return cached
        }
        
        // Also check scale 200 cache key from generateSticker
        let genKey = "\(UInt(bitPattern: ObjectIdentifier(avatar)))_\(pose)_\(animojiNamed ?? "memoji")_200" as NSString
        if let cached = posedStickerCache.object(forKey: genKey) {
            return cached
        }
        
        guard let cfg = stickerConfiguration(named: pose, animojiNamed: animojiNamed) else {
            return snapshot(avatar: avatar, size: size, scale: 2.0)
        }
        
        if let gen = stickerGenerator(for: avatar) {
            let genCls: AnyClass = type(of: gen)
            let genSel = NSSelectorFromString("stickerImageWithConfiguration:completionHandler:")
            if gen.responds(to: genSel),
               let method = class_getInstanceMethod(genCls, genSel) {
                typealias GenFunc = @convention(c) (AnyObject, Selector, AnyObject, (@convention(block) (AnyObject?) -> Void)?) -> Void
                let callable = unsafeBitCast(method_getImplementation(method), to: GenFunc.self)
                
                var rendered: NSImage?
                var isDone = false
                callable(gen, genSel, cfg, { result in
                    rendered = result as? NSImage
                    isDone = true
                })
                
                let start = Date()
                while !isDone && Date().timeIntervalSince(start) < 0.6 {
                    RunLoop.current.run(until: Date().addingTimeInterval(0.01))
                }
                
                if let img = rendered {
                    posedStickerCache.setObject(img, forKey: cacheKey)
                    return img
                }
            }
        }
        
        return snapshot(avatar: avatar, size: size, scale: 2.0)
    }
}
