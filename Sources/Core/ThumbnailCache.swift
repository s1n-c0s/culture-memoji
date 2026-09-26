import Foundation
import AppKit

@MainActor
public final class ThumbnailCache: ObservableObject {
    public static let shared = ThumbnailCache()
    
    private let cache = NSCache<NSString, NSImage>()
    
    private init() {
        cache.countLimit = 300
    }
    
    public func cachedImage(forKey key: String) -> NSImage? {
        return cache.object(forKey: key as NSString)
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
            
            if let url = neutralSticker?.localFileURL, let img = NSImage(contentsOf: url) {
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
    
    /// Loads or generates a sticker thumbnail for an emote
    public func getEmoteThumbnail(
        sticker: StickerItem,
        avatarObject: AnyObject?,
        isAnimoji: Bool,
        animojiName: String?
    ) async -> NSImage? {
        let key = "emote_\(sticker.id)_\(avatarObject != nil ? UInt(bitPattern: ObjectIdentifier(avatarObject!)) : 0)"
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }
        
        // 1. Check local file URL first
        if let url = sticker.localFileURL, let img = NSImage(contentsOf: url) {
            cache.setObject(img, forKey: key as NSString)
            return img
        }
        
        // 2. Dynamic generation
        if let avatar = avatarObject {
            if let img = await AvatarKitBridge.shared.generateSticker(
                avatar: avatar,
                poseName: sticker.name,
                animojiNamed: isAnimoji ? animojiName : nil,
                scale: 1.0
            ) {
                cache.setObject(img, forKey: key as NSString)
                return img
            }
        }
        
        return nil
    }
}
