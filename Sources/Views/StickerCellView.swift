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
        VStack(spacing: 6) {
            // Sticker Image Card
            ZStack {
                // Background surface
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isHovered ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.04),
                                lineWidth: isHovered ? 1.0 : 0.5
                            )
                    )
                    .shadow(
                        color: isHovered ? Color.black.opacity(0.07) : Color.black.opacity(0.02),
                        radius: isHovered ? 6 : 2,
                        x: 0,
                        y: isHovered ? 2 : 1
                    )
                
                // Sticker Image or Loader
                if let img = loadedImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(10)
                        .scaleEffect(isHovered ? 1.03 : 1.0)
                        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isHovered)
                } else {
                    ProgressView()
                        .scaleEffect(0.7)
                }
                
                // Copied Notification Overlay
                if showCopiedAlert {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.green)
                        Text("Copied")
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .shadow(radius: 3)
                    .transition(.scale.combined(with: .opacity))
                }
                
                // Minimal Hover Actions (Top-right)
                if isHovered && !showCopiedAlert {
                    VStack {
                        HStack(spacing: 4) {
                            Spacer()
                            
                            // Copy button
                            Button(action: copySticker) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 9.5))
                                    .foregroundColor(.primary)
                                    .frame(width: 22, height: 22)
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
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 9.5))
                                    .foregroundColor(.primary)
                                    .frame(width: 22, height: 22)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .disabled(loadedImage == nil)
                            .help("Export Options...")
                        }
                        .padding(5)
                        
                        Spacer()
                    }
                    .transition(.opacity)
                }
            }
            .frame(height: 120)
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .onTapGesture {
                onSelectPose(sticker.name)
            }
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
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
            
            // Clean Title Label
            HStack(spacing: 3) {
                Text(sticker.emoji)
                    .font(.system(size: 11))
                Text(sticker.localizedTitle)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .task(id: "\(sticker.id)_\(avatar != nil ? UInt(bitPattern: ObjectIdentifier(avatar!)) : 0)") {
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
        
        // 2. Fall back: render a live posed snapshot via AvatarKit
        guard let avatar = avatar else { return }
        let snap = AvatarKitBridge.shared.snapshot(
            avatar: avatar,
            poseName: sticker.name,
            animojiNamed: isAnimoji ? animojiName : nil,
            size: CGSize(width: 320, height: 320)
        )
        if let snap = snap {
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
