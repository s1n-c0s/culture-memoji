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
    
    public var backgroundColors: [Color] {
        switch self {
        case .studio:
            return [Color.accentColor.opacity(0.12), Color(nsColor: .windowBackgroundColor)]
        case .graphite:
            return [Color(red: 0.15, green: 0.16, blue: 0.18), Color(red: 0.08, green: 0.09, blue: 0.10)]
        case .velvet:
            return [Color.purple.opacity(0.18), Color(nsColor: .windowBackgroundColor)]
        case .neutral:
            return [Color(nsColor: .controlBackgroundColor), Color(nsColor: .windowBackgroundColor)]
        }
    }
}

public struct AvatarDetailView: View {
    public let avatarItem: AvatarItem
    public let avatarObject: AnyObject?
    public let stickers: [StickerItem]
    public let onRandomizeRequested: () -> Void
    public let onEditRequested: () -> Void
    
    @State private var displayMode: StageDisplayMode = .split
    @State private var activePoseName: String?
    @State private var stageHeight: CGFloat = 280
    @State private var backdrop: StudioBackdrop = .studio
    @State private var showCopiedAlert: Bool = false
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
            // Header Bar
            headerBar
            
            Divider()
            
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
    }
    
    // MARK: - Header Bar
    
    private var headerBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(avatarItem.displayName)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    // Badge
                    Text(badgeLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(badgeColor.opacity(0.15))
                        .foregroundColor(badgeColor)
                        .clipShape(Capsule())
                }
                
                Text("\(stickers.count) sticker variations ready to use and export")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Mode Picker
            Picker("", selection: $displayMode) {
                ForEach(StageDisplayMode.allCases) { mode in
                    Label(mode.rawValue, systemImage: mode.iconName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 320)
            
            // Copy avatar snapshot button
            Button(action: copyQuickAvatar) {
                HStack(spacing: 5) {
                    Image(systemName: showCopiedAlert ? "checkmark" : "doc.on.doc")
                        .foregroundColor(showCopiedAlert ? .green : .primary)
                    Text(showCopiedAlert ? "Copied!" : "Copy Avatar")
                }
            }
            .help("Quick copy avatar snapshot to clipboard (⌘C)")
            
            // Customize button for editable avatars
            if avatarItem.isEditable {
                Button(action: onEditRequested) {
                    Label("Customize", systemImage: "paintbrush.fill")
                }
                .buttonStyle(.borderedProminent)
                .help("Open 3D Memoji Studio to edit hairstyle, skin tone, colors, glasses, outfit (⌘E)")
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
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
                mutationId: stageMutationId
            )
            .padding(displayMode == .full3D ? 24 : 12)
            
            // Floating Stage Controls Overlay
            stageOverlayControls
        }
    }
    
    private var stageOverlayControls: some View {
        VStack {
            HStack {
                // Active Pose Chip with Reset Button
                if let pose = activePoseName {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10))
                            .foregroundColor(.accentColor)
                        Text(friendlyPoseName(pose))
                            .font(.system(size: 11, weight: .semibold))
                        
                        Button(action: {
                            withAnimation {
                                activePoseName = nil
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                        .help("Reset to neutral expression")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.1), radius: 3)
                }
                
                Spacer()
                
                // Backdrop Theme & Quick Actions Pill
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
                    
                    Divider().frame(height: 14)
                    
                    // Reset View button
                    Button(action: resetCamera) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help("Reset camera framing & orientation")
                    
                    // Randomize button if random or user memoji
                    Button(action: onRandomizeRequested) {
                        Image(systemName: "dice.fill")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help("Randomize Memoji appearance (⌘R)")
                    
                    // Share button
                    Button(action: shareAvatar) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help("Share avatar image...")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.1), radius: 3)
            }
            .padding(14)
            
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
    
    private func copyQuickAvatar() {
        guard let avatar = avatarObject else { return }
        if let snap = AvatarKitBridge.shared.snapshot(avatar: avatar, size: CGSize(width: 512, height: 512), scale: 2.0) {
            StickerExportManager.shared.copyToClipboard(image: snap)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                showCopiedAlert = true
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                withAnimation {
                    showCopiedAlert = false
                }
            }
        }
    }
    
    private func resetCamera() {
        activePoseName = nil
        stageMutationId = UUID()
    }
    
    private func shareAvatar() {
        guard let avatar = avatarObject,
              let snap = AvatarKitBridge.shared.snapshot(avatar: avatar, size: CGSize(width: 512, height: 512), scale: 2.0),
              let tempURL = StickerExportManager.shared.createTemporaryFile(for: snap, filename: "\(avatarItem.displayName)_Avatar") else {
            return
        }
        
        let picker = NSSharingServicePicker(items: [tempURL])
        if let window = NSApplication.shared.keyWindow, let contentView = window.contentView {
            picker.show(relativeTo: NSRect(x: contentView.bounds.midX, y: contentView.bounds.maxY - 40, width: 1, height: 1), of: contentView, preferredEdge: .maxY)
        }
    }
}
