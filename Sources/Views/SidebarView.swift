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
        VStack(spacing: 0) {
            // Header Top Bar: Filter & New Button
            VStack(spacing: 8) {
                // "+ New Memoji Studio" Hero Button
                Button(action: onAddNewMemoji) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text("New Memoji")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        LinearGradient(
                            colors: [Color.accentColor, Color.purple.opacity(0.85)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: Color.accentColor.opacity(0.25), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .help("Create a brand-new Memoji in 3D Studio (⌘N)")
                
                // Sidebar Filter TextField
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 11))
                    TextField("Filter avatars...", text: $filterText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                    if !filterText.isEmpty {
                        Button(action: { filterText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)
            
            Divider()
            
            // Avatar Groups List
            List(selection: $selectedAvatarId) {
                // Custom Studio Memojis Section
                if !filteredCustom.isEmpty || filterText.isEmpty {
                    Section(header: HStack {
                        Label("Studio Memojis", systemImage: "sparkles")
                            .font(.system(size: 11, weight: .bold))
                        Spacer()
                        Text("\(customMemojis.count)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }) {
                        if customMemojis.isEmpty {
                            Button(action: onAddNewMemoji) {
                                HStack(spacing: 8) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 11))
                                    Text("Create your first Memoji...")
                                        .font(.caption)
                                }
                                .foregroundColor(.secondary)
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        } else {
                            ForEach(filteredCustom) { item in
                                NavigationLink(value: item.id) {
                                    avatarRow(item: item, iconName: "person.crop.circle.badge.checkmark", gradient: [Color.purple, Color.indigo], subtitle: "Custom 3D Model")
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
                        Label("System Memojis", systemImage: "person.crop.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                        Spacer()
                        Text("\(userMemojis.count)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }) {
                        if userMemojis.isEmpty && filterText.isEmpty {
                            Text("No personal Memojis found in macOS")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 4)
                        } else {
                            ForEach(filteredUser) { item in
                                NavigationLink(value: item.id) {
                                    avatarRow(item: item, iconName: "person.fill", gradient: [Color.blue, Color.cyan], subtitle: "\(item.cachedStickerCount) stickers")
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
                        Label("Generated Memojis", systemImage: "dice.fill")
                            .font(.system(size: 11, weight: .bold))
                        Spacer()
                        Text("\(randomMemojis.count)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }) {
                        ForEach(filteredRandom) { item in
                            NavigationLink(value: item.id) {
                                avatarRow(item: item, iconName: "sparkles", gradient: [Color.orange, Color.pink], subtitle: "Randomized 3D")
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
                        Label("Apple Animojis", systemImage: "pawprint.fill")
                            .font(.system(size: 11, weight: .bold))
                        Spacer()
                        Text("\(builtinAnimojis.count)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }) {
                        ForEach(filteredAnimojis) { item in
                            NavigationLink(value: item.id) {
                                HStack(spacing: 10) {
                                    Text(emojiForAnimoji(item.displayName))
                                        .font(.system(size: 15))
                                        .frame(width: 24, height: 24)
                                        .background(Color.primary.opacity(0.06))
                                        .clipShape(Circle())
                                    
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.displayName.capitalized)
                                            .font(.system(size: 12, weight: .medium))
                                        Text("Apple Animoji")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
                
                // Quick Tools Section
                if filterText.isEmpty {
                    Section(header: Label("Quick Actions", systemImage: "wrench.and.screwdriver.fill")
                        .font(.system(size: 11, weight: .bold))) {
                        Button(action: onAddNewMemoji) {
                            Label("New Memoji Studio...", systemImage: "paintbrush.fill")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 2)
                        
                        Button(action: onAddRandomMemoji) {
                            Label("Quick Random Memoji", systemImage: "dice.fill")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 2)
                        
                        Button(action: openSystemMemojiEditor) {
                            Label("System Settings Memojis...", systemImage: "slider.horizontal.3")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 2)
                        .help("Opens macOS System Settings or Messages to customize Memojis")
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .safeAreaInset(edge: .bottom) {
            // Footer status bar
            VStack(spacing: 6) {
                Divider()
                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(AvatarKitBridge.shared.isAvailable ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)
                        Text(AvatarKitBridge.shared.isAvailable ? "AvatarKit Active" : "Cache Mode")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: onRefreshRequested) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help("Reload system database")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
    
    // MARK: - Row View Helper
    
    private func avatarRow(item: AvatarItem, iconName: String, gradient: [Color], subtitle: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                LinearGradient(
                    colors: gradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(width: 24, height: 24)
                .clipShape(Circle())
                
                Image(systemName: iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            Spacer(minLength: 4)
        }
        .padding(.vertical, 2)
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
