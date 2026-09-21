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
        guard let id = selectedAvatarId else {
            return userMemojis.first ?? builtinAnimojis.first
        }
        return userMemojis.first(where: { $0.id == id })
            ?? randomMemojis.first(where: { $0.id == id })
            ?? builtinAnimojis.first(where: { $0.id == id })
            ?? userMemojis.first
            ?? builtinAnimojis.first
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
                    Text("Select a Memoji from the sidebar, or create a random one.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Button("Create Random Memoji") {
                        addRandomMemoji()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        
        // Select first available avatar if nothing selected yet
        if selectedAvatarId == nil {
            selectedAvatarId = dbUsers.first?.id ?? builtinAnimojis.first?.id
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
        guard let item = userMemojis.first(where: { $0.id == id })
                        ?? randomMemojis.first(where: { $0.id == id })
                        ?? builtinAnimojis.first(where: { $0.id == id }) else {
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
        
        // 2. Load sticker list if not cached
        if avatarStickers[id] == nil {
            loadStickers(for: item)
        }
    }
    
    @MainActor
    private func loadStickers(for item: AvatarItem) {
        switch item.sourceType {
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
