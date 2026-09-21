import SwiftUI
import AppKit

public struct ContentView: View {
    @State private var customMemojis: [AvatarItem] = []
    @State private var userMemojis: [AvatarItem] = []
    @State private var builtinAnimojis: [AvatarItem] = []
    @State private var randomMemojis: [AvatarItem] = []
    @State private var selectedAvatarId: String?
    
    // In-memory cache for live AVTAvatar/AVTAnimoji instances
    @State private var avatarObjects: [String: AnyObject] = [:]
    @State private var avatarStickers: [String: [StickerItem]] = [:]
    @State private var isLoading: Bool = true
    
    // Editor sheet state
    @State private var isShowingEditor: Bool = false
    @State private var editorTargetAvatar: AnyObject? = nil
    @State private var editorTargetName: String = "My Memoji"
    @State private var editorTargetItem: AvatarItem? = nil
    @State private var isNewMemoji: Bool = false
    
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
    
    public var body: some View {
        NavigationSplitView {
            SidebarView(
                selectedAvatarId: $selectedAvatarId,
                userMemojis: userMemojis,
                customMemojis: customMemojis,
                builtinAnimojis: builtinAnimojis,
                randomMemojis: randomMemojis,
                onAddNewMemoji: startCreatingNewMemoji,
                onEditMemoji: startEditingMemoji,
                onDeleteCustomMemoji: deleteCustomMemoji,
                onAddRandomMemoji: addRandomMemoji,
                onRefreshRequested: reloadData
            )
            .navigationSplitViewColumnWidth(min: 230, ideal: 260, max: 320)
        } detail: {
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading Apple Memoji system...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let current = selectedAvatarItem {
                AvatarDetailView(
                    avatarItem: current,
                    avatarObject: avatarObjects[current.id],
                    stickers: avatarStickers[current.id] ?? [],
                    onRandomizeRequested: {
                        randomizeCurrentMemoji(item: current)
                    },
                    onEditRequested: {
                        startEditingMemoji(item: current)
                    }
                )
                .id(current.id)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No Memoji Selected")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("Select an avatar from the sidebar or create a new custom Memoji.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 12) {
                        Button(action: startCreatingNewMemoji) {
                            Label("Create New Memoji", systemImage: "sparkles")
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button("Random Memoji") {
                            addRandomMemoji()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $isShowingEditor) {
            if let avatar = editorTargetAvatar {
                MemojiEditorView(
                    avatar: avatar,
                    name: editorTargetName,
                    isNew: isNewMemoji,
                    onSave: { name, savedAvatar in
                        handleEditorSave(name: name, savedAvatar: savedAvatar)
                    },
                    onCancel: {
                        isShowingEditor = false
                    }
                )
            }
        }
        .task {
            await loadInitialData()
        }
        .onChange(of: selectedAvatarId) { _, newId in
            if let id = newId {
                ensureAvatarLoaded(forId: id)
            }
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
        let names = AvatarKitBridge.shared.animojiNames()
        self.builtinAnimojis = names.map { name in
            AvatarItem(
                id: "animoji_\(name)",
                displayName: name,
                sourceType: .builtinAnimoji(name: name)
            )
        }
        
        // Select first available avatar if nothing selected yet
        if selectedAvatarId == nil {
            selectedAvatarId = customs.first?.id ?? dbUsers.first?.id ?? builtinAnimojis.first?.id
        }
        
        isLoading = false
        
        // Load avatar data for the selected avatar
        if let firstId = selectedAvatarId {
            ensureAvatarLoaded(forId: firstId)
        }
    }
    
    @MainActor
    private func reloadData() {
        let currentId = selectedAvatarId
        // Clear caches to force a fresh load
        avatarObjects.removeAll()
        avatarStickers.removeAll()
        Task {
            await loadInitialData()
            if let id = currentId, !id.isEmpty {
                selectedAvatarId = id
                ensureAvatarLoaded(forId: id)
            }
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
            switch item.sourceType {
            case .customMemoji:
                if let data = item.rawData,
                   let avatar = AvatarKitBridge.shared.loadAvatar(fromData: data) {
                    avatarObjects[id] = avatar
                } else if let neutral = MemojiCustomizer.shared.createNeutralMemoji() {
                    avatarObjects[id] = neutral
                }
                
            case .userMemoji:
                if let data = item.rawData,
                   let avatar = AvatarKitBridge.shared.loadAvatar(fromData: data) {
                    avatarObjects[id] = avatar
                }
                
            case .builtinAnimoji(let name):
                if let animoji = AvatarKitBridge.shared.loadAnimoji(named: name) {
                    avatarObjects[id] = animoji
                }
                
            case .randomMemoji:
                if let rand = AvatarKitBridge.shared.createRandomMemoji() {
                    avatarObjects[id] = rand
                }
            }
        }
        
        // 2. Load sticker list if not cached
        if avatarStickers[id] == nil {
            loadStickers(for: item)
        }
    }
    
    @MainActor
    private func loadStickers(for item: AvatarItem) {
        switch item.sourceType {
        case .customMemoji:
            let names = AvatarKitBridge.shared.availableStickerNames(forAnimojiNamed: nil)
            avatarStickers[item.id] = makeStickerItems(from: names, prefix: item.id)
            
        case .userMemoji(let uuid):
            // First try disk-cached high-res PNGs (fast, no AvatarKit render needed)
            let diskStickers = AvatarDatabaseReader.shared.findCachedStickers(forUUID: uuid)
            if !diskStickers.isEmpty {
                avatarStickers[item.id] = diskStickers
            } else {
                // Fall back to AvatarKit sticker config names
                let names = AvatarKitBridge.shared.availableStickerNames(forAnimojiNamed: nil)
                avatarStickers[item.id] = makeStickerItems(from: names, prefix: item.id)
            }
            
        case .builtinAnimoji(let name):
            let names = AvatarKitBridge.shared.availableStickerNames(forAnimojiNamed: name)
            avatarStickers[item.id] = makeStickerItems(from: names, prefix: item.id)
            
        case .randomMemoji:
            let names = AvatarKitBridge.shared.availableStickerNames(forAnimojiNamed: nil)
            avatarStickers[item.id] = makeStickerItems(from: names, prefix: item.id)
        }
    }
    
    private func makeStickerItems(from names: [String], prefix: String) -> [StickerItem] {
        names.map { name in
            let meta = AvatarDatabaseReader.shared.metadata(forStickerName: name)
            return StickerItem(
                id: "\(prefix)_\(name)",
                name: name,
                localizedTitle: meta.title,
                category: meta.category,
                emoji: meta.emoji
            )
        }
    }
    
    // MARK: - Creation & Editing
    
    @MainActor
    private func startCreatingNewMemoji() {
        guard let newAvatar = MemojiCustomizer.shared.createNeutralMemoji()
                ?? AvatarKitBridge.shared.createRandomMemoji() else {
            return
        }
        
        editorTargetAvatar = newAvatar
        editorTargetName = "My Memoji \(customMemojis.count + 1)"
        editorTargetItem = nil
        isNewMemoji = true
        isShowingEditor = true
    }
    
    @MainActor
    private func startEditingMemoji(item: AvatarItem) {
        ensureAvatarLoaded(forId: item.id)
        guard let avatar = avatarObjects[item.id]
                ?? MemojiCustomizer.shared.createNeutralMemoji() else {
            return
        }
        
        // Clone so edits can be discarded if canceled
        let editableCopy = AvatarKitBridge.shared.cloneAvatar(avatar) ?? avatar
        editorTargetAvatar = editableCopy
        editorTargetName = item.displayName
        editorTargetItem = item
        isNewMemoji = false
        isShowingEditor = true
    }
    
    @MainActor
    private func handleEditorSave(name: String, savedAvatar: AnyObject) {
        guard let data = AvatarKitBridge.shared.dataRepresentation(for: savedAvatar) else {
            isShowingEditor = false
            return
        }
        
        if let existing = editorTargetItem {
            // Updating existing item
            switch existing.sourceType {
            case .customMemoji(let id):
                let updated = AvatarDatabaseReader.shared.saveCustomMemoji(name: name, data: data, existingId: id)
                if let idx = customMemojis.firstIndex(where: { $0.id == id }) {
                    customMemojis[idx] = updated
                }
                avatarObjects[id] = savedAvatar
                selectedAvatarId = id
                
            case .userMemoji(let uuid):
                _ = AvatarDatabaseReader.shared.updateUserMemojiInSystemDatabase(uuid: uuid, data: data)
                if let idx = userMemojis.firstIndex(where: { $0.id == existing.id }) {
                    userMemojis[idx].rawData = data
                    userMemojis[idx].displayName = name
                }
                avatarObjects[existing.id] = savedAvatar
                selectedAvatarId = existing.id
                
            case .randomMemoji:
                let newItem = AvatarDatabaseReader.shared.saveCustomMemoji(name: name, data: data)
                customMemojis.insert(newItem, at: 0)
                avatarObjects[newItem.id] = savedAvatar
                loadStickers(for: newItem)
                selectedAvatarId = newItem.id
                
            case .builtinAnimoji:
                break
            }
        } else {
            // Brand new Memoji created in Studio
            let newItem = AvatarDatabaseReader.shared.saveCustomMemoji(name: name, data: data)
            customMemojis.insert(newItem, at: 0)
            avatarObjects[newItem.id] = savedAvatar
            loadStickers(for: newItem)
            selectedAvatarId = newItem.id
        }
        
        isShowingEditor = false
        
        // Trigger detail view refresh
        let savedId = selectedAvatarId
        selectedAvatarId = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            selectedAvatarId = savedId
        }
    }
    
    @MainActor
    private func deleteCustomMemoji(item: AvatarItem) {
        _ = AvatarDatabaseReader.shared.deleteCustomMemoji(id: item.id)
        customMemojis.removeAll { $0.id == item.id }
        avatarObjects.removeValue(forKey: item.id)
        avatarStickers.removeValue(forKey: item.id)
        
        if selectedAvatarId == item.id {
            selectedAvatarId = customMemojis.first?.id ?? userMemojis.first?.id ?? builtinAnimojis.first?.id
            if let nextId = selectedAvatarId {
                ensureAvatarLoaded(forId: nextId)
            }
        }
    }
    
    // MARK: - Actions
    
    @MainActor
    private func addRandomMemoji() {
        guard let rand = AvatarKitBridge.shared.createRandomMemoji() else { return }
        let seed = UUID()
        let id = "random_\(seed.uuidString)"
        let count = randomMemojis.count + 1
        
        let item = AvatarItem(
            id: id,
            displayName: "Random Avatar \(count)",
            sourceType: .randomMemoji(seed: seed)
        )
        
        avatarObjects[id] = rand
        randomMemojis.append(item)
        loadStickers(for: item)
        selectedAvatarId = id
    }
    
    @MainActor
    private func randomizeCurrentMemoji(item: AvatarItem) {
        // Animojis cannot be randomized — generate a new random Memoji instead
        if case .builtinAnimoji = item.sourceType {
            addRandomMemoji()
            return
        }
        
        guard let avatar = avatarObjects[item.id] else { return }
        let randSel = NSSelectorFromString("randomize")
        guard (avatar as AnyObject).responds(to: randSel) else { return }
        _ = (avatar as AnyObject).perform(randSel)
        
        // Force the 3D view to re-render by briefly niling the selection
        let savedId = selectedAvatarId
        selectedAvatarId = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            selectedAvatarId = savedId
        }
    }
}
