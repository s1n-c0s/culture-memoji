import SwiftUI
import AppKit

public struct SidebarView: View {
    @Binding public var selectedAvatarId: String?
    @Binding public var activePoseName: String?
    @Binding public var currentTab: SidebarTab
    @Binding public var viewMode: SidebarViewMode
    
    public let userMemojis: [AvatarItem]
    public let customMemojis: [AvatarItem]
    public let builtinAnimojis: [AvatarItem]
    public let randomMemojis: [AvatarItem]
    public let avatarObjects: [String: AnyObject]
    public let stickersForSelectedAvatar: [StickerItem]
    
    public let onAddNewMemoji: () -> Void
    public let onEditMemoji: (AvatarItem) -> Void
    public let onDuplicateMemoji: ((AvatarItem) -> Void)?
    public let onDeleteCustomMemoji: (AvatarItem) -> Void
    public let onRenameMemoji: ((AvatarItem) -> Void)?
    public let onRefreshRequested: () -> Void
    public let onCopySticker: ((StickerItem) -> Void)?
    
    @ObservedObject private var favorites = FavoritesManager.shared
    @State private var searchText: String = ""
    @State private var isSearchActive: Bool = false
    @State private var selectedEmoteCategory: StickerCategory = .all
    
    public init(
        selectedAvatarId: Binding<String?>,
        activePoseName: Binding<String?>,
        currentTab: Binding<SidebarTab>,
        viewMode: Binding<SidebarViewMode>,
        userMemojis: [AvatarItem],
        customMemojis: [AvatarItem],
        builtinAnimojis: [AvatarItem],
        randomMemojis: [AvatarItem],
        avatarObjects: [String: AnyObject],
        stickersForSelectedAvatar: [StickerItem],
        onAddNewMemoji: @escaping () -> Void,
        onEditMemoji: @escaping (AvatarItem) -> Void,
        onDuplicateMemoji: ((AvatarItem) -> Void)? = nil,
        onDeleteCustomMemoji: @escaping (AvatarItem) -> Void,
        onRenameMemoji: ((AvatarItem) -> Void)? = nil,
        onRefreshRequested: @escaping () -> Void,
        onCopySticker: ((StickerItem) -> Void)? = nil
    ) {
        self._selectedAvatarId = selectedAvatarId
        self._activePoseName = activePoseName
        self._currentTab = currentTab
        self._viewMode = viewMode
        self.userMemojis = userMemojis
        self.customMemojis = customMemojis
        self.builtinAnimojis = builtinAnimojis
        self.randomMemojis = randomMemojis
        self.avatarObjects = avatarObjects
        self.stickersForSelectedAvatar = stickersForSelectedAvatar
        self.onAddNewMemoji = onAddNewMemoji
        self.onEditMemoji = onEditMemoji
        self.onDuplicateMemoji = onDuplicateMemoji
        self.onDeleteCustomMemoji = onDeleteCustomMemoji
        self.onRenameMemoji = onRenameMemoji
        self.onRefreshRequested = onRefreshRequested
        self.onCopySticker = onCopySticker
    }
    
    private var allCharacters: [AvatarItem] {
        var items = customMemojis + userMemojis + randomMemojis + builtinAnimojis
        // Sort: favorites first, then preserve ordering
        items.sort { a, b in
            let aFav = favorites.isCharacterFavorite(a.id)
            let bFav = favorites.isCharacterFavorite(b.id)
            if aFav != bFav { return aFav && !bFav }
            return false
        }
        return items
    }
    
    private var filteredCharacters: [AvatarItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return allCharacters }
        return allCharacters.filter {
            $0.displayName.localizedCaseInsensitiveContains(q) ||
            $0.id.localizedCaseInsensitiveContains(q)
        }
    }
    
    private var filteredEmotes: [StickerItem] {
        var list = stickersForSelectedAvatar
        if selectedEmoteCategory != .all {
            list = list.filter { $0.category == selectedEmoteCategory }
        }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(q) ||
                $0.localizedTitle.localizedCaseInsensitiveContains(q) ||
                $0.emoji.contains(q)
            }
        }
        // Favorites first
        list.sort { a, b in
            let aFav = favorites.isEmoteFavorite(a.name)
            let bFav = favorites.isEmoteFavorite(b.name)
            if aFav != bFav { return aFav && !bFav }
            return false
        }
        return list
    }
    
    private var selectedAvatarItem: AvatarItem? {
        guard let id = selectedAvatarId else { return allCharacters.first }
        return allCharacters.first(where: { $0.id == id })
    }
    
    private var isAnimoji: Bool {
        if case .builtinAnimoji = selectedAvatarItem?.sourceType { return true }
        return false
    }
    
    private var animojiName: String? {
        if case .builtinAnimoji(let name) = selectedAvatarItem?.sourceType { return name }
        return nil
    }
    
    private let gridColumns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]
    
    public var body: some View {
        VStack(spacing: 0) {
            // Top Section (Tabs, Action Bar, Search)
            sidebarHeader
                .padding(.horizontal, 20)
                .padding(.top, 44)
                .padding(.bottom, 12)
            
            // Content Area (Characters or Emotes Grid/List)
            ScrollView {
                if currentTab == .character {
                    characterContent
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                        .padding(.bottom, 24)
                } else {
                    emoteContent
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                        .padding(.bottom, 24)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Bottom Section (Centered 2x2 Grid and 2-Row List View Mode Switcher)
            sidebarFooter
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .background(AppTheme.sidebarBackground)
        .frame(minWidth: 260, idealWidth: 320, maxWidth: 380)
    }
    
    // MARK: - Header (Tabs + Subheader Action Row + Search)
    
    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Row 1: Character / Emote tabs
            HStack(spacing: 24) {
                // Character tab button
                Button(action: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        currentTab = .character
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 19))
                            .foregroundColor(currentTab == .character ? .black : Color.black.opacity(0.45))
                        
                        Text("Character")
                            .font(.system(size: 18, weight: currentTab == .character ? .bold : .regular))
                            .foregroundColor(currentTab == .character ? .black : Color.black.opacity(0.45))
                    }
                }
                .buttonStyle(.plain)
                
                // Emote tab button
                Button(action: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        currentTab = .emote
                    }
                }) {
                    Text("Emote")
                        .font(.system(size: 18, weight: currentTab == .emote ? .bold : .regular))
                        .foregroundColor(currentTab == .emote ? .black : Color.black.opacity(0.45))
                }
                .buttonStyle(.plain)
                
                Spacer()
            }
            
            // Row 2: Subheader (+ New Character / Filter and Search icon)
            HStack {
                if currentTab == .character {
                    // + New Character button
                    Button(action: onAddNewMemoji) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 17, weight: .medium))
                            Text("New Character")
                                .font(.system(size: 16, weight: .regular))
                        }
                        .foregroundColor(.black)
                    }
                    .buttonStyle(.plain)
                } else {
                    // Emote category filter menu
                    Menu {
                        ForEach(StickerCategory.allCases) { cat in
                            Button(action: { selectedEmoteCategory = cat }) {
                                HStack {
                                    Text(cat.rawValue)
                                    if selectedEmoteCategory == cat {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: selectedEmoteCategory.iconName)
                                .font(.system(size: 14))
                            Text(selectedEmoteCategory == .all ? "All Emotes" : selectedEmoteCategory.rawValue)
                                .font(.system(size: 16, weight: .regular))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(.black)
                    }
                    .menuStyle(.borderlessButton)
                }
                
                Spacer()
                
                // Search icon
                Button(action: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        isSearchActive.toggle()
                        if !isSearchActive {
                            searchText = ""
                        }
                    }
                }) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(isSearchActive || !searchText.isEmpty ? .black : Color.black.opacity(0.7))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            
            // Row 3: Collapsible Search TextField
            if isSearchActive || !searchText.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundColor(Color.black.opacity(0.5))
                    
                    TextField(currentTab == .character ? "Search characters..." : "Search emotes...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundColor(.black)
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundColor(Color.black.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.75))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
    
    // MARK: - Character Content
    
    private var characterContent: some View {
        Group {
            if filteredCharacters.isEmpty {
                VStack(spacing: 12) {
                    Spacer(minLength: 40)
                    Text("No characters found")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.secondaryText)
                    if !searchText.isEmpty {
                        Button("Clear Search") {
                            searchText = ""
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(.black)
                    }
                }
                .frame(maxWidth: .infinity)
            } else if viewMode == .grid {
                LazyVGrid(columns: gridColumns, spacing: 14) {
                    ForEach(filteredCharacters) { item in
                        CharacterCardView(
                            item: item,
                            avatarObject: avatarObjects[item.id],
                            isSelected: selectedAvatarId == item.id,
                            isFavorite: favorites.isCharacterFavorite(item.id),
                            onSelect: {
                                selectedAvatarId = item.id
                            },
                            onToggleFavorite: {
                                favorites.toggleCharacterFavorite(item.id)
                            },
                            onEdit: {
                                onEditMemoji(item)
                            },
                            onDuplicate: onDuplicateMemoji != nil ? {
                                onDuplicateMemoji?(item)
                            } : nil,
                            onDelete: item.isCustomMemoji ? {
                                onDeleteCustomMemoji(item)
                            } : nil,
                            onRename: onRenameMemoji != nil ? {
                                onRenameMemoji?(item)
                            } : nil
                        )
                    }
                }
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(filteredCharacters) { item in
                        CharacterListRowView(
                            item: item,
                            avatarObject: avatarObjects[item.id],
                            isSelected: selectedAvatarId == item.id,
                            isFavorite: favorites.isCharacterFavorite(item.id),
                            onSelect: {
                                selectedAvatarId = item.id
                            },
                            onToggleFavorite: {
                                favorites.toggleCharacterFavorite(item.id)
                            },
                            onEdit: {
                                onEditMemoji(item)
                            }
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - Emote Content
    
    private var emoteContent: some View {
        Group {
            if filteredEmotes.isEmpty {
                VStack(spacing: 12) {
                    Spacer(minLength: 40)
                    Text("No emotes found")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.secondaryText)
                    if !searchText.isEmpty {
                        Button("Clear Search") {
                            searchText = ""
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(.black)
                    }
                }
                .frame(maxWidth: .infinity)
            } else if viewMode == .grid {
                LazyVGrid(columns: gridColumns, spacing: 14) {
                    ForEach(filteredEmotes) { sticker in
                        EmoteCardView(
                            sticker: sticker,
                            avatarObject: selectedAvatarId != nil ? avatarObjects[selectedAvatarId!] : nil,
                            isAnimoji: isAnimoji,
                            animojiName: animojiName,
                            isSelected: activePoseName == sticker.name,
                            isFavorite: favorites.isEmoteFavorite(sticker.name),
                            onSelect: {
                                if activePoseName == sticker.name {
                                    activePoseName = nil
                                } else {
                                    activePoseName = sticker.name
                                }
                            },
                            onToggleFavorite: {
                                favorites.toggleEmoteFavorite(sticker.name)
                            },
                            onCopy: {
                                onCopySticker?(sticker)
                            }
                        )
                    }
                }
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(filteredEmotes) { sticker in
                        EmoteListRowView(
                            sticker: sticker,
                            avatarObject: selectedAvatarId != nil ? avatarObjects[selectedAvatarId!] : nil,
                            isAnimoji: isAnimoji,
                            animojiName: animojiName,
                            isSelected: activePoseName == sticker.name,
                            isFavorite: favorites.isEmoteFavorite(sticker.name),
                            onSelect: {
                                if activePoseName == sticker.name {
                                    activePoseName = nil
                                } else {
                                    activePoseName = sticker.name
                                }
                            },
                            onToggleFavorite: {
                                favorites.toggleEmoteFavorite(sticker.name)
                            },
                            onCopy: {
                                onCopySticker?(sticker)
                            }
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - Footer (Grid & List View Mode Switcher)
    
    private var sidebarFooter: some View {
        HStack(spacing: 22) {
            // 2x2 Grid View Mode Button
            Button(action: {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                    viewMode = .grid
                }
            }) {
                Grid2x2Icon(isSelected: viewMode == .grid)
            }
            .buttonStyle(.plain)
            .help("Grid View (2 columns)")
            
            // 2-Row List View Mode Button
            Button(action: {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                    viewMode = .list
                }
            }) {
                List2RowIcon(isSelected: viewMode == .list)
            }
            .buttonStyle(.plain)
            .help("List View")
        }
    }
}
