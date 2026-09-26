import SwiftUI
import AppKit

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
    
    // Editor sheet state
    @State private var isShowingEditor: Bool = false
    @State private var editorTargetAvatar: AnyObject? = nil
    @State private var editorTargetName: String = "My Memoji"
    @State private var editorTargetItem: AvatarItem? = nil
    @State private var isNewMemoji: Bool = false
    @State private var toastMessage: String? = nil
    
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
    
    public var body: some View {
        HStack(spacing: 0) {
            // Left Sidebar
            SidebarView(
                selectedAvatarId: $selectedAvatarId,
                activePoseName: $activePoseName,
                currentTab: $currentTab,
                viewMode: $viewMode,
                userMemojis: userMemojis,
                customMemojis: customMemojis,
                builtinAnimojis: builtinAnimojis,
                randomMemojis: randomMemojis,
                avatarObjects: avatarObjects,
                stickersForSelectedAvatar: selectedAvatarId != nil ? (avatarStickers[selectedAvatarId!] ?? []) : [],
                onAddNewMemoji: startCreatingNewMemoji,
                onEditMemoji: startEditingMemoji,
                onDuplicateMemoji: duplicateMemoji,
                onDeleteCustomMemoji: deleteCustomMemoji,
                onRenameMemoji: renameMemoji,
                onRefreshRequested: reloadData,
                onCopySticker: copyStickerToClipboard
            )
            .frame(width: 330)
            
            // Subtle vertical divider between sidebar and main area
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)
            
            // Right Main Stage
            ZStack {
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
                        avatarObject: avatarObjects[current.id],
                        activePoseName: activePoseName,
                        onResetPoseAndCamera: {
                            activePoseName = nil
                        },
                        onEditRequested: {
                            startEditingMemoji(item: current)
                        },
                        onRenameRequested: { newName in
                            renameAvatar(item: current, newName: newName)
                        },
                        onCopiedNotification: { msg in
                            showToast(msg)
                        }
                    )
                    .id(current.id)
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
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.stageBackground)
                }
                
                // Floating App Toast Notification HUD
                if let toast = toastMessage {
                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 14))
                            Text(toast)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(.ultraThickMaterial)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
                        .padding(.bottom, 24)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                activePoseName = nil
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
                displayName: name.capitalized,
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
        avatarObjects.removeAll()
        avatarStickers.removeAll()
        ThumbnailCache.shared.clear()
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
        let allNames: [String]
        let diskStickers: [StickerItem]
        let animojiName: String?
        
        switch item.sourceType {
        case .customMemoji:
            animojiName = nil
            allNames = AvatarKitBridge.shared.availableStickerNames(forAnimojiNamed: nil)
            diskStickers = AvatarDatabaseReader.shared.findAppCachedStickers(forAvatarId: item.id)
            
        case .userMemoji(let uuid):
            animojiName = nil
            allNames = AvatarKitBridge.shared.availableStickerNames(forAnimojiNamed: nil)
            diskStickers = AvatarDatabaseReader.shared.findCachedStickers(forUUID: uuid)
            
        case .builtinAnimoji(let name):
            animojiName = name
            allNames = AvatarKitBridge.shared.availableStickerNames(forAnimojiNamed: name)
            diskStickers = AvatarDatabaseReader.shared.findCachedStickers(forAnimojiNamed: name)
            
        case .randomMemoji:
            animojiName = nil
            allNames = AvatarKitBridge.shared.availableStickerNames(forAnimojiNamed: nil)
            diskStickers = AvatarDatabaseReader.shared.findAppCachedStickers(forAvatarId: item.id)
        }
        
        let merged = mergeStickerItems(diskStickers: diskStickers, allNames: allNames, prefix: item.id)
        avatarStickers[item.id] = merged
        
        // 1. Pre-warm sticker configurations in background so previewing poses is instant
        AvatarKitBridge.shared.prewarmStickerConfigurations(forAnimojiNamed: animojiName, stickerNames: allNames)
        
        // 2. Pre-warm top thumbnails in background so switching to Emote tab is instant
        ThumbnailCache.shared.prewarmEmoteThumbnails(
            stickers: merged,
            avatarObject: avatarObjects[item.id],
            isAnimoji: animojiName != nil,
            animojiName: animojiName
        )
    }
    
    private func mergeStickerItems(diskStickers: [StickerItem], allNames: [String], prefix: String) -> [StickerItem] {
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
        
        let editableCopy = AvatarKitBridge.shared.cloneAvatar(avatar) ?? avatar
        editorTargetAvatar = editableCopy
        editorTargetName = item.displayName
        editorTargetItem = item
        isNewMemoji = false
        isShowingEditor = true
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
    private func handleEditorSave(name: String, savedAvatar: AnyObject) {
        guard let data = AvatarKitBridge.shared.dataRepresentation(for: savedAvatar) else {
            isShowingEditor = false
            return
        }
        
        AvatarKitBridge.shared.clearPosedStickerCache()
        ThumbnailCache.shared.clear()
        
        if let existing = editorTargetItem {
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
            customMemojis.insert(newItem, at: 0)
            avatarObjects[newItem.id] = savedAvatar
            loadStickers(for: newItem)
            selectedAvatarId = newItem.id
            showToast("Created Memoji '\(name)'")
        }
        
        isShowingEditor = false
        
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
        
        showToast("Deleted '\(item.displayName)'")
        
        if selectedAvatarId == item.id {
            selectedAvatarId = customMemojis.first?.id ?? userMemojis.first?.id ?? builtinAnimojis.first?.id
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
            withAnimation {
                if toastMessage == text {
                    toastMessage = nil
                }
            }
        }
    }
}
