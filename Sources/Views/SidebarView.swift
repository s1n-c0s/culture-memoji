import SwiftUI
import AppKit

public struct SidebarView: View {
    @Binding public var selectedAvatarId: String?
    public let userMemojis: [AvatarItem]
    public let customMemojis: [AvatarItem]
    public let builtinAnimojis: [AvatarItem]
    public let randomMemojis: [AvatarItem]
    public let onAddNewMemoji: () -> Void
    public let onEditMemoji: (AvatarItem) -> Void
    public let onDuplicateMemoji: ((AvatarItem) -> Void)?
    public let onDeleteCustomMemoji: (AvatarItem) -> Void
    public let onAddRandomMemoji: () -> Void
    public let onRefreshRequested: () -> Void
    
    @State private var filterText: String = ""
    
    public init(
        selectedAvatarId: Binding<String?>,
        userMemojis: [AvatarItem],
        customMemojis: [AvatarItem] = [],
        builtinAnimojis: [AvatarItem],
        randomMemojis: [AvatarItem],
        onAddNewMemoji: @escaping () -> Void,
        onEditMemoji: @escaping (AvatarItem) -> Void,
        onDuplicateMemoji: ((AvatarItem) -> Void)? = nil,
        onDeleteCustomMemoji: @escaping (AvatarItem) -> Void,
        onAddRandomMemoji: @escaping () -> Void,
        onRefreshRequested: @escaping () -> Void
    ) {
        self._selectedAvatarId = selectedAvatarId
        self.userMemojis = userMemojis
        self.customMemojis = customMemojis
        self.builtinAnimojis = builtinAnimojis
        self.randomMemojis = randomMemojis
        self.onAddNewMemoji = onAddNewMemoji
        self.onEditMemoji = onEditMemoji
        self.onDuplicateMemoji = onDuplicateMemoji
        self.onDeleteCustomMemoji = onDeleteCustomMemoji
        self.onAddRandomMemoji = onAddRandomMemoji
        self.onRefreshRequested = onRefreshRequested
    }
    
    private var filteredCustom: [AvatarItem] {
        filter(customMemojis)
    }
    
    private var filteredUser: [AvatarItem] {
        filter(userMemojis)
    }
    
    private var filteredAnimojis: [AvatarItem] {
        filter(builtinAnimojis)
    }
    
    private var filteredRandom: [AvatarItem] {
        filter(randomMemojis)
    }
    
    private func filter(_ items: [AvatarItem]) -> [AvatarItem] {
        let q = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return items }
        return items.filter { $0.displayName.localizedCaseInsensitiveContains(q) || $0.id.localizedCaseInsensitiveContains(q) }
    }
    
    public var body: some View {
        List(selection: $selectedAvatarId) {
            // Custom Studio Memojis Section
            if !filteredCustom.isEmpty || filterText.isEmpty {
                Section(header: HStack {
                    Text("Studio Memojis")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    if !customMemojis.isEmpty {
                        Text("\(customMemojis.count)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }) {
                    if customMemojis.isEmpty && filterText.isEmpty {
                        Button(action: onAddNewMemoji) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 11))
                                Text("Create your first Memoji...")
                                    .font(.system(size: 11.5))
                            }
                            .foregroundColor(.secondary)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    } else {
                        ForEach(filteredCustom) { item in
                            NavigationLink(value: item.id) {
                                avatarRow(item: item, iconName: "sparkles", tintColor: .purple, subtitle: "Studio Model")
                            }
                            .contextMenu {
                                Button {
                                    onEditMemoji(item)
                                } label: {
                                    Label("Customize Memoji...", systemImage: "paintbrush")
                                }
                                
                                if let onDuplicate = onDuplicateMemoji {
                                    Button {
                                        onDuplicate(item)
                                    } label: {
                                        Label("Duplicate Memoji", systemImage: "doc.on.doc")
                                    }
                                }
                                
                                Divider()
                                
                                Button(role: .destructive) {
                                    onDeleteCustomMemoji(item)
                                } label: {
                                    Label("Delete Memoji", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            
            // User System Memojis Section
            if !filteredUser.isEmpty || filterText.isEmpty {
                Section(header: HStack {
                    Text("System Memojis")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    if !userMemojis.isEmpty {
                        Text("\(userMemojis.count)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }) {
                    if userMemojis.isEmpty && filterText.isEmpty {
                        Text("No personal Memojis found")
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(filteredUser) { item in
                            NavigationLink(value: item.id) {
                                avatarRow(item: item, iconName: "person.fill", tintColor: .accentColor, subtitle: "\(item.cachedStickerCount) stickers")
                            }
                            .contextMenu {
                                Button {
                                    onEditMemoji(item)
                                } label: {
                                    Label("Customize Memoji...", systemImage: "paintbrush")
                                }
                                
                                if let onDuplicate = onDuplicateMemoji {
                                    Button {
                                        onDuplicate(item)
                                    } label: {
                                        Label("Duplicate as Custom Memoji", systemImage: "doc.on.doc")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            // Randomly Generated Custom Memojis Section
            if !filteredRandom.isEmpty {
                Section(header: HStack {
                    Text("Generated Memojis")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(randomMemojis.count)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.8))
                }) {
                    ForEach(filteredRandom) { item in
                        NavigationLink(value: item.id) {
                            avatarRow(item: item, iconName: "dice.fill", tintColor: .orange, subtitle: "Randomized")
                        }
                        .contextMenu {
                            Button {
                                onEditMemoji(item)
                            } label: {
                                Label("Customize Memoji...", systemImage: "paintbrush")
                            }
                            
                            if let onDuplicate = onDuplicateMemoji {
                                Button {
                                    onDuplicate(item)
                                } label: {
                                    Label("Save as Custom Memoji", systemImage: "square.and.arrow.down")
                                }
                            }
                        }
                    }
                }
            }
            
            // Apple Animojis Section
            if !filteredAnimojis.isEmpty || filterText.isEmpty {
                Section(header: HStack {
                    Text("Apple Animojis")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(builtinAnimojis.count)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.8))
                }) {
                    ForEach(filteredAnimojis) { item in
                        NavigationLink(value: item.id) {
                            HStack(spacing: 9) {
                                Text(emojiForAnimoji(item.displayName))
                                    .font(.system(size: 14))
                                    .frame(width: 26, height: 26)
                                    .background(Color.primary.opacity(0.05))
                                    .clipShape(Circle())
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.displayName.capitalized)
                                        .font(.system(size: 12.5, weight: .medium))
                                        .lineLimit(1)
                                    Text("Apple Animoji")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                Spacer(minLength: 4)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $filterText, placement: .sidebar, prompt: "Search Memojis...")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(action: onAddNewMemoji) {
                        Label("New Studio Memoji", systemImage: "sparkles")
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    
                    Button(action: onAddRandomMemoji) {
                        Label("Random Memoji", systemImage: "dice")
                    }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    
                    Divider()
                    
                    Button(action: openSystemMemojiEditor) {
                        Label("System Settings Memojis...", systemImage: "gearshape")
                    }
                    
                    Button(action: onRefreshRequested) {
                        Label("Reload Database", systemImage: "arrow.clockwise")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .help("Create or generate Memoji (⌘N)")
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(AvatarKitBridge.shared.isAvailable ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(AvatarKitBridge.shared.isAvailable ? "Ready" : "Cache")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: onRefreshRequested) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Reload system database")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
    }
    
    // MARK: - Row View Helper
    
    private func avatarRow(item: AvatarItem, iconName: String, tintColor: Color, subtitle: String) -> some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(tintColor.opacity(0.12))
                    .frame(width: 26, height: 26)
                
                Image(systemName: iconName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(tintColor)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            Spacer(minLength: 4)
        }
        .padding(.vertical, 3)
    }
    
    // MARK: - Emoji Lookup
    
    private func emojiForAnimoji(_ name: String) -> String {
        switch name.lowercased() {
        case "fox": return "🦊"
        case "panda": return "🐼"
        case "unicorn": return "🦄"
        case "dragon": return "🐲"
        case "lion": return "🦁"
        case "bear": return "🐻"
        case "tiger": return "🐯"
        case "koala": return "🐨"
        case "trex": return "🦖"
        case "ghost": return "👻"
        case "robot": return "🤖"
        case "alien": return "👽"
        case "cat": return "🐱"
        case "dog": return "🐶"
        case "monkey": return "🐵"
        case "boar": return "🐗"
        case "pig": return "🐷"
        case "rabbit": return "🐰"
        case "chicken": return "🐔"
        case "cow": return "🐮"
        case "giraffe": return "🦒"
        case "shark": return "🦈"
        case "owl": return "🦉"
        case "mouse": return "🐭"
        case "octopus": return "🐙"
        case "skull": return "💀"
        case "poo": return "💩"
        default: return "🎭"
        }
    }
    
    private func openSystemMemojiEditor() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Users-and-Groups-Settings.extension") {
            NSWorkspace.shared.open(url)
        } else if let msgs = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.MobileSMS") {
            NSWorkspace.shared.openApplication(at: msgs, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
