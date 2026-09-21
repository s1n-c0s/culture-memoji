import SwiftUI
import AppKit

public struct StickerCellView: View {
    public let sticker: StickerItem
    public let avatar: AnyObject?
    public let isAnimoji: Bool
    public let animojiName: String?
    public let onSelectPose: (String) -> Void
    public let onExportRequest: (StickerItem, NSImage) -> Void
    
    @State private var isHovered: Bool = false
    @State private var showCopiedAlert: Bool = false
    @State private var loadedImage: NSImage?
    
    public init(
        sticker: StickerItem,
        avatar: AnyObject?,
        isAnimoji: Bool = false,
        animojiName: String? = nil,
        onSelectPose: @escaping (String) -> Void,
        onExportRequest: @escaping (StickerItem, NSImage) -> Void
    ) {
        self.sticker = sticker
        self.avatar = avatar
        self.isAnimoji = isAnimoji
        self.animojiName = animojiName
        self.onSelectPose = onSelectPose
        self.onExportRequest = onExportRequest
    }
    
    public var body: some View {
        VStack(spacing: 8) {
            // Sticker Image Container — tap anywhere to apply the pose to the 3D stage
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(isHovered ? 0.9 : 0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isHovered ? Color.accentColor.opacity(0.6) : Color.gray.opacity(0.15), lineWidth: isHovered ? 2.0 : 1)
                    )
                
                if let img = loadedImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(12)
                } else {
                    ProgressView()
                        .scaleEffect(0.8)
                }
                
                // Copied Notification Overlay
                if showCopiedAlert {
                    VStack {
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Copied!")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .shadow(radius: 4)
                        .padding(.bottom, 8)
                    }
                    .transition(.opacity.combined(with: .scale))
                }
                
                // Hover Action Bar — copy and export shortcuts shown on hover
                if isHovered {
                    VStack {
                        Spacer()
                        
                        HStack(spacing: 6) {
                            // Copy button
                            Button(action: copySticker) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 11))
                                    .padding(5)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .help("Copy transparent PNG to clipboard")
                            
                            // Export button — only enabled when image is loaded
                            Button(action: {
                                if let img = loadedImage {
                                    onExportRequest(sticker, img)
                                }
                            }) {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 11))
                                    .padding(5)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .disabled(loadedImage == nil)
                            .help("Custom export (PNG/JPEG/Background)")
                        }
                        .padding(.bottom, 8)
                    }
                }
            }
            .frame(height: 130)
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .onTapGesture {
                // Clicking the sticker directly applies the 3D pose to the stage
                onSelectPose(sticker.name)
            }
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
            // Drag and Drop — only when image is actually loaded
            .onDrag {
                guard let img = loadedImage else {
                    return NSItemProvider()
                }
                if let tempURL = StickerExportManager.shared.createTemporaryFile(for: img, filename: sticker.name) {
                    return NSItemProvider(contentsOf: tempURL) ?? NSItemProvider()
                }
                return NSItemProvider()
            }
            
            // Title & Emoji
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Text(sticker.emoji)
                        .font(.system(size: 12))
                    Text(sticker.localizedTitle)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                
                Text(sticker.category.rawValue)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .task(id: sticker.id) {
            await loadImage()
        }
    }
    
    /// Load image: prefer disk-cached PNG, fall back to live snapshot from AvatarKit.
    @MainActor
    private func loadImage() async {
        // 1. Try on-disk pre-rendered sticker PNG (fast path, no AvatarKit needed)
        if let fileURL = sticker.localFileURL,
           let image = NSImage(contentsOf: fileURL) {
            self.loadedImage = image
            return
        }
        
        // 2. Fall back: render a live snapshot via AvatarKit (on main actor, safe)
        guard let avatar = avatar else { return }
        let snap = AvatarKitBridge.shared.snapshot(avatar: avatar, size: CGSize(width: 256, height: 256))
        if let snap {
            self.loadedImage = snap
        }
    }
    
    private func copySticker() {
        guard let img = loadedImage else { return }
        StickerExportManager.shared.copyToClipboard(image: img)
        withAnimation {
            showCopiedAlert = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            withAnimation {
                showCopiedAlert = false
            }
        }
    }
}
