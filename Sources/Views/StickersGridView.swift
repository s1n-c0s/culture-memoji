import SwiftUI
import AppKit

public struct StickersGridView: View {
    public let stickers: [StickerItem]
    public let avatar: AnyObject?
    public let isAnimoji: Bool
    public let animojiName: String?
    public let onSelectPose: (String) -> Void
    
    @State private var searchText: String = ""
    @State private var selectedCategory: StickerCategory = .all
    @State private var exportStickerTarget: (sticker: StickerItem, image: NSImage)?
    @State private var showBatchExportAlert: Bool = false
    @State private var batchExportCount: Int = 0
    @State private var isBatchExporting: Bool = false
    
    private let columns = [
        GridItem(.adaptive(minimum: 125, maximum: 160), spacing: 14)
    ]
    
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
    
    public var filteredStickers: [StickerItem] {
        stickers.filter { sticker in
            let matchesCategory = selectedCategory == .all || sticker.category == selectedCategory
            let matchesSearch = searchText.isEmpty ||
                sticker.localizedTitle.localizedCaseInsensitiveContains(searchText) ||
                sticker.name.localizedCaseInsensitiveContains(searchText) ||
                sticker.emoji.contains(searchText)
            return matchesCategory && matchesSearch
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Search and Filter Bar
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    // Search field
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search \(stickers.count) sticker poses, emotions, gestures...", text: $searchText)
                            .textFieldStyle(.plain)
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    
                    // Batch Export All Button
                    Button(action: startBatchExport) {
                        Label(isBatchExporting ? "Exporting..." : "Export All (\(stickers.count))", systemImage: "arrow.down.doc.fill")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .disabled(stickers.isEmpty || isBatchExporting)
                }
                
                // Category Pills
                HStack(spacing: 8) {
                    ForEach(StickerCategory.allCases) { cat in
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedCategory = cat
                            }
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: cat.iconName)
                                    .font(.system(size: 10))
                                Text(cat.rawValue)
                                    .font(.system(size: 11, weight: selectedCategory == cat ? .bold : .medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(selectedCategory == cat ? Color.accentColor : Color(nsColor: .controlBackgroundColor).opacity(0.7))
                            .foregroundColor(selectedCategory == cat ? .white : .primary)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    
                    Text("\(filteredStickers.count) stickers")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Stickers Grid Scroll
            ScrollView {
                if filteredStickers.isEmpty {
                    VStack(spacing: 12) {
                        Spacer(minLength: 60)
                        Image(systemName: "sparkles")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No stickers match '\(searchText)'")
                            .font(.headline)
                        Text("Try searching for happy, love, thumbs up, wink, peace, or party")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
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
                                }
                            )
                        }
                    }
                    .padding(20)
                }
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
            Text("Successfully exported \(batchExportCount) stickers to the selected folder.")
        }
    }
    
    private func startBatchExport() {
        guard !stickers.isEmpty else { return }
        isBatchExporting = true
        
        // Prepare images
        var exportList: [(name: String, image: NSImage)] = []
        for sticker in stickers {
            if let url = sticker.localFileURL, let img = NSImage(contentsOf: url) {
                exportList.append((sticker.name, img))
            } else if let avatar = avatar, let snap = AvatarKitBridge.shared.snapshot(avatar: avatar, size: CGSize(width: 512, height: 512)) {
                exportList.append((sticker.name, snap))
            }
        }
        
        StickerExportManager.shared.batchExport(
            stickers: exportList,
            targetSize: 512,
            background: .transparent,
            format: .png
        ) { count in
            self.isBatchExporting = false
            self.batchExportCount = count
            if count > 0 {
                self.showBatchExportAlert = true
            }
        }
    }
}

private struct IdentifiableExport: Identifiable {
    let id = UUID()
    let sticker: StickerItem
    let image: NSImage
}
