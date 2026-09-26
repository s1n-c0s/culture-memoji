import Foundation
import Combine

/// Manages custom user ordering of characters/models with persistent storage in UserDefaults.
@MainActor
public final class CharacterOrderManager: ObservableObject {
    public static let shared = CharacterOrderManager()
    
    @Published public private(set) var customOrder: [String] = []
    
    private let storageKey = "CultureMemoji_CharacterCustomOrder"
    
    private init() {
        if let saved = UserDefaults.standard.array(forKey: storageKey) as? [String] {
            customOrder = saved
        }
    }
    
    public var hasCustomOrder: Bool {
        !customOrder.isEmpty
    }
    
    /// Applies custom ordering to the provided avatar items.
    /// If no custom order is saved, it sorts favorites first followed by original order.
    public func applyOrder(to items: [AvatarItem], favorites: FavoritesManager) -> [AvatarItem] {
        guard !customOrder.isEmpty else {
            var defaultSorted = items
            defaultSorted.sort { a, b in
                let aFav = favorites.isCharacterFavorite(a.id)
                let bFav = favorites.isCharacterFavorite(b.id)
                if aFav != bFav { return aFav && !bFav }
                return false
            }
            return defaultSorted
        }
        
        var orderMap: [String: Int] = [:]
        for (index, id) in customOrder.enumerated() {
            orderMap[id] = index
        }
        
        var ordered: [AvatarItem] = []
        var unplaced: [AvatarItem] = []
        
        for item in items {
            if orderMap[item.id] != nil {
                ordered.append(item)
            } else {
                unplaced.append(item)
            }
        }
        
        ordered.sort { a, b in
            let idxA = orderMap[a.id] ?? 0
            let idxB = orderMap[b.id] ?? 0
            return idxA < idxB
        }
        
        // Unplaced items (e.g., newly loaded system animojis or custom avatars)
        unplaced.sort { a, b in
            let aFav = favorites.isCharacterFavorite(a.id)
            let bFav = favorites.isCharacterFavorite(b.id)
            if aFav != bFav { return aFav && !bFav }
            return false
        }
        
        return ordered + unplaced
    }
    
    /// Moves a character by source ID to target ID's position among current items
    public func move(sourceId: String, targetId: String, currentItems: [AvatarItem]? = nil) {
        guard sourceId != targetId else { return }
        
        var currentIds = !customOrder.isEmpty ? customOrder : (currentItems?.map(\.id) ?? [])
        if !currentIds.contains(sourceId) {
            currentIds.append(sourceId)
        }
        if !currentIds.contains(targetId) {
            currentIds.append(targetId)
        }
        
        guard let sourceIndex = currentIds.firstIndex(of: sourceId),
              let targetIndex = currentIds.firstIndex(of: targetId) else {
            return
        }
        
        currentIds.remove(at: sourceIndex)
        currentIds.insert(sourceId, at: targetIndex)
        
        self.customOrder = currentIds
        UserDefaults.standard.set(currentIds, forKey: storageKey)
    }
    
    /// Moves a character to the very top (index 0)
    public func moveToTop(id: String, currentItems: [AvatarItem]) {
        var currentIds = currentItems.map(\.id)
        guard let sourceIndex = currentIds.firstIndex(of: id), sourceIndex > 0 else { return }
        
        currentIds.remove(at: sourceIndex)
        currentIds.insert(id, at: 0)
        
        self.customOrder = currentIds
        UserDefaults.standard.set(currentIds, forKey: storageKey)
    }
    
    /// Moves a character to the very bottom
    public func moveToBottom(id: String, currentItems: [AvatarItem]) {
        var currentIds = currentItems.map(\.id)
        guard let sourceIndex = currentIds.firstIndex(of: id), sourceIndex < currentIds.count - 1 else { return }
        
        currentIds.remove(at: sourceIndex)
        currentIds.append(id)
        
        self.customOrder = currentIds
        UserDefaults.standard.set(currentIds, forKey: storageKey)
    }
    
    /// Moves a character earlier (-1) or later (+1)
    public func moveByOffset(id: String, offset: Int, currentItems: [AvatarItem]) {
        var currentIds = currentItems.map(\.id)
        guard let idx = currentIds.firstIndex(of: id) else { return }
        let newIdx = idx + offset
        guard newIdx >= 0 && newIdx < currentIds.count else { return }
        
        currentIds.remove(at: idx)
        currentIds.insert(id, at: newIdx)
        
        self.customOrder = currentIds
        UserDefaults.standard.set(currentIds, forKey: storageKey)
    }
    
    /// Moves all selected character IDs to the top, preserving relative order
    public func moveSelectedToTop(ids: Set<String>, currentItems: [AvatarItem]) {
        guard !ids.isEmpty else { return }
        let selectedList = currentItems.filter { ids.contains($0.id) }.map(\.id)
        let remainingList = currentItems.filter { !ids.contains($0.id) }.map(\.id)
        
        let newOrder = selectedList + remainingList
        self.customOrder = newOrder
        UserDefaults.standard.set(newOrder, forKey: storageKey)
    }
    
    /// Inserts a new character ID at the top (used when creating or duplicating an avatar)
    public func insertAtTop(id: String) {
        var current = customOrder
        current.removeAll { $0 == id }
        current.insert(id, at: 0)
        self.customOrder = current
        UserDefaults.standard.set(current, forKey: storageKey)
    }
    
    /// Removes a character ID from custom order (used when deleting an avatar)
    public func remove(id: String) {
        if customOrder.contains(id) {
            customOrder.removeAll { $0 == id }
            UserDefaults.standard.set(customOrder, forKey: storageKey)
        }
    }
    
    /// Resets custom order back to system default
    public func resetOrder() {
        self.customOrder = []
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
