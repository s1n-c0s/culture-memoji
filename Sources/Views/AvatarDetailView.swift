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

public struct AvatarDetailView: View {
    public let avatarItem: AvatarItem
    public let avatarObject: AnyObject?
    public let stickers: [StickerItem]
    public let onRandomizeRequested: () -> Void
    public let onEditRequested: () -> Void
    
    @State private var displayMode: StageDisplayMode = .split
    @State private var activePoseName: String?
    @State private var stageHeight: CGFloat = 260
    @State private var showCopiedAlert: Bool = false
    
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
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
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
                
                // Copy avatar image button
                Button(action: copyQuickAvatar) {
                    Label(showCopiedAlert ? "Copied!" : "Copy Avatar", systemImage: showCopiedAlert ? "checkmark" : "doc.on.doc")
                }
                .help("Quick copy avatar snapshot to clipboard")
                
                // Customize button for editable avatars
                if avatarItem.isEditable {
                    Button(action: onEditRequested) {
                        Label("Customize", systemImage: "paintbrush.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Customize hairstyles, skin tone, colors, glasses, and outfit")
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Content Area based on Display Mode
            if displayMode == .liveCamera {
                liveCameraSection
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    // 3D Stage: in split mode it uses stageHeight, in full3D mode it expands to fill the entire window
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
    
    // MARK: - 3D Stage Section
    
    private var stageSection: some View {
        ZStack {
            // Background subtle gradient
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.06),
                    Color(nsColor: .windowBackgroundColor)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            
            // Native AVTView
            Avatar3DStageRepresentable(
                avatar: avatarObject,
                activePoseName: activePoseName,
                isAnimoji: isAnimoji,
                animojiName: animojiName
            )
            .padding(displayMode == .full3D ? 24 : 12)
            
            // Stage Controls Overlay
            VStack {
                HStack {
                    if let pose = activePoseName {
                        HStack(spacing: 6) {
                            Text("Pose: \(friendlyPoseName(pose))")
                                .font(.system(size: 11, weight: .medium))
                            Button(action: {
                                activePoseName = nil
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 6) {
                        // Snapshot button
                        Button(action: copyQuickAvatar) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 12))
                                .padding(7)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Snapshot current 3D stage to clipboard")
                        
                        // Randomize button if random or user memoji
                        Button(action: onRandomizeRequested) {
                            Image(systemName: "dice.fill")
                                .font(.system(size: 12))
                                .padding(7)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Randomize 3D Memoji appearance")
                    }
                }
                .padding(12)
                
                Spacer()
                
                // 3D Navigation Hint (Full 3D Mode)
                if displayMode == .full3D {
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
                    .padding(.bottom, 8)
                }
            }
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
            HStack(spacing: 10) {
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
                
                ForEach(stickers.prefix(25)) { sticker in
                    Button(action: {
                        activePoseName = sticker.name
                    }) {
                        HStack(spacing: 4) {
                            Text(sticker.emoji)
                            Text(sticker.localizedTitle)
                                .font(.system(size: 11, weight: activePoseName == sticker.name ? .bold : .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(activePoseName == sticker.name ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                        .foregroundColor(activePoseName == sticker.name ? .white : .primary)
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
    
    // MARK: - Helpers
    
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
}
