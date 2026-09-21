import SwiftUI
import AppKit

public enum GridDensity: String, CaseIterable, Identifiable {
    case compact = "Compact"
    case standard = "Standard"
    case large = "Large"
    
    public var id: String { rawValue }
    
    public var minWidth: CGFloat {
        switch self {
        case .compact: return 100
        case .standard: return 130
        case .large: return 175
        }
    }
    
    public var iconName: String {
        switch self {
        case .compact: return "square.grid.3x3.fill"
        case .standard: return "square.grid.2x2.fill"
        case .large: return "square.fill"
        }
    }
}

public struct StickersGridView: View {
    public let stickers: [StickerItem]
    public let avatar: AnyObject?
    public let isAnimoji: Bool
    public let animojiName: String?
    public let onSelectPose: (String) -> Void
    
    @State private var searchText: String = ""
    @State private var selectedCategory: StickerCategory = .all
    @State private var gridDensity: GridDensity = .standard
    @State private var exportStickerTarget: (sticker: StickerItem, image: NSImage)?
    @State private var showBatchExportAlert: Bool = false
    @State private var batchExportCount: Int = 0
    @State private var isBatchExporting: Bool = false
    @State private var toastMessage: String? = nil
    
    public init(
        stickers: [StickerItem],
        avatar: AnyObject?,
        isAnimoji: Bool = false,
        animojiName: String? = nil,
        onSelectPose: @escaping (String) -> Void
    ) {
        self.stickers = stickers
        self.avatar = avatar
        self.isAnimoji = isAnimoji
        self.animojiName = animojiName
        self.onSelectPose = onSelectPose
    }
    
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: gridDensity.minWidth, maximum: gridDensity.minWidth + 35), spacing: 14)]
    }
    
    public var filteredStickers: [StickerItem] {
        stickers.filter { sticker in
            let matchesCategory = selectedCategory == .all || sticker.category == selectedCategory
            let matchesSearch = matchesSearchQuery(sticker, query: searchText)
            return matchesCategory && matchesSearch
        }
    }
    
    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Search, Density & Filter Bar
                headerControlBar
                
                Divider()
                
                // Stickers Grid Scroll Area
                gridContentArea
            }
            
            // Floating Toast Notification HUD
            if let toast = toastMessage {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 13))
                        Text(toast)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThickMaterial)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                    .padding(.bottom, 20)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(item: Binding(
            get: { exportStickerTarget.map { IdentifiableExport(sticker: $0.sticker, image: $0.image) } },
            set: { _ in exportStickerTarget = nil }
        )) { target in
            ExportModalView(sticker: target.sticker, image: target.image)
        }
        .alert("Batch Export Completed", isPresented: $showBatchExportAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Successfully exported \(batchExportCount) stickers to your selected folder.")
        }
    }
    
    // MARK: - Header Controls
    
    private var headerControlBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                // Search field with clear button
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                    TextField("Search \(stickers.count) sticker poses, emotions, gestures...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                
                // Density Picker
                Picker("", selection: $gridDensity) {
                    ForEach(GridDensity.allCases) { density in
                        Image(systemName: density.iconName).tag(density)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 90)
                .help("Adjust sticker grid size")
                
                // Batch Export Button
                Button(action: startBatchExport) {
                    HStack(spacing: 5) {
                        Image(systemName: isBatchExporting ? "arrow.triangle.2.circlepath" : "arrow.down.doc.fill")
                            .rotationEffect(.degrees(isBatchExporting ? 360 : 0))
                            .animation(isBatchExporting ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isBatchExporting)
                        Text(isBatchExporting ? "Exporting..." : "Export All (\(stickers.count))")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .disabled(stickers.isEmpty || isBatchExporting)
                .help("Export all stickers to a folder as transparent PNGs")
            }
            
            // Category Filter Pills with Item Counts
            HStack(spacing: 8) {
                ForEach(StickerCategory.allCases) { cat in
                    let isSelected = selectedCategory == cat
                    let count = count(for: cat)
                    
                    Button(action: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            selectedCategory = cat
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: cat.iconName)
                                .font(.system(size: 10))
                            Text(cat.rawValue)
                                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                            Text("\(count)")
                                .font(.system(size: 10))
                                .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                        .foregroundColor(isSelected ? .white : .primary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
                
                Text("\(filteredStickers.count) of \(stickers.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Grid Content Area
    
    private var gridContentArea: some View {
        ScrollView {
            if filteredStickers.isEmpty {
                VStack(spacing: 14) {
                    Spacer(minLength: 60)
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.7))
                    Text("No stickers match '\(searchText)'")
                        .font(.headline)
                    Text("Try searching for happy, smile, love, thumbs up, wave, think, or party")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Button("Clear Search") {
                        searchText = ""
                        selectedCategory = .all
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
                    
                    Spacer(minLength: 60)
                }
                .frame(maxWidth: .infinity)
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(filteredStickers) { sticker in
                        StickerCellView(
                            sticker: sticker,
                            avatar: avatar,
                            isAnimoji: isAnimoji,
                            animojiName: animojiName,
                            onSelectPose: onSelectPose,
                            onExportRequest: { item, img in
                                exportStickerTarget = (item, img)
                            },
                            onCopied: { title in
                                showToast("Copied \(title) to clipboard")
                            }
                        )
                    }
                }
                .padding(20)
            }
        }
    }
    
    // MARK: - Helpers & Synonyms
    
    private func count(for category: StickerCategory) -> Int {
        if category == .all {
            return stickers.count
        }
        return stickers.filter { $0.category == category }.count
    }
    
    private func matchesSearchQuery(_ sticker: StickerItem, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return true }
        
        // Direct matching
        if sticker.localizedTitle.localizedCaseInsensitiveContains(q) ||
            sticker.name.localizedCaseInsensitiveContains(q) ||
            sticker.emoji.contains(q) {
            return true
        }
        
        // Semantic keyword synonyms
        let synonyms: [String: [String]] = [
            "love": ["heart", "kiss", "in_love", "three_hearts"],
            "happy": ["smile", "joy", "grin", "celebration", "tears_of_joy", "star_struck"],
            "laugh": ["lol", "tears_of_joy", "happy", "joyful", "wink"],
            "cry": ["crying", "tears", "sad"],
            "sad": ["frown", "crying", "annoyed"],
            "cool": ["smirk", "victory", "sunglasses", "wink", "peace"],
            "tech": ["technologist", "laptop", "code", "developer", "mac"],
            "hand": ["thumbs", "wave", "peace", "fingers", "bump", "clap", "raised", "folded", "heart_hands"],
            "sleep": ["yawn", "sleeping", "zzz"],
            "think": ["thinking", "skeptical", "eyebrow", "head_tilt", "idea", "eureka"],
            "angry": ["pouting", "swearing", "steam", "rage", "censored"],
            "party": ["celebration", "party_horn", "starry"]
        ]
        
        for (keyword, tokens) in synonyms where q.contains(keyword) || keyword.contains(q) {
            for token in tokens {
                if sticker.name.lowercased().contains(token) ||
                    sticker.localizedTitle.lowercased().contains(token) {
                    return true
                }
            }
        }
        
        return false
    }
    
    private func showToast(_ message: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            toastMessage = message
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation {
                if toastMessage == message {
                    toastMessage = nil
                }
            }
        }
    }
    
    private func startBatchExport() {
        guard !stickers.isEmpty else { return }
        isBatchExporting = true
        
        var exportList: [(name: String, image: NSImage)] = []
        for sticker in stickers {
            if let url = sticker.localFileURL, let img = NSImage(contentsOf: url) {
                exportList.append((sticker.name, img))
            }
        }
        
        guard !exportList.isEmpty else {
            isBatchExporting = false
            return
        }
        
        StickerExportManager.shared.batchExport(
            stickers: exportList,
            targetSize: 512,
            background: .transparent,
            format: .png
        ) { @MainActor count in
            isBatchExporting = false
            batchExportCount = count
            if count > 0 {
                showBatchExportAlert = true
            }
        }
    }
}

private struct IdentifiableExport: Identifiable {
    let id = UUID()
    let sticker: StickerItem
    let image: NSImage
}
