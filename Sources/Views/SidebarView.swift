import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
    public let onToggleSidebar: (() -> Void)?
    
    @ObservedObject private var favorites = FavoritesManager.shared
    @ObservedObject private var orderManager = CharacterOrderManager.shared
    @State private var draggedAvatarItem: AvatarItem? = nil
    @State private var searchText: String = ""
    @State private var isSearchActive: Bool = false
    @State private var selectedEmoteCategory: StickerCategory = .all
    @State private var isSelectionMode: Bool = false
    @State private var selectedCharacterIds: Set<String> = []
    @State private var isShowingDeleteBatchAlert: Bool = false
    @State private var isHoveringCollapse: Bool = false
    @State private var isHoveringSearch: Bool = false
    @State private var isHoveringNewCharacter: Bool = false
    
    private let supportedDropTypes: [String] = [
        UTType.utf8PlainText.identifier,
        UTType.plainText.identifier,
        UTType.text.identifier,
        "NSStringPboardType"
    ]
    
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
        onCopySticker: ((StickerItem) -> Void)? = nil,
        onToggleSidebar: (() -> Void)? = nil
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
        self.onToggleSidebar = onToggleSidebar
    }
    
    private var allCharacters: [AvatarItem] {
        let items = customMemojis + userMemojis + randomMemojis + builtinAnimojis
        return orderManager.applyOrder(to: items, favorites: favorites)
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
            // Top Section (Header Toolbar)
            sidebarHeader
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity)
                .background(
                    AppTheme.sidebarBackground
                        .overlay(
                            Rectangle()
                                .fill(Color.primary.opacity(0.06))
                                .frame(height: 1),
                            alignment: .bottom
                        )
                )
            
            // Content Area (Characters or Emotes Grid/List)
            ScrollView {
                if currentTab == .character {
                    characterContent
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 24)
                } else {
                    emoteContent
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 24)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onDrop(of: supportedDropTypes, isTargeted: nil) { _ in
                draggedAvatarItem = nil
                return true
            }
            
            // Bottom Section (Character & Emote Tabs + View Mode Switcher)
            sidebarFooter
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    AppTheme.sidebarBackground
                        .overlay(
                            Rectangle()
                                .fill(Color.primary.opacity(0.06))
                                .frame(height: 1),
                            alignment: .top
                        )
                )
        }
        .background(AppTheme.sidebarBackground)
        .frame(minWidth: 280, idealWidth: 330, maxWidth: 380)
        .onChange(of: currentTab) { _, newTab in
            if newTab != .character {
                isSelectionMode = false
                selectedCharacterIds.removeAll()
            }
        }
        .alert(isPresented: $isShowingDeleteBatchAlert) {
            Alert(
                title: Text("Delete \(deletableSelectedItems.count) Custom Memoji\(deletableSelectedItems.count > 1 ? "s" : "")?"),
                message: Text("This action cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    batchDeleteSelected()
                },
                secondaryButton: .cancel()
            )
        }
        .onExitCommand {
            if isSelectionMode {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    isSelectionMode = false
                    selectedCharacterIds.removeAll()
                }
            }
        }
    }
    
    // MARK: - Header (Toolbar: Title, Actions & Search)
    
    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Row 1: Collapse Button + Title with Live Count Badge + Search Toggle Button
            HStack(spacing: 8) {
                // Collapse Sidebar Button
                if let toggle = onToggleSidebar {
                    Button(action: toggle) {
                        Image(systemName: "sidebar.leading")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(isHoveringCollapse ? .primary : .secondary)
                            .frame(width: 30, height: 30)
                            .background(Color.primary.opacity(isHoveringCollapse ? 0.1 : 0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .onHover { h in isHoveringCollapse = h }
                    .help("Collapse Sidebar (⌘\\)")
                }
                
                // Section Title & Item Count Badge
                HStack(spacing: 7) {
                    Text(currentTab == .character ? "Characters" : "Emotes")
                        .font(.system(size: 15.5, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Text("\(currentTab == .character ? filteredCharacters.count : filteredEmotes.count)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Capsule())
                }
                
                Spacer()
                
                // Search Toggle Button (matching 30x30 rounded square)
                Button(action: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        isSearchActive.toggle()
                        if !isSearchActive {
                            searchText = ""
                        }
                    }
                }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isSearchActive || !searchText.isEmpty ? Color.accentColor.opacity(0.14) : Color.primary.opacity(isHoveringSearch ? 0.1 : 0.05))
                            .frame(width: 30, height: 30)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isSearchActive || !searchText.isEmpty ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08), lineWidth: 1)
                            )
                        
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(isSearchActive || !searchText.isEmpty ? Color.accentColor : (isHoveringSearch ? .primary : .secondary))
                    }
                }
                .buttonStyle(.plain)
                .onHover { h in isHoveringSearch = h }
                .help(isSearchActive ? "Close Search" : "Search (⌘F)")
            }
            
            // Row 2: Contextual Actions Row
            HStack(spacing: 8) {
                if currentTab == .character {
                    // + New Character button (prominent accented CTA)
                    Button(action: onAddNewMemoji) {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                                .font(.system(size: 11.5, weight: .bold))
                            Text("New Character")
                                .font(.system(size: 12.5, weight: .semibold))
                        }
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5.5)
                        .background(Color.accentColor.opacity(isHoveringNewCharacter ? 0.18 : 0.11))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.accentColor.opacity(0.28), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .onHover { h in isHoveringNewCharacter = h }
                    .help("Create a new 3D Memoji (⌘N)")
                    
                    Spacer()
                    
                    // Select Multiple toggle button
                    Button(action: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            isSelectionMode.toggle()
                            if !isSelectionMode {
                                selectedCharacterIds.removeAll()
                            }
                        }
                    }) {
                        HStack(spacing: 4.5) {
                            Image(systemName: isSelectionMode ? "checkmark.circle.fill" : "checkmark.circle")
                                .font(.system(size: 11.5, weight: .semibold))
                            Text(isSelectionMode ? "Done" : "Select")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(isSelectionMode ? .accentColor : .primary.opacity(0.85))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5.5)
                        .background(isSelectionMode ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelectionMode ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(isSelectionMode ? "Exit Selection Mode (Esc)" : "Select multiple characters to favorite or delete")
                } else {
                    // Emote category filter menu
                    Menu {
                        ForEach(StickerCategory.allCases) { cat in
                            Button(action: { selectedEmoteCategory = cat }) {
                                HStack {
                                    Label(cat.rawValue, systemImage: cat.iconName)
                                    if selectedEmoteCategory == cat {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: selectedEmoteCategory.iconName)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(Color.accentColor)
                            Text(selectedEmoteCategory == .all ? "All Emotes" : selectedEmoteCategory.rawValue)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundColor(.primary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5.5)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .menuStyle(.borderlessButton)
                    
                    Spacer()
                    
                    if selectedEmoteCategory != .all {
                        Button(action: {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                                selectedEmoteCategory = .all
                            }
                        }) {
                            Text("Clear")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            // Row 3: Collapsible Search TextField
            if isSearchActive || !searchText.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    TextField(currentTab == .character ? "Filter characters..." : "Filter emotes...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .foregroundColor(.primary)
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
    
    // MARK: - Character Content
    
    private var characterContent: some View {
        VStack(spacing: 8) {
            // Batch selection action bar (shows when selection mode is active)
            if isSelectionMode {
                HStack(spacing: 8) {
                    Button(action: toggleSelectAll) {
                        HStack(spacing: 5) {
                            Image(systemName: selectedCharacterIds.count == filteredCharacters.count && !filteredCharacters.isEmpty ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundColor(selectedCharacterIds.isEmpty ? .secondary : .accentColor)
                            
                            Text(selectedCharacterIds.isEmpty ? "Select All" : "\(selectedCharacterIds.count) Selected")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    // Batch Move to Top button
                    Button(action: batchMoveToTop) {
                        Image(systemName: "arrow.up.to.line")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundColor(selectedCharacterIds.isEmpty ? .secondary.opacity(0.35) : .accentColor)
                            .frame(width: 28, height: 28)
                            .background(selectedCharacterIds.isEmpty ? Color.primary.opacity(0.04) : Color.accentColor.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedCharacterIds.isEmpty)
                    .help("Move Selected Characters to Top")
                    
                    // Batch Favorite / Unfavorite button
                    Button(action: batchToggleFavorite) {
                        Image(systemName: allSelectedAreFavorites ? "star.slash.fill" : "star.fill")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundColor(allSelectedAreFavorites ? .secondary : AppTheme.goldColor)
                            .frame(width: 28, height: 28)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedCharacterIds.isEmpty)
                    .help(allSelectedAreFavorites ? "Unfavorite Selected Characters" : "Favorite Selected Characters")
                    
                    // Batch Delete button
                    Button(action: {
                        isShowingDeleteBatchAlert = true
                    }) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundColor(deletableSelectedItems.count > 0 ? .red : .secondary.opacity(0.35))
                            .frame(width: 28, height: 28)
                            .background(deletableSelectedItems.count > 0 ? Color.red.opacity(0.12) : Color.primary.opacity(0.04))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(deletableSelectedItems.isEmpty)
                    .help(deletableSelectedItems.count > 0 ? "Delete \(deletableSelectedItems.count) Custom Memoji(s)" : "Only custom studio Memojis can be deleted")
                    
                    // Done button
                    Button(action: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            isSelectionMode = false
                            selectedCharacterIds.removeAll()
                        }
                    }) {
                        Text("Done")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 3, y: 1)
                .padding(.bottom, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            if filteredCharacters.isEmpty {
                VStack(spacing: 12) {
                    Spacer(minLength: 40)
                    Image(systemName: "person.slash")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text("No characters found")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                    if !searchText.isEmpty {
                        Button("Clear Search") {
                            searchText = ""
                        }
                        .buttonStyle(.bordered)
                        .font(.system(size: 12))
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
                            isSelectionMode: isSelectionMode,
                            isMarked: selectedCharacterIds.contains(item.id),
                            isBeingDragged: draggedAvatarItem?.id == item.id,
                            hasCustomOrder: orderManager.hasCustomOrder,
                            onSelect: {
                                if isSelectionMode {
                                    toggleCharacterSelection(item.id)
                                } else {
                                    selectedAvatarId = item.id
                                }
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
                            } : nil,
                            onHoldClick: {
                                if !isSelectionMode {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                        isSelectionMode = true
                                        selectedCharacterIds = [item.id]
                                    }
                                } else {
                                    toggleCharacterSelection(item.id)
                                }
                            },
                            onEnterSelectionMode: {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                    isSelectionMode = true
                                    selectedCharacterIds = [item.id]
                                }
                            },
                            onMoveToTop: {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                    orderManager.moveToTop(id: item.id, currentItems: allCharacters)
                                }
                            },
                            onMoveToBottom: {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                    orderManager.moveToBottom(id: item.id, currentItems: allCharacters)
                                }
                            },
                            onMoveForward: {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                    orderManager.moveByOffset(id: item.id, offset: 1, currentItems: allCharacters)
                                }
                            },
                            onMoveBackward: {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                    orderManager.moveByOffset(id: item.id, offset: -1, currentItems: allCharacters)
                                }
                            },
                            onResetOrder: {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                    orderManager.resetOrder()
                                }
                            }
                        )
                        .onDrag {
                            self.draggedAvatarItem = item
                            return NSItemProvider(object: item.id as NSString)
                        }
                        .onDrop(
                            of: supportedDropTypes,
                            delegate: CharacterDropDelegate(
                                targetItem: item,
                                draggedItem: $draggedAvatarItem,
                                onMove: { source, target in
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                        orderManager.move(sourceId: source.id, targetId: target.id, currentItems: allCharacters)
                                    }
                                },
                                onDropEnded: {
                                    draggedAvatarItem = nil
                                }
                            )
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
                            isSelectionMode: isSelectionMode,
                            isMarked: selectedCharacterIds.contains(item.id),
                            isBeingDragged: draggedAvatarItem?.id == item.id,
                            hasCustomOrder: orderManager.hasCustomOrder,
                            onSelect: {
                                if isSelectionMode {
                                    toggleCharacterSelection(item.id)
                                } else {
                                    selectedAvatarId = item.id
                                }
                            },
                            onToggleFavorite: {
                                favorites.toggleCharacterFavorite(item.id)
                            },
                            onEdit: {
                                onEditMemoji(item)
                            },
                            onHoldClick: {
                                if !isSelectionMode {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                        isSelectionMode = true
                                        selectedCharacterIds = [item.id]
                                    }
                                } else {
                                    toggleCharacterSelection(item.id)
                                }
                            },
                            onEnterSelectionMode: {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                    isSelectionMode = true
                                    selectedCharacterIds = [item.id]
                                }
                            },
                            onMoveToTop: {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                    orderManager.moveToTop(id: item.id, currentItems: allCharacters)
                                }
                            },
                            onMoveToBottom: {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                    orderManager.moveToBottom(id: item.id, currentItems: allCharacters)
                                }
                            },
                            onMoveForward: {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                    orderManager.moveByOffset(id: item.id, offset: 1, currentItems: allCharacters)
                                }
                            },
                            onMoveBackward: {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                    orderManager.moveByOffset(id: item.id, offset: -1, currentItems: allCharacters)
                                }
                            },
                            onResetOrder: {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                    orderManager.resetOrder()
                                }
                            }
                        )
                        .onDrag {
                            self.draggedAvatarItem = item
                            return NSItemProvider(object: item.id as NSString)
                        }
                        .onDrop(
                            of: supportedDropTypes,
                            delegate: CharacterDropDelegate(
                                targetItem: item,
                                draggedItem: $draggedAvatarItem,
                                onMove: { source, target in
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                        orderManager.move(sourceId: source.id, targetId: target.id, currentItems: allCharacters)
                                    }
                                },
                                onDropEnded: {
                                    draggedAvatarItem = nil
                                }
                            )
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - Batch Selection Helpers
    
    private var allSelectedAreFavorites: Bool {
        guard !selectedCharacterIds.isEmpty else { return false }
        return selectedCharacterIds.allSatisfy { favorites.isCharacterFavorite($0) }
    }
    
    private var deletableSelectedItems: [AvatarItem] {
        filteredCharacters.filter { selectedCharacterIds.contains($0.id) && $0.isCustomMemoji }
    }
    
    private func batchMoveToTop() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            orderManager.moveSelectedToTop(ids: selectedCharacterIds, currentItems: allCharacters)
        }
    }
    
    private func toggleCharacterSelection(_ id: String) {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
            if selectedCharacterIds.contains(id) {
                selectedCharacterIds.remove(id)
            } else {
                selectedCharacterIds.insert(id)
            }
        }
    }
    
    private func toggleSelectAll() {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
            if selectedCharacterIds.count == filteredCharacters.count {
                selectedCharacterIds.removeAll()
            } else {
                selectedCharacterIds = Set(filteredCharacters.map(\.id))
            }
        }
    }
    
    private func batchToggleFavorite() {
        let turnOff = allSelectedAreFavorites
        for id in selectedCharacterIds {
            let isFav = favorites.isCharacterFavorite(id)
            if turnOff && isFav {
                favorites.toggleCharacterFavorite(id)
            } else if !turnOff && !isFav {
                favorites.toggleCharacterFavorite(id)
            }
        }
    }
    
    private func batchDeleteSelected() {
        let items = deletableSelectedItems
        for item in items {
            onDeleteCustomMemoji(item)
            selectedCharacterIds.remove(item.id)
        }
        if selectedCharacterIds.isEmpty {
            isSelectionMode = false
        }
    }
    
    // MARK: - Emote Content
    
    private func isEmoteSelected(_ sticker: StickerItem) -> Bool {
        guard let active = activePoseName else { return false }
        return active.caseInsensitiveCompare(sticker.name) == .orderedSame
            || active.caseInsensitiveCompare(sticker.id) == .orderedSame
    }
    
    private var emoteContent: some View {
        let avatarObj = selectedAvatarId != nil ? avatarObjects[selectedAvatarId!] : nil
        let animojiFlag = isAnimoji
        let animojiVal = animojiName
        let emotes = filteredEmotes
        
        return Group {
            if emotes.isEmpty {
                VStack(spacing: 12) {
                    Spacer(minLength: 40)
                    Image(systemName: "sparkles")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text("No emotes found")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                    if !searchText.isEmpty {
                        Button("Clear Search") {
                            searchText = ""
                        }
                        .buttonStyle(.bordered)
                        .font(.system(size: 12))
                    }
                }
                .frame(maxWidth: .infinity)
            } else if viewMode == .grid {
                LazyVGrid(columns: gridColumns, spacing: 14) {
                    ForEach(emotes) { sticker in
                        EmoteCardView(
                            sticker: sticker,
                            avatarObject: avatarObj,
                            isAnimoji: animojiFlag,
                            animojiName: animojiVal,
                            isSelected: isEmoteSelected(sticker),
                            isFavorite: favorites.isEmoteFavorite(sticker.name),
                            onSelect: {
                                if isEmoteSelected(sticker) {
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
                    ForEach(emotes) { sticker in
                        EmoteListRowView(
                            sticker: sticker,
                            avatarObject: avatarObj,
                            isAnimoji: animojiFlag,
                            animojiName: animojiVal,
                            isSelected: isEmoteSelected(sticker),
                            isFavorite: favorites.isEmoteFavorite(sticker.name),
                            onSelect: {
                                if isEmoteSelected(sticker) {
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
    
    // MARK: - Footer (Tabs & View Mode Switcher)
    
    private var sidebarFooter: some View {
        HStack(spacing: 8) {
            // Character & Emote Tab Segmented Control
            HStack(spacing: 4) {
                // Character tab button
                Button(action: {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                        currentTab = .character
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                        
                        Text("Character")
                            .font(.system(size: 12.5, weight: currentTab == .character ? .semibold : .medium))
                    }
                    .foregroundColor(currentTab == .character ? .primary : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(currentTab == .character ? Color(nsColor: .controlBackgroundColor) : Color.clear)
                            .shadow(color: currentTab == .character ? Color.black.opacity(0.08) : Color.clear, radius: 3, y: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Characters (⇥)")
                
                // Emote tab button
                Button(action: {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                        currentTab = .emote
                        if activePoseName == nil, let first = filteredEmotes.first {
                            activePoseName = first.name
                        }
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                        
                        Text("Emote")
                            .font(.system(size: 12.5, weight: currentTab == .emote ? .semibold : .medium))
                    }
                    .foregroundColor(currentTab == .emote ? .primary : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(currentTab == .emote ? Color(nsColor: .controlBackgroundColor) : Color.clear)
                            .shadow(color: currentTab == .emote ? Color.black.opacity(0.08) : Color.clear, radius: 3, y: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Emotes (⇥)")
            }
            .animation(.spring(response: 0.22, dampingFraction: 0.8), value: currentTab)
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color.primary.opacity(0.06))
            )
            
            // View Mode Switcher (2x2 Grid / 2-Row List)
            HStack(spacing: 2) {
                // 2x2 Grid View Mode Button
                Button(action: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        viewMode = .grid
                    }
                }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(viewMode == .grid ? Color.primary.opacity(0.1) : Color.clear)
                            .frame(width: 28, height: 26)
                        
                        Grid2x2Icon(isSelected: viewMode == .grid)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Grid View (2 columns)")
                
                // 2-Row List View Mode Button
                Button(action: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        viewMode = .list
                    }
                }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(viewMode == .list ? Color.primary.opacity(0.1) : Color.clear)
                            .frame(width: 28, height: 26)
                        
                        List2RowIcon(isSelected: viewMode == .list)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("List View")
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.04))
            )
        }
        .padding(.horizontal, 14)
    }
}

// MARK: - Character Drop Delegate for Drag-to-Reorder
struct CharacterDropDelegate: DropDelegate {
    let targetItem: AvatarItem
    @Binding var draggedItem: AvatarItem?
    let onMove: (AvatarItem, AvatarItem) -> Void
    let onDropEnded: () -> Void
    
    func dropEntered(info: DropInfo) {
        guard let dragged = draggedItem, dragged.id != targetItem.id else { return }
        onMove(dragged, targetItem)
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
    
    func performDrop(info: DropInfo) -> Bool {
        draggedItem = nil
        onDropEnded()
        return true
    }
    
    func dropExited(info: DropInfo) {
    }
    
    func validateDrop(info: DropInfo) -> Bool {
        return draggedItem != nil
    }
}

