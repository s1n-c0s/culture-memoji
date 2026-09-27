import Foundation
import AppKit

/// High-performance asynchronous manager for rendering and caching 3D visual preview
/// thumbnails for Memoji customization presets (hairstyles, beards, glasses, headwear, etc.).
@MainActor
public final class PresetThumbnailManager {
    public static let shared = PresetThumbnailManager()
    
    // In-memory cache for instant 0ms access
    private let memoryCache = NSCache<NSString, NSImage>()
    
    // Persistent disk cache location
    private let diskCacheURL: URL
    
    // AvatarKit runtime classes and instances
    private var builderCls: AnyClass?
    private var memojiCls: AnyClass?
    private var presetCls: AnyClass?
    private var builderInstance: AnyObject?
    private var templateAvatar: AnyObject?
    private var currentCategory: CustomizerCategory?
    private var isInitialized = false
    
    // Cached function pointers for fast invocation
    typealias SetPresetFunc = @convention(c) (AnyObject, Selector, AnyObject, Int) -> Void
    typealias ImageFunc = @convention(c) (AnyObject, Selector, CGSize, CGFloat, AnyObject?) -> AnyObject?
    private var setPresetCallable: SetPresetFunc?
    private var imageCallable: ImageFunc?
    private let setPresetSel = NSSelectorFromString("setPreset:forCategory:")
    private let imageSel = NSSelectorFromString("imageWithSize:scale:options:")
    private let setFramingModeSel = NSSelectorFromString("setFramingMode:")
    private let setAvatarSel = NSSelectorFromString("setAvatar:")
    
    // In-flight task tracking to deduplicate concurrent requests
    private var inFlightTasks: [String: Task<NSImage?, Never>] = [:]
    
    // Serial chain to serialize snapshot rendering and prevent GPU/runtime collisions
    private var renderChain: Task<Void, Never>?
    
    private init() {
        let baseDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.diskCacheURL = baseDir.appendingPathComponent("CultureMemoji/PresetThumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.diskCacheURL, withIntermediateDirectories: true)
        
        memoryCache.countLimit = 500
        setupAvatarKitIfNeeded()
    }
    
    private func setupAvatarKitIfNeeded() {
        if isInitialized { return }
        AvatarKitBridge.shared.loadFrameworksIfNeeded()
        
        self.builderCls = NSClassFromString("AVTSnapshotBuilder")
        self.memojiCls = NSClassFromString("AVTMemoji")
        self.presetCls = NSClassFromString("AVTPreset")
        
        guard let bCls = builderCls, let mCls = memojiCls else { return }
        
        let sharedSel = NSSelectorFromString("sharedInstance")
        if (bCls as AnyObject).responds(to: sharedSel),
           let builder = (bCls as AnyObject).perform(sharedSel)?.takeUnretainedValue() {
            self.builderInstance = builder
        }
        
        if let m = class_getInstanceMethod(mCls, setPresetSel) {
            self.setPresetCallable = unsafeBitCast(method_getImplementation(m), to: SetPresetFunc.self)
        }
        if let m = class_getInstanceMethod(bCls, imageSel) {
            self.imageCallable = unsafeBitCast(method_getImplementation(m), to: ImageFunc.self)
        }
        
        isInitialized = true
    }
    
    // MARK: - Public API
    
    /// Returns the cached thumbnail immediately if present in memory or disk cache (0ms).
    public func cachedThumbnail(for preset: PresetOption) -> NSImage? {
        if preset.id.lowercased() == "none" { return nil }
        let key = cacheKey(for: preset)
        
        if let mem = memoryCache.object(forKey: key as NSString) {
            return mem
        }
        if let disk = loadFromDisk(key: key) {
            memoryCache.setObject(disk, forKey: key as NSString)
            return disk
        }
        return nil
    }
    
    /// Loads or generates a 3D visual preview thumbnail asynchronously.
    public func loadThumbnail(for preset: PresetOption) async -> NSImage? {
        if preset.id.lowercased() == "none" { return nil }
        let key = cacheKey(for: preset)
        
        // 1. Check memory & disk caches (0ms instant)
        if let cached = cachedThumbnail(for: preset) {
            return cached
        }
        
        // 2. Deduplicate if already rendering
        if let existing = inFlightTasks[key] {
            return await existing.value
        }
        
        // 3. Serialize onto background render chain
        let prevChain = renderChain
        let renderTask = Task<NSImage?, Never> { @MainActor [weak self] () -> NSImage? in
            _ = await prevChain?.value
            await Task.yield()
            guard let self = self else { return nil }
            
            // Re-check after waiting in queue in case it was rendered/cached already
            if let cached = self.cachedThumbnail(for: preset) {
                self.inFlightTasks.removeValue(forKey: key)
                return cached
            }
            
            let img = self.renderThumbnail(preset: preset)
            if let img = img {
                self.memoryCache.setObject(img, forKey: key as NSString)
                self.saveToDisk(image: img, key: key)
            }
            self.inFlightTasks.removeValue(forKey: key)
            return img
        }
        
        inFlightTasks[key] = renderTask
        renderChain = Task {
            _ = await renderTask.value
        }
        return await renderTask.value
    }
    
    // MARK: - Rendering
    
    private func renderThumbnail(preset: PresetOption) -> NSImage? {
        setupAvatarKitIfNeeded()
        guard let builder = builderInstance,
              let setPres = setPresetCallable,
              let imgCall = imageCallable else { return nil }
        
        prepareTemplate(for: preset.category)
        guard let template = templateAvatar else { return nil }
        
        // Apply preset
        setPres(template, setPresetSel, preset.rawPreset, preset.category.rawValue)
        
        // Configure camera framing for this category
        let renSel = NSSelectorFromString("renderer")
        if (builder as AnyObject).responds(to: renSel),
           let ren = (builder as AnyObject).perform(renSel)?.takeUnretainedValue() {
            let camera = cameraForCategory(preset.category)
            if (ren as AnyObject).responds(to: setFramingModeSel) {
                _ = (ren as AnyObject).perform(setFramingModeSel, with: camera as NSString)
            }
        }
        
        // Render 80x80 snapshot (scale 2.0 = 160x160 Retina)
        let img = imgCall(builder, imageSel, CGSize(width: 80, height: 80), 2.0, nil) as? NSImage
        return img
    }
    
    private func prepareTemplate(for category: CustomizerCategory) {
        if templateAvatar == nil || currentCategory != category {
            currentCategory = category
            templateAvatar = AvatarKitBridge.shared.loadNeutralMemoji()
            if let builder = builderInstance, let template = templateAvatar {
                _ = (builder as AnyObject).perform(setAvatarSel, with: template)
            }
        }
    }
    
    private func cameraForCategory(_ category: CustomizerCategory) -> String {
        switch category {
        case .hair: return "cameraHairstyle"
        case .facialHair: return "cameraChin"
        case .headwear: return "cameraHeadwear"
        case .eyewear, .eyebrows, .eyes: return "cameraEyes"
        case .nose: return "cameraNose"
        case .mouth: return "cameraMouth"
        case .ears, .audio: return "cameraEars"
        case .skin: return "cameraFace"
        case .outfit: return "cameraDefault"
        }
    }
    
    private func cacheKey(for preset: PresetOption) -> String {
        "\(preset.category.rawValue)_\(preset.id)"
    }
    
    // MARK: - Disk Persistence
    
    private func loadFromDisk(key: String) -> NSImage? {
        let fileURL = diskCacheURL.appendingPathComponent("\(key).png")
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let img = NSImage(data: data) else { return nil }
        return img
    }
    
    private func saveToDisk(image: NSImage, key: String) {
        Task.detached(priority: .utility) { [diskCacheURL = self.diskCacheURL] in
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { return }
            let fileURL = diskCacheURL.appendingPathComponent("\(key).png")
            try? png.write(to: fileURL)
        }
    }
}
