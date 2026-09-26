import Foundation
import AppKit

public enum AvatarSourceType: Hashable, Sendable {
    case userMemoji(uuid: String)
    case customMemoji(id: String)
    case builtinAnimoji(name: String)
    case randomMemoji(seed: UUID)
}

public struct AvatarItem: Identifiable, Hashable {
    public let id: String
    public var displayName: String
    public let sourceType: AvatarSourceType
    public var rawData: Data?
    public var cachedStickerCount: Int
    public var isBuiltin: Bool {
        if case .builtinAnimoji = sourceType { return true }
        return false
    }
    public var isUserMemoji: Bool {
        if case .userMemoji = sourceType { return true }
        return false
    }
    public var isCustomMemoji: Bool {
        if case .customMemoji = sourceType { return true }
        return false
    }
    public var isEditable: Bool {
        if case .builtinAnimoji = sourceType { return false }
        return true
    }
    
    public init(
        id: String,
        displayName: String,
        sourceType: AvatarSourceType,
        rawData: Data? = nil,
        cachedStickerCount: Int = 0
    ) {
        self.id = id
        self.displayName = displayName
        self.sourceType = sourceType
        self.rawData = rawData
        self.cachedStickerCount = cachedStickerCount
    }
}

public enum StickerCategory: String, CaseIterable, Identifiable {
    case all = "All"
    case expressions = "Expressions"
    case gestures = "Gestures"
    case reactions = "Reactions"
    case activities = "Activities"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .all: return "sparkles"
        case .expressions: return "face.smiling"
        case .gestures: return "hand.raised"
        case .reactions: return "heart.fill"
        case .activities: return "figure.run"
        }
    }
}

public struct StickerItem: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let localizedTitle: String
    public let category: StickerCategory
    public let emoji: String
    public var localFileURL: URL?
    
    public init(
        id: String,
        name: String,
        localizedTitle: String,
        category: StickerCategory = .expressions,
        emoji: String = "✨",
        localFileURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.localizedTitle = localizedTitle
        self.category = category
        self.emoji = emoji
        self.localFileURL = localFileURL
    }
}

public enum SidebarTab: String, CaseIterable, Identifiable {
    case character = "Character"
    case emote = "Emote"
    
    public var id: String { rawValue }
}

public enum SidebarViewMode: String, CaseIterable, Identifiable {
    case grid = "Grid"
    case list = "List"
    
    public var id: String { rawValue }
}

