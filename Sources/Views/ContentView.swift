import SwiftUI
import AppKit
/// Atomic, immutable payload for presenting the Memoji editor sheet.
/// Conforms to Identifiable to guarantee 100% reliable first-click sheet presentation with no state races.
public struct EditorContext: Identifiable {
    public let id = UUID()
    public let avatar: AnyObject
    public let name: String
    public let item: AvatarItem?
    public let isNew: Bool
    
    public init(avatar: AnyObject, name: String, item: AvatarItem? = nil, isNew: Bool = false) {
        self.avatar = avatar
        self.name = name
        self.item = item
        self.isNew = isNew
    }
}

public struct ContentView: View {
    @State private var customMemojis: [AvatarItem] = []
    @State private var userMemojis: [AvatarItem] = []
    @State private var builtinAnimojis: [AvatarItem] = []
    @State private var randomMemojis: [AvatarItem] = []
    @State private var selectedAvatarId: String?
    @State private var activePoseName: String?
    
    @State private var currentTab: SidebarTab = .character
    @State private var viewMode: SidebarViewMode = .grid
    
    // In-memory cache for live AVTAvatar/AVTAnimoji instances
    @State private var avatarObjects: [String: AnyObject] = [:]
    @State private var avatarStickers: [String: [StickerItem]] = [:]
    @State private var isLoading: Bool = true
    
    // Editor sheet state (unified atomic Identifiable context)
    @State private var editorContext: EditorContext? = nil
    @State private var toastMessage: String? = nil
    
    // Sidebar collapse & full screen state
    @State private var isSidebarCollapsed: Bool = false
    @State private var isFullScreen: Bool = false
    @State private var isHoveringFloatingSidebar: Bool = false
    
    public init() {}
    
    public var selectedAvatarItem: AvatarItem? {
        guard let id = selectedAvatarId else {
            return customMemojis.first ?? userMemojis.first ?? builtinAnimojis.first
        }
        return customMemojis.first(where: { $0.id == id })
            ?? userMemojis.first(where: { $0.id == id })
            ?? randomMemojis.first(where: { $0.id == id })
            ?? builtinAnimojis.first(where: { $0.id == id })
            ?? customMemojis.first
            ?? userMemojis.first
            ?? builtinAnimojis.first
    }
    
    private var isAnimoji: Bool {
        if case .builtinAnimoji = selectedAvatarItem?.sourceType { return true }
        return false
    }
    
    private var animojiName: String? {
        if case .builtinAnimoji(let name) = selectedAvatarItem?.sourceType { return name }
        return nil
    }
    
    private var selectedAvatarIdBinding: Binding<String?> {
        Binding(
            get: { selectedAvatarId },
            set: { newId in
                if let id = newId {
                    AvatarKitBridge.shared.cancelPendingStickerRenders()
                    ensureAvatarLoaded(forId: id)
                    selectedAvatarId = id
                    
                    // Ensure active emote stays active and outlined across character switches
                    if let active = activePoseName {
                        let stickers = stickersForCurrentAvatar()
                        if !stickers.contains(where: { $0.name.caseInsensitiveCompare(active) == .orderedSame }) {
                            // If previous pose is not supported on the newly selected character, fallback to first available
                            activePoseName = stickers.first?.name
                        }
                    }
                } else {
                    selectedAvatarId = nil
                }
            }
        )
    }
    
    private func currentAvatarObject(for item: AvatarItem) -> AnyObject? {
        if let obj = avatarObjects[item.id] {
            return obj
        }
        if let obj = Self.loadAvatarObject(for: item) {
            avatarObjects[item.id] = obj
            return obj
        }
        return nil
    }
    
    private func stickersForCurrentAvatar() -> [StickerItem] {
        guard let item = selectedAvatarItem else { return [] }
        if let cached = avatarStickers[item.id] {
            return cached
        }
        let items = Self.loadStickerItems(for: item)
        avatarStickers[item.id] = items
        return items
    }
    
    public var body: some View {
        HStack(spacing: 0) {
            // Left Sidebar (Collapsible)
            if !isSidebarCollapsed {
                SidebarView(
                    selectedAvatarId: selectedAvatarIdBinding,
                    activePoseName: $activePoseName,
                    currentTab: $currentTab,
                    viewMode: $viewMode,
                    userMemojis: userMemojis,
                    customMemojis: customMemojis,
                    builtinAnimojis: builtinAnimojis,
                    randomMemojis: randomMemojis,
                    avatarObjects: avatarObjects,
                    stickersForSelectedAvatar: stickersForCurrentAvatar(),
                    onAddNewMemoji: startCreatingNewMemoji,
                    onEditMemoji: startEditingMemoji,
                    onDuplicateMemoji: duplicateMemoji,
                    onDeleteAvatar: deleteAvatar,
                    onRenameMemoji: renameMemoji,
                    onRefreshRequested: reloadData,
                    onCopySticker: copyStickerToClipboard,
                    onToggleSidebar: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            isSidebarCollapsed.toggle()
                        }
                    }
                )
                .frame(width: 330)
                .transition(.asymmetric(
                    insertion: .move(edge: .leading).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                
                // Subtle vertical divider between sidebar and main area
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 1)
                    .transition(.opacity)
            }
            
            // Right Main Stage
            ZStack {
                // Floating Expand Sidebar Button when collapsed
                if isSidebarCollapsed {
                    VStack {
                        HStack {
                            Button(action: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                    isSidebarCollapsed = false
                                }
                            }) {
                                Image(systemName: "sidebar.leading")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.primary.opacity(0.85))
                                    .frame(width: 32, height: 32)
                                    .background(.ultraThinMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.primary.opacity(isHoveringFloatingSidebar ? 0.2 : 0.08), lineWidth: 1)
                                    )
                                    .scaleEffect(isHoveringFloatingSidebar ? 1.05 : 1.0)
                                    .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
                            }
                            .buttonStyle(.plain)
                            .onHover { h in isHoveringFloatingSidebar = h }
                            .help("Show Sidebar (⌘\\)")
                            
                            Spacer()
                        }
                        .padding(.top, 18)
                        .padding(.leading, 18)
                        
                        Spacer()
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    .zIndex(60)
                }
                
                if isLoading {
                    VStack(spacing: 14) {
                        ProgressView()
                            .scaleEffect(0.85)
                        Text("Loading Apple Memojis...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.stageBackground)
                } else if let current = selectedAvatarItem {
                    AvatarDetailView(
                        avatarItem: current,
                        avatarObject: currentAvatarObject(for: current),
                        activePoseName: activePoseName,
                        isFullScreen: isFullScreen,
                        onResetPoseAndCamera: {
                            activePoseName = nil
                        },
                        onEditRequested: {
                            startEditingMemoji(item: current)
                        },
                        onRenameRequested: { newName in
                            renameAvatar(item: current, newName: newName)
                        },
                        onDeleteRequested: {
                            deleteAvatar(item: current)
                        },
                        onCopiedNotification: { msg in
                            showToast(msg)
                        },
                        onToggleFullScreen: {
                            toggleFullScreen()
                        }
                    )
                } else {
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.1))
                                .frame(width: 72, height: 72)
                            
                            Image(systemName: "sparkles")
                                .font(.system(size: 30))
                                .foregroundColor(.accentColor)
                        }
                        
                        Text("No Memoji Selected")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        
                        Button(action: startCreatingNewMemoji) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                    .font(.system(size: 13, weight: .bold))
                                Text("New Character")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .contentShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(SpringPressButtonStyle())
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.stageBackground)
                }
                
                // Floating App Toast Notification HUD (Top-Center macOS HUD Style)
                if let toast = toastMessage {
                    VStack {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 13.5, weight: .semibold))
                            Text(toast)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8.5)
                        .background(.ultraThickMaterial)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.primary.opacity(0.09), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
                        .padding(.top, 18)
                        
                        Spacer()
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
                    .zIndex(100)
                    .allowsHitTesting(false)
                }
            }
            .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: isSidebarCollapsed ? 520 : 880, minHeight: 560)
        .sheet(item: $editorContext) { context in
            MemojiEditorView(
                avatar: context.avatar,
                name: context.name,
                isNew: context.isNew,
                onSave: { name, savedAvatar in
                    handleEditorSave(name: name, savedAvatar: savedAvatar, targetItem: context.item)
                },
                onCancel: {
                    editorContext = nil
                }
            )
        }
        .onAppear {
            DispatchQueue.main.async {
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
            }
        }
        .task {
            await loadInitialData()
        }
        .onChange(of: selectedAvatarId) { _, newId in
            if let id = newId {
                AvatarKitBridge.shared.cancelPendingStickerRenders()
                ensureAvatarLoaded(forId: id)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                isFullScreen = true
                isSidebarCollapsed = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                isFullScreen = false
                isSidebarCollapsed = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebarRequested)) { _ in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                isSidebarCollapsed.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebarTabRequested)) { _ in
            toggleSidebarTab()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleFullScreenRequested)) { _ in
            toggleFullScreen()
        }
        .onReceive(NotificationCenter.default.publisher(for: .newMemojiRequested)) { _ in
            startCreatingNewMemoji()
        }
        .onReceive(NotificationCenter.default.publisher(for: .customizeMemojiRequested)) { _ in
            if let current = selectedAvatarItem, current.isEditable {
                startEditingMemoji(item: current)
            }
        }
    }
    
    private func toggleSidebarTab() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            if isSidebarCollapsed {
                isSidebarCollapsed = false
            }
            if currentTab == .character {
                currentTab = .emote
                if activePoseName == nil {
                    let stickers = stickersForCurrentAvatar()
                    if let first = stickers.first {
                        activePoseName = first.name
                    }
                }
            } else {
                currentTab = .character
            }
        }
    }
    
    private func toggleFullScreen() {
        if let window = NSApp.keyWindow ?? NSApp.windows.first {
            window.toggleFullScreen(nil)
        }
    }
    
    // MARK: - Data Loading
    
    @MainActor
    private func loadInitialData() async {
        isLoading = true
        
        // 1. Custom Studio Memojis from app storage
        let customs = AvatarDatabaseReader.shared.fetchCustomAvatars()
        self.customMemojis = customs
        
        // 2. User Memojis from Apple SQLite database
        let dbUsers = AvatarDatabaseReader.shared.fetchUserMemojis()
        self.userMemojis = dbUsers
        
        // 3. Apple built-in Animojis from AvatarKit
        let hiddenIds = AvatarDatabaseReader.shared.hiddenAvatarIds()
        let names = AvatarKitBridge.shared.animojiNames()
        self.builtinAnimojis = names.compactMap { name in
            let id = "animoji_\(name)"
            if hiddenIds.contains(id) { return nil }
            return AvatarItem(
                id: id,
                displayName: name.capitalized,
                sourceType: .builtinAnimoji(name: name)
            )
        }
        
        // Select first available avatar if nothing selected yet
        let firstId = selectedAvatarId ?? customs.first?.id ?? dbUsers.first?.id ?? builtinAnimojis.first?.id
        selectedAvatarId = firstId
        
        // Load the first avatar and stickers synchronously so the main stage renders on frame 0
        if let id = firstId {
            ensureAvatarLoaded(forId: id)
        }
        
        isLoading = false
        
        // Ensure customizer engine and neutral avatar are pre-warmed after first UI presentation
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            MemojiCustomizer.shared.prewarm()
        }
    }
    
    @MainActor
    private func reloadData() {
        let currentId = selectedAvatarId
        avatarObjects.removeAll()
        avatarStickers.removeAll()
        ThumbnailCache.shared.clear()
        AvatarKitBridge.shared.cancelPendingStickerRenders()
        Task {
            await loadInitialData()
            if let id = currentId, !id.isEmpty {
                selectedAvatarId = id
                ensureAvatarLoaded(forId: id)
            }
            showToast("System database reloaded")
        }
    }
    
    @MainActor
    private func ensureAvatarLoaded(forId id: String) {
        guard let item = customMemojis.first(where: { $0.id == id })
                        ?? userMemojis.first(where: { $0.id == id })
                        ?? randomMemojis.first(where: { $0.id == id })
                        ?? builtinAnimojis.first(where: { $0.id == id }) else {
            return
        }
        
        // 1. Load 3D AVTAvatar instance if not already cached
        if avatarObjects[id] == nil {
            if let obj = Self.loadAvatarObject(for: item) {
                avatarObjects[id] = obj
            }
        }
        
        // 2. Load sticker list if not cached
        if avatarStickers[id] == nil {
            loadStickers(for: item)
        }
    }
    
    @MainActor
    private func loadStickers(for item: AvatarItem) {
        let stickers = Self.loadStickerItems(for: item)
        avatarStickers[item.id] = stickers
        ThumbnailCache.shared.prewarmEmoteThumbnails(stickers: stickers)
    }
    
    public static func loadAvatarObject(for item: AvatarItem) -> AnyObject? {
        switch item.sourceType {
        case .customMemoji:
            if let data = item.rawData,
               let avatar = AvatarKitBridge.shared.loadAvatar(fromData: data) {
                return avatar
            } else if let neutral = MemojiCustomizer.shared.createNeutralMemoji() {
                return neutral
            }
            
        case .userMemoji:
            if let data = item.rawData,
               let avatar = AvatarKitBridge.shared.loadAvatar(fromData: data) {
                return avatar
            }
            
        case .builtinAnimoji(let name):
            if let animoji = AvatarKitBridge.shared.loadAnimoji(named: name) {
                return animoji
            }
            
        case .randomMemoji:
            if let rand = AvatarKitBridge.shared.createRandomMemoji() {
                return rand
            }
        }
        return nil
    }
    
    public static func loadStickerItems(for item: AvatarItem) -> [StickerItem] {
        let allNames: [String]
        let diskStickers: [StickerItem]
        
        switch item.sourceType {
        case .customMemoji:
            allNames = AvatarKitBridge.shared.availableStickerNames(forAnimojiNamed: nil)
            diskStickers = AvatarDatabaseReader.shared.findAppCachedStickers(forAvatarId: item.id)
            
        case .userMemoji(let uuid):
            allNames = AvatarKitBridge.shared.availableStickerNames(forAnimojiNamed: nil)
            diskStickers = AvatarDatabaseReader.shared.findCachedStickers(forUUID: uuid)
            
        case .builtinAnimoji(let name):
            allNames = AvatarKitBridge.shared.availableStickerNames(forAnimojiNamed: name)
            diskStickers = AvatarDatabaseReader.shared.findCachedStickers(forAnimojiNamed: name)
            
        case .randomMemoji:
            allNames = AvatarKitBridge.shared.availableStickerNames(forAnimojiNamed: nil)
            diskStickers = AvatarDatabaseReader.shared.findAppCachedStickers(forAvatarId: item.id)
        }
        
        return mergeStickerItems(diskStickers: diskStickers, allNames: allNames, prefix: item.id)
    }
    
    public static func mergeStickerItems(diskStickers: [StickerItem], allNames: [String], prefix: String) -> [StickerItem] {
        var result: [StickerItem] = []
        var seenNames = Set<String>()
        
        // 1. Add disk stickers first (they load instantly with 0ms delay)
        for item in diskStickers {
            if seenNames.insert(item.name.lowercased()).inserted {
                result.append(item)
            }
        }
        
        // 2. Append any extra poses from availableStickerNames
        for name in allNames {
            if !seenNames.contains(name.lowercased()) {
                seenNames.insert(name.lowercased())
                let meta = AvatarDatabaseReader.shared.metadata(forStickerName: name)
                result.append(
                    StickerItem(
                        id: "\(prefix)_\(name)",
                        name: name,
                        localizedTitle: meta.title,
                        category: meta.category,
                        emoji: meta.emoji,
                        localFileURL: nil
                    )
                )
            }
        }
        
        return result
    }
    
    // MARK: - Creation & Editing
    
    @MainActor
    private func startCreatingNewMemoji() {
        guard let newAvatar = MemojiCustomizer.shared.createNeutralMemoji()
                ?? AvatarKitBridge.shared.createRandomMemoji() else {
            return
        }
        
        self.editorContext = EditorContext(
            avatar: newAvatar,
            name: "My Memoji \(customMemojis.count + 1)",
            item: nil,
            isNew: true
        )
    }
    
    @MainActor
    private func startEditingMemoji(item: AvatarItem) {
        ensureAvatarLoaded(forId: item.id)
        guard let avatar = avatarObjects[item.id]
                ?? MemojiCustomizer.shared.createNeutralMemoji() else {
            return
        }
        
        // Pass avatar directly — MemojiEditorView performs single isolated clone internally
        self.editorContext = EditorContext(
            avatar: avatar,
            name: item.displayName,
            item: item,
            isNew: false
        )
    }
    
    @MainActor
    private func duplicateMemoji(item: AvatarItem) {
        ensureAvatarLoaded(forId: item.id)
        guard let avatar = avatarObjects[item.id],
              let data = AvatarKitBridge.shared.dataRepresentation(for: avatar) else {
            return
        }
        let copyName = "\(item.displayName) Copy"
        let newItem = AvatarDatabaseReader.shared.saveCustomMemoji(name: copyName, data: data)
        CharacterOrderManager.shared.insertAtTop(id: newItem.id)
        customMemojis.insert(newItem, at: 0)
        if let cloned = AvatarKitBridge.shared.cloneAvatar(avatar) {
            avatarObjects[newItem.id] = cloned
        }
        loadStickers(for: newItem)
        selectedAvatarId = newItem.id
        showToast("Duplicated '\(item.displayName)'")
    }
    
    @MainActor
    private func renameAvatar(item: AvatarItem, newName: String) {
        switch item.sourceType {
        case .customMemoji(let id):
            _ = AvatarDatabaseReader.shared.renameCustomMemoji(id: id, newName: newName)
            if let idx = customMemojis.firstIndex(where: { $0.id == id }) {
                customMemojis[idx].displayName = newName
            }
        case .userMemoji:
            if let idx = userMemojis.firstIndex(where: { $0.id == item.id }) {
                userMemojis[idx].displayName = newName
            }
        case .builtinAnimoji:
            if let idx = builtinAnimojis.firstIndex(where: { $0.id == item.id }) {
                builtinAnimojis[idx].displayName = newName
            }
        case .randomMemoji:
            if let idx = randomMemojis.firstIndex(where: { $0.id == item.id }) {
                randomMemojis[idx].displayName = newName
            }
        }
        showToast("Renamed to '\(newName)'")
    }
    
    @MainActor
    private func renameMemoji(item: AvatarItem) {
        let alert = NSAlert()
        alert.messageText = "Rename Character"
        alert.informativeText = "Enter a new name for '\(item.displayName)':"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        input.stringValue = item.displayName
        alert.accessoryView = input
        
        if alert.runModal() == .alertFirstButtonReturn {
            let val = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !val.isEmpty {
                renameAvatar(item: item, newName: val)
            }
        }
    }
    
    @MainActor
    private func handleEditorSave(name: String, savedAvatar: AnyObject, targetItem: AvatarItem?) {
        guard let data = AvatarKitBridge.shared.dataRepresentation(for: savedAvatar) else {
            editorContext = nil
            return
        }
        
        AvatarKitBridge.shared.clearPosedStickerCache()
        ThumbnailCache.shared.clear()
        
        if let existing = targetItem {
            avatarStickers.removeValue(forKey: existing.id)
            switch existing.sourceType {
            case .customMemoji(let id):
                let updated = AvatarDatabaseReader.shared.saveCustomMemoji(name: name, data: data, existingId: id)
                if let idx = customMemojis.firstIndex(where: { $0.id == id }) {
                    customMemojis[idx] = updated
                }
                avatarObjects[id] = savedAvatar
                loadStickers(for: updated)
                selectedAvatarId = id
                showToast("Updated '\(name)'")
                
            case .userMemoji(let uuid):
                _ = AvatarDatabaseReader.shared.updateUserMemojiInSystemDatabase(uuid: uuid, data: data)
                if let idx = userMemojis.firstIndex(where: { $0.id == existing.id }) {
                    userMemojis[idx].rawData = data
                    userMemojis[idx].displayName = name
                }
                avatarObjects[existing.id] = savedAvatar
                loadStickers(for: existing)
                selectedAvatarId = existing.id
                showToast("Updated system Memoji '\(name)'")
                
            case .randomMemoji:
                let newItem = AvatarDatabaseReader.shared.saveCustomMemoji(name: name, data: data)
                CharacterOrderManager.shared.insertAtTop(id: newItem.id)
                customMemojis.insert(newItem, at: 0)
                avatarObjects[newItem.id] = savedAvatar
                loadStickers(for: newItem)
                selectedAvatarId = newItem.id
                showToast("Saved custom Memoji '\(name)'")
                
            case .builtinAnimoji:
                break
            }
        } else {
            let newItem = AvatarDatabaseReader.shared.saveCustomMemoji(name: name, data: data)
            CharacterOrderManager.shared.insertAtTop(id: newItem.id)
            customMemojis.insert(newItem, at: 0)
            avatarObjects[newItem.id] = savedAvatar
            loadStickers(for: newItem)
            selectedAvatarId = newItem.id
            showToast("Created Memoji '\(name)'")
        }
        
        editorContext = nil
        
        let savedId = selectedAvatarId
        selectedAvatarId = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            selectedAvatarId = savedId
        }
    }
    
    @MainActor
    private func deleteAvatar(item: AvatarItem) {
        // 1. Remove from backing storage by sourceType
        switch item.sourceType {
        case .customMemoji(let id):
            _ = AvatarDatabaseReader.shared.deleteCustomMemoji(id: id)
            customMemojis.removeAll { $0.id == item.id }
        case .userMemoji(let uuid):
            _ = AvatarDatabaseReader.shared.deleteUserMemoji(uuid: uuid)
            userMemojis.removeAll { $0.id == item.id }
        case .randomMemoji:
            AvatarDatabaseReader.shared.hideAvatar(id: item.id)
            randomMemojis.removeAll { $0.id == item.id }
        case .builtinAnimoji:
            AvatarDatabaseReader.shared.hideAvatar(id: item.id)
            builtinAnimojis.removeAll { $0.id == item.id }
        }
        
        // 2. Clean order, favorites, in-memory caches
        CharacterOrderManager.shared.remove(id: item.id)
        FavoritesManager.shared.removeCharacterFavorite(item.id)
        avatarObjects.removeValue(forKey: item.id)
        avatarStickers.removeValue(forKey: item.id)
        ThumbnailCache.shared.removeImage(forKey: "avatar_\(item.id)")
        
        showToast("Deleted '\(item.displayName)'")
        
        // 3. Select next available character if deleted item was selected
        if selectedAvatarId == item.id {
            let nextItem = customMemojis.first ?? userMemojis.first ?? randomMemojis.first ?? builtinAnimojis.first
            selectedAvatarId = nextItem?.id
            if let nextId = selectedAvatarId {
                ensureAvatarLoaded(forId: nextId)
            }
        }
    }
    
    @MainActor
    private func copyStickerToClipboard(sticker: StickerItem) {
        guard let id = selectedAvatarId else { return }
        let avatar = avatarObjects[id]
        
        Task {
            if let img = await ThumbnailCache.shared.getEmoteThumbnail(
                sticker: sticker,
                avatarObject: avatar,
                isAnimoji: isAnimoji,
                animojiName: animojiName
            ) {
                StickerExportManager.shared.copyToClipboard(image: img)
                showToast("Copied '\(sticker.localizedTitle)' sticker")
            }
        }
    }
    
    private func showToast(_ text: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            toastMessage = text
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                if toastMessage == text {
                    toastMessage = nil
                }
            }
        }
    }
}
