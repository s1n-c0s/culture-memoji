import SwiftUI
import AppKit

public struct StickerCellView: View {
    public let sticker: StickerItem
    public let avatar: AnyObject?
    public let isAnimoji: Bool
    public let animojiName: String?
    public let onSelectPose: (String) -> Void
    public let onExportRequest: (StickerItem, NSImage) -> Void
    public let onCopied: ((String) -> Void)?
    
    @State private var isHovered: Bool = false
    @State private var showCopiedAlert: Bool = false
    @State private var loadedImage: NSImage?
    
    public init(
        sticker: StickerItem,
        avatar: AnyObject?,
        isAnimoji: Bool = false,
        animojiName: String? = nil,
        onSelectPose: @escaping (String) -> Void,
        onExportRequest: @escaping (StickerItem, NSImage) -> Void,
        onCopied: ((String) -> Void)? = nil
    ) {
        self.sticker = sticker
        self.avatar = avatar
        self.isAnimoji = isAnimoji
        self.animojiName = animojiName
        self.onSelectPose = onSelectPose
        self.onExportRequest = onExportRequest
        self.onCopied = onCopied
    }
    
    public var body: some View {
        VStack(spacing: 8) {
            // Sticker Image Card
            ZStack {
                // Card Background with smooth elevation on hover
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                isHovered ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.06),
                                lineWidth: isHovered ? 1.5 : 1
                            )
                    )
                    .shadow(
                        color: isHovered ? Color.black.opacity(0.12) : Color.black.opacity(0.03),
                        radius: isHovered ? 8 : 3,
                        x: 0,
                        y: isHovered ? 4 : 1
                    )
                
                // Sticker Image or Loader
                if let img = loadedImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(10)
                        .scaleEffect(isHovered ? 1.04 : 1.0)
                        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
                } else {
                    ProgressView()
                        .scaleEffect(0.75)
                }
                
                // "Pose 3D" pill on hover (top center)
                if isHovered && !showCopiedAlert {
                    VStack {
                        HStack(spacing: 4) {
                            Image(systemName: "cube.transparent")
                                .font(.system(size: 9))
                            Text("Pose 3D")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .shadow(radius: 2)
                        .padding(.top, 6)
                        
                        Spacer()
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
                
                // Copied Notification Overlay
                if showCopiedAlert {
                    VStack {
                        Spacer()
                        HStack(spacing: 5) {
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
                
                // Hover Action Bar (Copy & Export Buttons)
                if isHovered && !showCopiedAlert {
                    VStack {
                        Spacer()
                        
                        HStack(spacing: 6) {
                            // Copy button
                            Button(action: copySticker) {
                                Image(systemName: "doc.on.doc.fill")
                                    .font(.system(size: 11))
                                    .padding(6)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .help("Copy transparent PNG (⌘C)")
                            
                            // Export button
                            Button(action: {
                                if let img = loadedImage {
                                    onExportRequest(sticker, img)
                                }
                            }) {
                                Image(systemName: "square.and.arrow.down.fill")
                                    .font(.system(size: 11))
                                    .padding(6)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .disabled(loadedImage == nil)
                            .help("Custom Export Options...")
                        }
                        .padding(.bottom, 8)
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .frame(height: 125)
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .onTapGesture {
                // Single click poses the 3D model
                onSelectPose(sticker.name)
            }
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    // Double click quickly copies sticker
                    copySticker()
                }
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
            .contextMenu {
                Button {
                    onSelectPose(sticker.name)
                } label: {
                    Label("Apply Pose to 3D Model", systemImage: "cube.transparent")
                }
                
                Divider()
                
                Button {
                    copySticker()
                } label: {
                    Label("Copy Sticker PNG", systemImage: "doc.on.doc")
                }
                
                Button {
                    if let img = loadedImage {
                        onExportRequest(sticker, img)
                    }
                } label: {
                    Label("Export Options...", systemImage: "square.and.arrow.down")
                }
                .disabled(loadedImage == nil)
                
                Divider()
                
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(sticker.name, forType: .string)
                } label: {
                    Label("Copy Pose Identifier (\(sticker.name))", systemImage: "tag")
                }
            }
            .onDrag {
                guard let img = loadedImage else {
                    return NSItemProvider()
                }
                if let tempURL = StickerExportManager.shared.createTemporaryFile(for: img, filename: sticker.name) {
                    return NSItemProvider(contentsOf: tempURL) ?? NSItemProvider()
                }
                return NSItemProvider()
            }
            
            // Title & Category Label
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
    
    // MARK: - Image Loading & Copy
    
    @MainActor
    private func loadImage() async {
        // 1. Try on-disk pre-rendered sticker PNG (fast, high-resolution)
        if let fileURL = sticker.localFileURL,
           let image = NSImage(contentsOf: fileURL) {
            self.loadedImage = image
            return
        }
        
        // 2. Fall back: render a live snapshot via AvatarKit
        guard let avatar = avatar else { return }
        let snap = AvatarKitBridge.shared.snapshot(avatar: avatar, size: CGSize(width: 256, height: 256))
        if let snap {
            self.loadedImage = snap
        }
    }
    
    private func copySticker() {
        guard let img = loadedImage else { return }
        StickerExportManager.shared.copyToClipboard(image: img)
        onCopied?(sticker.localizedTitle)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
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
