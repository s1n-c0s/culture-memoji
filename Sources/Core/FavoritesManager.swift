import Foundation
import Combine

/// Manages favorites for characters and emotes with persistent storage
@MainActor
public final class FavoritesManager: ObservableObject {
    public static let shared = FavoritesManager()
    
    @Published public private(set) var favoriteCharacters: Set<String> = []
    @Published public private(set) var favoriteEmotes: Set<String> = []
    
    private let charKey = "CultureMemoji_FavoriteCharacters"
    private let emoteKey = "CultureMemoji_FavoriteEmotes"
    
    private init() {
        if let savedChars = UserDefaults.standard.array(forKey: charKey) as? [String] {
            favoriteCharacters = Set(savedChars)
        }
        if let savedEmotes = UserDefaults.standard.array(forKey: emoteKey) as? [String] {
            favoriteEmotes = Set(savedEmotes)
        }
    }
    
    public func isCharacterFavorite(_ id: String) -> Bool {
        favoriteCharacters.contains(id)
    }
    
    public func toggleCharacterFavorite(_ id: String) {
        if favoriteCharacters.contains(id) {
            favoriteCharacters.remove(id)
        } else {
            favoriteCharacters.insert(id)
        }
        UserDefaults.standard.set(Array(favoriteCharacters), forKey: charKey)
    }
    
    public func isEmoteFavorite(_ name: String) -> Bool {
        favoriteEmotes.contains(name)
    }
    
    public func toggleEmoteFavorite(_ name: String) {
        if favoriteEmotes.contains(name) {
            favoriteEmotes.remove(name)
        } else {
            favoriteEmotes.insert(name)
        }
        UserDefaults.standard.set(Array(favoriteEmotes), forKey: emoteKey)
    }
}
