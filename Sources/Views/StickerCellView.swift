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
            // Sticker Image Container
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(isHovered ? 0.9 : 0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isHovered ? Color.accentColor.opacity(0.5) : Color.gray.opacity(0.15), lineWidth: isHovered ? 1.5 : 1)
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
                
                // Hover Action Bar
                if isHovered {
                    VStack {
                        HStack {
                            Spacer()
                            // Animate 3D pose button
                            Button(action: {
                                onSelectPose(sticker.name)
                            }) {
                                Image(systemName: "cube.fill")
                                    .font(.system(size: 11))
                                    .padding(6)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .help("Preview 3D pose in stage")
                        }
                        .padding(8)
                        
                        Spacer()
                        
                        HStack(spacing: 6) {
                            // Copy button
                            Button(action: copySticker) {
                                Label("Copy", systemImage: "doc.on.doc")
                                    .font(.system(size: 10, weight: .medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .help("Copy transparent PNG to clipboard")
                            
                            // Export button
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
                            .help("Custom export (PNG/JPEG/Background)")
                        }
                        .padding(.bottom, 8)
                    }
                }
            }
            .frame(height: 130)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
            // Drag and Drop support
            .onDrag {
                guard let img = loadedImage,
                      let tempURL = StickerExportManager.shared.createTemporaryFile(for: img, filename: sticker.name) else {
                    return NSItemProvider()
                }
                return NSItemProvider(contentsOf: tempURL) ?? NSItemProvider()
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
            loadImage()
        }
    }
    
    private func loadImage() {
        if let fileURL = sticker.localFileURL,
           let image = NSImage(contentsOf: fileURL) {
            self.loadedImage = image
            return
        }
        
        // Dynamically render snapshot if no local file
        Task.detached(priority: .userInitiated) {
            // Render on main actor
            await MainActor.run {
                if let avatar = avatar {
                    // Try snapshot with pose or default snapshot
                    if let snap = AvatarKitBridge.shared.snapshot(avatar: avatar, size: CGSize(width: 256, height: 256)) {
                        self.loadedImage = snap
                    }
                }
            }
        }
    }
    
    private func copySticker() {
        guard let img = loadedImage else { return }
        StickerExportManager.shared.copyToClipboard(image: img)
        withAnimation {
            showCopiedAlert = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation {
                showCopiedAlert = false
            }
        }
    }
}
