import SwiftUI
import AppKit

public struct ContentView: View {
    @State private var userMemojis: [AvatarItem] = []
    @State private var builtinAnimojis: [AvatarItem] = []
    @State private var randomMemojis: [AvatarItem] = []
    @State private var selectedAvatarId: String?
    
    // In-memory cache for live AVTAvatar/AVTAnimoji instances
    @State private var avatarObjects: [String: AnyObject] = [:]
    @State private var avatarStickers: [String: [StickerItem]] = [:]
    @State private var isLoading: Bool = true
    
    public init() {}
    
    public var selectedAvatarItem: AvatarItem? {
        if let id = selectedAvatarId {
            if let item = userMemojis.first(where: { $0.id == id }) { return item }
            if let item = randomMemojis.first(where: { $0.id == id }) { return item }
            if let item = builtinAnimojis.first(where: { $0.id == id }) { return item }
        }
        return userMemojis.first ?? builtinAnimojis.first
    }
    
    public var body: some View {
        NavigationSplitView {
            SidebarView(
                selectedAvatarId: $selectedAvatarId,
                userMemojis: userMemojis,
                builtinAnimojis: builtinAnimojis,
                randomMemojis: randomMemojis,
                onAddRandomMemoji: addRandomMemoji,
                onRefreshRequested: reloadData
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
        } detail: {
            if let current = selectedAvatarItem {
                AvatarDetailView(
                    avatarItem: current,
                    avatarObject: avatarObjects[current.id],
                    stickers: avatarStickers[current.id] ?? [],
                    onRandomizeRequested: {
                        randomizeCurrentMemoji(item: current)
                    }
                )
                .id(current.id)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading Apple Memoji system...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            loadInitialData()
        }
        .onChange(of: selectedAvatarId) { _, newId in
            if let id = newId {
                ensureAvatarLoaded(forId: id)
            }
        }
    }
    
    // MARK: - Data Loading
    
    private func loadInitialData() {
        isLoading = true
        
        // 1. User Memojis from Apple SQLite database
        let dbUsers = AvatarDatabaseReader.shared.fetchUserMemojis()
        self.userMemojis = dbUsers
        
        // 2. Apple built-in Animojis from AvatarKit
        let names = AvatarKitBridge.shared.animojiNames()
        self.builtinAnimojis = names.map { name in
            AvatarItem(
                id: "animoji_\(name)",
                displayName: name,
                sourceType: .builtinAnimoji(name: name)
            )
        }
        
        // Select first available avatar
        if selectedAvatarId == nil {
            selectedAvatarId = dbUsers.first?.id ?? builtinAnimojis.first?.id
        }
        
        if let firstId = selectedAvatarId {
            ensureAvatarLoaded(forId: firstId)
        }
        
        isLoading = false
    }
    
    private func reloadData() {
        let currentId = selectedAvatarId
        loadInitialData()
        if let id = currentId {
            selectedAvatarId = id
            ensureAvatarLoaded(forId: id)
        }
    }
    
    private func ensureAvatarLoaded(forId id: String) {
        // Find item
        guard let item = userMemojis.first(where: { $0.id == id }) ??
                        randomMemojis.first(where: { $0.id == id }) ??
                        builtinAnimojis.first(where: { $0.id == id }) else {
            return
        }
        
        // 1. Load 3D AVTAvatar instance if not already cached
        if avatarObjects[id] == nil {
            switch item.sourceType {
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
        
        // 2. Load Stickers list
        if avatarStickers[id] == nil {
            loadStickers(for: item)
        }
    }
    
    private func loadStickers(for item: AvatarItem) {
        switch item.sourceType {
        case .userMemoji(let uuid):
            // Check disk for high-res cached PNGs
            let diskStickers = AvatarDatabaseReader.shared.findCachedStickers(forUUID: uuid)
            if !diskStickers.isEmpty {
                avatarStickers[item.id] = diskStickers
            } else {
                // Generate sticker configs from AvatarKit
                let names = AvatarKitBridge.shared.availableStickerNames(forAnimojiNamed: nil)
                avatarStickers[item.id] = names.map { name in
                    let meta = AvatarDatabaseReader.shared.metadata(forStickerName: name)
                    return StickerItem(
                        id: "\(item.id)_\(name)",
                        name: name,
                        localizedTitle: meta.title,
                        category: meta.category,
                        emoji: meta.emoji
                    )
                }
            }
            
        case .builtinAnimoji(let name):
            let names = AvatarKitBridge.shared.availableStickerNames(forAnimojiNamed: name)
            avatarStickers[item.id] = names.map { sName in
                let meta = AvatarDatabaseReader.shared.metadata(forStickerName: sName)
                return StickerItem(
                    id: "\(item.id)_\(sName)",
                    name: sName,
                    localizedTitle: meta.title,
                    category: meta.category,
                    emoji: meta.emoji
                )
            }
            
        case .randomMemoji:
            let names = AvatarKitBridge.shared.availableStickerNames(forAnimojiNamed: nil)
            avatarStickers[item.id] = names.map { sName in
                let meta = AvatarDatabaseReader.shared.metadata(forStickerName: sName)
                return StickerItem(
                    id: "\(item.id)_\(sName)",
                    name: sName,
                    localizedTitle: meta.title,
                    category: meta.category,
                    emoji: meta.emoji
                )
            }
        }
    }
    
    // MARK: - Actions
    
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
    
    private func randomizeCurrentMemoji(item: AvatarItem) {
        if case .builtinAnimoji = item.sourceType {
            // Builtin animojis cannot be randomized, create a random Memoji instead
            addRandomMemoji()
            return
        }
        
        if let avatar = avatarObjects[item.id] {
            let randSel = NSSelectorFromString("randomize")
            if (avatar as AnyObject).responds(to: randSel) {
                _ = (avatar as AnyObject).perform(randSel)
                // Force reload view by updating id
                let currentId = selectedAvatarId
                selectedAvatarId = nil
                DispatchQueue.main.async {
                    selectedAvatarId = currentId
                }
            }
        }
    }
}
