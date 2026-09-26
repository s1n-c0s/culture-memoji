import Foundation
import AppKit

@MainActor
public final class ThumbnailCache: ObservableObject {
    public static let shared = ThumbnailCache()
    
    private let cache = NSCache<NSString, NSImage>()
    
    private let diskCacheDirectory: URL = {
        let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = cachesURL.appendingPathComponent("CultureMemoji/Stickers")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    
    private init() {
        cache.countLimit = 600
    }
    
    public func cachedImage(forKey key: String) -> NSImage? {
        return cache.object(forKey: key as NSString)
    }
    
    /// Synchronously returns an in-memory cached thumbnail for an emote (instant frame-0 render)
    public func cachedEmoteThumbnail(for sticker: StickerItem) -> NSImage? {
        return cache.object(forKey: "emote_\(sticker.id)" as NSString)
    }
    
    public func setImage(_ image: NSImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
    
    public func clear() {
        cache.removeAllObjects()
    }
    
    /// Loads or generates a thumbnail for an avatar
    public func getThumbnail(for item: AvatarItem, avatarObject: AnyObject?) async -> NSImage? {
        let key = "avatar_\(item.id)"
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }
        
        // 1. Built-in Animoji fast thumbnail
        if case .builtinAnimoji(let name) = item.sourceType {
            if let thumb = AvatarKitBridge.shared.animojiThumbnail(named: name) {
                cache.setObject(thumb, forKey: key as NSString)
                return thumb
            }
        }
        
        // 2. User Memoji cached disk sticker
        if case .userMemoji(let uuid) = item.sourceType {
            let diskStickers = AvatarDatabaseReader.shared.findCachedStickers(forUUID: uuid)
            // Look for neutral or front sticker first
            let neutralSticker = diskStickers.first(where: {
                $0.name.lowercased().contains("neutral") ||
                $0.name.lowercased().contains("front") ||
                $0.name.lowercased().contains("happy") ||
                $0.name.lowercased().contains("smile")
            }) ?? diskStickers.first
            
            if let url = neutralSticker?.localFileURL, let img = await loadDiskImage(at: url) {
                cache.setObject(img, forKey: key as NSString)
                return img
            }
        }
        
        // 3. Fallback to 3D snapshot
        if let avatar = avatarObject {
            let isAnimoji: Bool
            let animojiName: String?
            if case .builtinAnimoji(let name) = item.sourceType {
                isAnimoji = true
                animojiName = name
            } else {
                isAnimoji = false
                animojiName = nil
            }
            
            if let snap = AvatarKitBridge.shared.snapshot(
                avatar: avatar,
                poseName: nil,
                animojiNamed: isAnimoji ? animojiName : nil,
                size: CGSize(width: 256, height: 256)
            ) {
                cache.setObject(snap, forKey: key as NSString)
                return snap
            }
        }
        
        return nil
    }
    
    /// Loads or generates a sticker thumbnail for an emote with persistent disk caching
    public func getEmoteThumbnail(
        sticker: StickerItem,
        avatarObject: AnyObject?,
        isAnimoji: Bool,
        animojiName: String?
    ) async -> NSImage? {
        let key = "emote_\(sticker.id)"
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }
        
        // 1. Check local file URL first (Apple's disk stickers)
        if let url = sticker.localFileURL {
            if let img = await loadDiskImage(at: url) {
                cache.setObject(img, forKey: key as NSString)
                return img
            }
        }
        
        // 2. Check CultureMemoji persistent disk cache
        let diskURL = diskCacheDirectory.appendingPathComponent("\(sticker.id).png")
        if FileManager.default.fileExists(atPath: diskURL.path) {
            if let img = await loadDiskImage(at: diskURL) {
                cache.setObject(img, forKey: key as NSString)
                return img
            }
        }
        
        // 3. Dynamic generation via serialized 3D sticker generator
        if let avatar = avatarObject {
            if let img = await AvatarKitBridge.shared.generateSticker(
                avatar: avatar,
                poseName: sticker.name,
                animojiNamed: isAnimoji ? animojiName : nil,
                scale: 1.0
            ) {
                cache.setObject(img, forKey: key as NSString)
                saveDiskImage(img, to: diskURL)
                return img
            }
        }
        
        return nil
    }
    
    /// Pre-warms the first batch of emote thumbnails in the background
    public func prewarmEmoteThumbnails(
        stickers: [StickerItem],
        avatarObject: AnyObject?,
        isAnimoji: Bool,
        animojiName: String?
    ) {
        Task {
            for sticker in stickers.prefix(16) {
                _ = await getEmoteThumbnail(
                    sticker: sticker,
                    avatarObject: avatarObject,
                    isAnimoji: isAnimoji,
                    animojiName: animojiName
                )
            }
        }
    }
    
    // MARK: - Non-blocking I/O Helpers
    
    private func loadDiskImage(at url: URL) async -> NSImage? {
        await Task.detached(priority: .userInitiated) {
            return NSImage(contentsOf: url)
        }.value
    }
    
    private func saveDiskImage(_ image: NSImage, to url: URL) {
        Task.detached(priority: .utility) {
            let parent = url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { return }
            try? png.write(to: url)
        }
    }
}
