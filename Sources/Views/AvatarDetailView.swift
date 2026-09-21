import SwiftUI
import AppKit

public enum StageDisplayMode: String, CaseIterable, Identifiable {
    case split = "3D Stage & Stickers"
    case full3D = "Full 3D Stage"
    case liveCamera = "Live Face Mirror"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .split: return "rectangle.split.2x1"
        case .full3D: return "cube.transparent.fill"
        case .liveCamera: return "camera.fill"
        }
    }
}

public enum StudioBackdrop: String, CaseIterable, Identifiable {
    case studio = "Studio"
    case graphite = "Graphite"
    case velvet = "Velvet"
    case neutral = "Clean"
    
    public var id: String { rawValue }
    
    public var nsColors: [NSColor] {
        switch self {
        case .studio:
            return [NSColor.controlAccentColor.withAlphaComponent(0.22), NSColor.windowBackgroundColor]
        case .graphite:
            return [NSColor(red: 0.18, green: 0.20, blue: 0.22, alpha: 1.0), NSColor(red: 0.08, green: 0.09, blue: 0.10, alpha: 1.0)]
        case .velvet:
            return [NSColor.systemPurple.withAlphaComponent(0.26), NSColor.windowBackgroundColor]
        case .neutral:
            return [NSColor.controlBackgroundColor, NSColor.windowBackgroundColor]
        }
    }
    
    public var backgroundColors: [Color] {
        nsColors.map { Color(nsColor: $0) }
    }
}

public struct AvatarDetailView: View {
    public let avatarItem: AvatarItem
    public let avatarObject: AnyObject?
    public let stickers: [StickerItem]
    public let onRandomizeRequested: () -> Void
    public let onEditRequested: () -> Void
    
    @StateObject private var stageController = StageViewController()
    @State private var displayMode: StageDisplayMode = .split
    @State private var activePoseName: String?
    @State private var stageHeight: CGFloat = 280
    @State private var backdrop: StudioBackdrop = .studio
    @State private var showCopiedAlert: Bool = false
    @State private var copiedNotificationText: String = "Copied!"
    @State private var stageMutationId: UUID = UUID()
    
    public init(
        avatarItem: AvatarItem,
        avatarObject: AnyObject?,
        stickers: [StickerItem],
        onRandomizeRequested: @escaping () -> Void,
        onEditRequested: @escaping () -> Void = {}
    ) {
        self.avatarItem = avatarItem
        self.avatarObject = avatarObject
        self.stickers = stickers
        self.onRandomizeRequested = onRandomizeRequested
        self.onEditRequested = onEditRequested
    }
    
    public var isAnimoji: Bool {
        if case .builtinAnimoji = avatarItem.sourceType { return true }
        return false
    }
    
    public var animojiName: String? {
        if case .builtinAnimoji(let name) = avatarItem.sourceType { return name }
        return nil
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Content Area based on Display Mode
            if displayMode == .liveCamera {
                liveCameraSection
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    // 3D Stage Section
                    stageSection
                        .frame(maxHeight: displayMode == .full3D ? .infinity : stageHeight)
                    
                    Divider()
                    
                    if displayMode == .split {
                        // Bottom Stickers Grid
                        StickersGridView(
                            stickers: stickers,
                            avatar: avatarObject,
                            isAnimoji: isAnimoji,
                            animojiName: animojiName,
                            onSelectPose: { pose in
                                activePoseName = pose
                            }
                        )
                    } else {
                        // Quick Pose selector bar at the bottom in Full 3D mode
                        quickPoseBar
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("", selection: $displayMode) {
                    ForEach(StageDisplayMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.iconName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
            }
            
            ToolbarItemGroup(placement: .primaryAction) {
                // Copy visual avatar snapshot button with dropdown menu
                Menu {
                    Button {
                        copyVisualAvatar(withBackdrop: false)
                    } label: {
                        Label("Copy Visual Transparent PNG", systemImage: "doc.on.doc")
                    }
                    
                    Button {
                        copyVisualAvatar(withBackdrop: true)
                    } label: {
                        Label("Copy with Studio Backdrop", systemImage: "photo")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showCopiedAlert ? "checkmark" : "doc.on.doc")
                            .foregroundColor(showCopiedAlert ? .green : .primary)
                        Text(showCopiedAlert ? copiedNotificationText : "Copy")
                    }
                } primaryAction: {
                    copyVisualAvatar(withBackdrop: false)
                }
                .help("Copy avatar snapshot (⌘C)")
                
                // Customize button for editable avatars
                if avatarItem.isEditable {
                    Button(action: onEditRequested) {
                        Label("Customize", systemImage: "paintbrush")
                    }
                    .help("Open 3D Memoji Studio to edit hairstyle, skin tone, colors (⌘E)")
                }
                
                Button(action: shareAvatar) {
                    Image(systemName: "square.and.arrow.up")
                }
                .help("Share avatar image...")
            }
        }
    }
    
    // MARK: - 3D Stage Section
    
    private var stageSection: some View {
        ZStack {
            // Backdrop Gradient with Vignette effect
            RadialGradient(
                colors: backdrop.backgroundColors,
                center: .center,
                startRadius: 40,
                endRadius: 450
            )
            
            // Native AVTView Stage
            Avatar3DStageRepresentable(
                avatar: avatarObject,
                activePoseName: activePoseName,
                isAnimoji: isAnimoji,
                animojiName: animojiName,
                clone: true,
                mutationId: stageMutationId,
                stageController: stageController
            )
            .padding(displayMode == .full3D ? 24 : 12)
            .contextMenu {
                Button {
                    copyVisualAvatar(withBackdrop: false)
                } label: {
                    Label("Copy Visual Transparent PNG", systemImage: "doc.on.doc")
                }
                
                Button {
                    copyVisualAvatar(withBackdrop: true)
                } label: {
                    Label("Copy with Studio Backdrop", systemImage: "photo")
                }
                
                Divider()
                
                Button {
                    resetCamera()
                } label: {
                    Label("Reset Camera Framing", systemImage: "arrow.counterclockwise")
                }
            }
            
            // Floating Stage Controls Overlay
            stageOverlayControls
        }
    }
    
    private var stageOverlayControls: some View {
        VStack {
            HStack(alignment: .top) {
                // Leading: Avatar Name & Active Pose Chip
                HStack(spacing: 8) {
                    Text(avatarItem.displayName)
                        .font(.system(size: 13, weight: .semibold))
                    
                    Text(badgeLabel)
                        .font(.system(size: 9.5, weight: .medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(badgeColor.opacity(0.12))
                        .foregroundColor(badgeColor)
                        .clipShape(Capsule())
                    
                    if let pose = activePoseName {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 9.5))
                                .foregroundColor(.accentColor)
                            Text(friendlyPoseName(pose))
                                .font(.system(size: 11, weight: .medium))
                            
                            Button(action: {
                                withAnimation {
                                    activePoseName = nil
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(.plain)
                            .help("Reset to neutral expression")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                
                Spacer()
                
                // Trailing: Backdrop Theme & Reset View Controls
                HStack(spacing: 8) {
                    // Backdrop theme menu
                    Menu {
                        ForEach(StudioBackdrop.allCases) { b in
                            Button(action: { backdrop = b }) {
                                HStack {
                                    Text(b.rawValue)
                                    if backdrop == b {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "circle.lefthalf.filled")
                            .font(.system(size: 11))
                    }
                    .menuStyle(.borderlessButton)
                    .help("Change studio backdrop lighting")
                    
                    Divider().frame(height: 12)
                    
                    // Reset View button
                    Button(action: resetCamera) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help("Reset camera framing & orientation")
                    
                    if avatarItem.isEditable {
                        Divider().frame(height: 12)
                        
                        // Randomize button if editable
                        Button(action: onRandomizeRequested) {
                            Image(systemName: "dice")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                        .help("Randomize appearance (⌘R)")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
            }
            .padding(12)
            
            Spacer()
            
            // Bottom Controls Bar in 3D Stage
            HStack {
                // Drag hint
                HStack(spacing: 6) {
                    Image(systemName: "hand.draw")
                        .font(.system(size: 10))
                    Text("Drag to rotate • Scroll to zoom")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                
                Spacer()
                
                // Stage height toggle in split mode
                if displayMode == .split {
                    HStack(spacing: 4) {
                        Button(action: {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                stageHeight = stageHeight == 280 ? 360 : (stageHeight == 360 ? 220 : 280)
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.and.down")
                                    .font(.system(size: 9))
                                Text(stageHeight == 280 ? "Medium" : (stageHeight == 360 ? "Tall" : "Compact"))
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("Adjust 3D stage height")
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
    }
    
    // MARK: - Live Camera Section
    
    private var liveCameraSection: some View {
        VStack(spacing: 16) {
            ZStack {
                LiveFaceMirrorRepresentable(avatar: avatarObject)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
            }
            .padding(20)
            
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Live Camera Face Tracking Active")
                        .font(.system(size: 13, weight: .semibold))
                }
                Text("Smile, wink, raise eyebrows, or turn your head to control the Memoji in real time.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 16)
        }
    }
    
    // MARK: - Quick Pose Bar (Full 3D Mode)
    
    private var quickPoseBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button(action: { activePoseName = nil }) {
                    Text("Neutral")
                        .font(.system(size: 11, weight: activePoseName == nil ? .bold : .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(activePoseName == nil ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                        .foregroundColor(activePoseName == nil ? .white : .primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                
                ForEach(stickers.prefix(30)) { sticker in
                    let isSelected = activePoseName == sticker.name
                    Button(action: {
                        activePoseName = sticker.name
                    }) {
                        HStack(spacing: 4) {
                            Text(sticker.emoji)
                            Text(sticker.localizedTitle)
                                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                        .foregroundColor(isSelected ? .white : .primary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Helpers & Actions
    
    private var badgeLabel: String {
        switch avatarItem.sourceType {
        case .customMemoji: return "Custom Studio Memoji"
        case .userMemoji: return "Apple System Memoji"
        case .builtinAnimoji: return "Apple Animoji"
        case .randomMemoji: return "Custom Generated"
        }
    }
    
    private var badgeColor: Color {
        switch avatarItem.sourceType {
        case .customMemoji: return .purple
        case .userMemoji: return .blue
        case .builtinAnimoji: return .indigo
        case .randomMemoji: return .orange
        }
    }
    
    private func friendlyPoseName(_ name: String) -> String {
        AvatarDatabaseReader.shared.metadata(forStickerName: name).title
    }
    
    private func copyVisualAvatar(withBackdrop: Bool = false) {
        // 1. Capture snapshot directly from live 3D stage (captures exact angle, zoom, and active pose)
        var visualImage: NSImage? = stageController.captureSnapshot()
        
        // 2. Fall back to on-demand posed renderer if stage snapshot isn't available
        if visualImage == nil, let avatar = avatarObject {
            visualImage = AvatarKitBridge.shared.snapshot(
                avatar: avatar,
                poseName: activePoseName,
                animojiNamed: isAnimoji ? animojiName : nil,
                size: CGSize(width: 1024, height: 1024)
            )
        }
        
        guard let originalImage = visualImage else { return }
        
        let finalImage: NSImage
        if withBackdrop {
            finalImage = StickerExportManager.shared.renderWithRadialBackdrop(
                avatarImage: originalImage,
                backdropColors: backdrop.nsColors
            )
        } else {
            finalImage = originalImage
        }
        
        StickerExportManager.shared.copyToClipboard(image: finalImage)
        
        copiedNotificationText = withBackdrop ? "Copied with Backdrop!" : "Copied Visual PNG!"
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showCopiedAlert = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation {
                showCopiedAlert = false
            }
        }
    }
    
    private func resetCamera() {
        activePoseName = nil
        stageMutationId = UUID()
    }
    
    private func shareAvatar() {
        var visualImage: NSImage? = stageController.captureSnapshot()
        if visualImage == nil, let avatar = avatarObject {
            visualImage = AvatarKitBridge.shared.snapshot(
                avatar: avatar,
                poseName: activePoseName,
                animojiNamed: isAnimoji ? animojiName : nil,
                size: CGSize(width: 1024, height: 1024)
            )
        }
        guard let snap = visualImage,
              let tempURL = StickerExportManager.shared.createTemporaryFile(for: snap, filename: "\(avatarItem.displayName)_Visual") else {
            return
        }
        
        let picker = NSSharingServicePicker(items: [tempURL])
        if let window = NSApplication.shared.keyWindow, let contentView = window.contentView {
            picker.show(relativeTo: NSRect(x: contentView.bounds.midX, y: contentView.bounds.maxY - 40, width: 1, height: 1), of: contentView, preferredEdge: .maxY)
        }
    }
}
