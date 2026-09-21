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
    public let onDeleteCustomMemoji: (AvatarItem) -> Void
    public let onAddRandomMemoji: () -> Void
    public let onRefreshRequested: () -> Void
    
    public init(
        selectedAvatarId: Binding<String?>,
        userMemojis: [AvatarItem],
        customMemojis: [AvatarItem] = [],
        builtinAnimojis: [AvatarItem],
        randomMemojis: [AvatarItem],
        onAddNewMemoji: @escaping () -> Void,
        onEditMemoji: @escaping (AvatarItem) -> Void,
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
        self.onDeleteCustomMemoji = onDeleteCustomMemoji
        self.onAddRandomMemoji = onAddRandomMemoji
        self.onRefreshRequested = onRefreshRequested
    }
    
    public var body: some View {
        List(selection: $selectedAvatarId) {
            // Custom Studio Memojis Section
            Section(header: HStack {
                Label("Studio Memojis", systemImage: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                Spacer()
                Button(action: onAddNewMemoji) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help("Create new custom Memoji")
                
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
                    ForEach(customMemojis) { item in
                        NavigationLink(value: item.id) {
                            HStack(spacing: 10) {
                                Image(systemName: "person.crop.circle.badge.checkmark")
                                    .font(.system(size: 14))
                                    .foregroundColor(.purple)
                                    .frame(width: 22, height: 22)
                                    .background(Color.purple.opacity(0.12))
                                    .clipShape(Circle())
                                
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.displayName)
                                        .font(.system(size: 12, weight: .medium))
                                    Text("Custom Studio Memoji")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                            }
                            .padding(.vertical, 2)
                        }
                        .contextMenu {
                            Button {
                                onEditMemoji(item)
                            } label: {
                                Label("Edit Memoji...", systemImage: "pencil")
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
            
            // User Memojis Section
            Section(header: HStack {
                Label("My System Memojis", systemImage: "person.crop.circle.fill")
                    .font(.system(size: 11, weight: .bold))
                Spacer()
                Text("\(userMemojis.count)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }) {
                if userMemojis.isEmpty {
                    Text("No personal Memojis detected in system")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(userMemojis) { item in
                        NavigationLink(value: item.id) {
                            HStack(spacing: 10) {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.blue)
                                    .frame(width: 22, height: 22)
                                    .background(Color.blue.opacity(0.12))
                                    .clipShape(Circle())
                                
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.displayName)
                                        .font(.system(size: 12, weight: .medium))
                                    Text("\(item.cachedStickerCount) stickers")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .contextMenu {
                            Button {
                                onEditMemoji(item)
                            } label: {
                                Label("Customize Memoji...", systemImage: "pencil")
                            }
                        }
                    }
                }
            }
            
            // Randomly Generated Custom Memojis Section
            if !randomMemojis.isEmpty {
                Section(header: Label("Generated Memojis", systemImage: "dice.fill")
                    .font(.system(size: 11, weight: .bold))) {
                    ForEach(randomMemojis) { item in
                        NavigationLink(value: item.id) {
                            HStack(spacing: 10) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 13))
                                    .foregroundColor(.orange)
                                    .frame(width: 22, height: 22)
                                    .background(Color.orange.opacity(0.12))
                                    .clipShape(Circle())
                                
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.displayName)
                                        .font(.system(size: 12, weight: .medium))
                                    Text("Custom 3D model")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .contextMenu {
                            Button {
                                onEditMemoji(item)
                            } label: {
                                Label("Customize Memoji...", systemImage: "pencil")
                            }
                        }
                    }
                }
            }
            
            // Apple Animojis Section
            Section(header: HStack {
                Label("Apple Animojis", systemImage: "pawprint.fill")
                    .font(.system(size: 11, weight: .bold))
                Spacer()
                Text("\(builtinAnimojis.count)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }) {
                ForEach(builtinAnimojis) { item in
                    NavigationLink(value: item.id) {
                        HStack(spacing: 10) {
                            Text(emojiForAnimoji(item.displayName))
                                .font(.system(size: 16))
                                .frame(width: 22, height: 22)
                            
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
            
            // Quick Tools Section
            Section(header: Label("Tools & System", systemImage: "wrench.and.screwdriver.fill")
                .font(.system(size: 11, weight: .bold))) {
                Button(action: onAddNewMemoji) {
                    Label("New Memoji Studio...", systemImage: "paintbrush.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .padding(.vertical, 2)
                
                Button(action: onAddRandomMemoji) {
                    Label("Create Random Memoji", systemImage: "plus.circle.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .padding(.vertical, 2)
                
                Button(action: openSystemMemojiEditor) {
                    Label("Edit Memoji in System...", systemImage: "slider.horizontal.3")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .padding(.vertical, 2)
                .help("Opens macOS System Settings or Messages to customize Memojis")
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            // Footer with status and refresh
            VStack(spacing: 8) {
                Divider()
                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(AvatarKitBridge.shared.isAvailable ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)
                        Text(AvatarKitBridge.shared.isAvailable ? "Apple System AvatarKit" : "System Cache Mode")
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
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
    
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
        // Try opening System Settings Users & Groups
        if let url = URL(string: "x-apple.systempreferences:com.apple.Users-and-Groups-Settings.extension") {
            NSWorkspace.shared.open(url)
        } else if let msgs = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.MobileSMS") {
            NSWorkspace.shared.openApplication(at: msgs, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
