import SwiftUI
import AppKit

public enum StudioLightingTheme: String, CaseIterable, Identifiable {
    case clean = "Clean Stage"
    case studio = "Ambient Studio"
    case graphite = "Graphite Dark"
    case velvet = "Keynote Velvet"
    
    public var id: String { rawValue }
    
    public var colors: [Color] {
        switch self {
        case .clean:
            return [
                Color.white,
                Color(white: 0.96)
            ]
        case .studio:
            return [
                Color(nsColor: .controlBackgroundColor).opacity(0.5),
                Color(nsColor: .windowBackgroundColor)
            ]
        case .graphite:
            return [
                Color(red: 0.18, green: 0.19, blue: 0.22),
                Color(red: 0.10, green: 0.11, blue: 0.13)
            ]
        case .velvet:
            return [
                Color.purple.opacity(0.18),
                Color(nsColor: .windowBackgroundColor)
            ]
        }
    }
}

public struct AvatarDetailView: View {
    public let avatarItem: AvatarItem
    public let avatarObject: AnyObject?
    public let activePoseName: String?
    public let onResetPoseAndCamera: () -> Void
    public let onEditRequested: () -> Void
    public let onRenameRequested: ((String) -> Void)?
    public let onCopiedNotification: ((String) -> Void)?
    
    @StateObject private var stageController = StageViewController()
    @State private var isLiveCameraActive: Bool = false
    @State private var showCopiedFeedback: Bool = false
    @State private var isHoveringName: Bool = false
    @State private var isEditingNameInline: Bool = false
    @State private var editedName: String = ""
    @State private var stageMutationId: UUID = UUID()
    @State private var lightingTheme: StudioLightingTheme = .clean
    
    public init(
        avatarItem: AvatarItem,
        avatarObject: AnyObject?,
        activePoseName: String? = nil,
        onResetPoseAndCamera: @escaping () -> Void,
        onEditRequested: @escaping () -> Void = {},
        onRenameRequested: ((String) -> Void)? = nil,
        onCopiedNotification: ((String) -> Void)? = nil
    ) {
        self.avatarItem = avatarItem
        self.avatarObject = avatarObject
        self.activePoseName = activePoseName
        self.onResetPoseAndCamera = onResetPoseAndCamera
        self.onEditRequested = onEditRequested
        self.onRenameRequested = onRenameRequested
        self.onCopiedNotification = onCopiedNotification
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
        ZStack {
            // Elegant Studio Ambient Backdrop
            RadialGradient(
                colors: lightingTheme.colors,
                center: .center,
                startRadius: 60,
                endRadius: 520
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Top Right Action Bar
                topRightBar
                    .padding(.top, 18)
                    .padding(.trailing, 22)
                
                // Central Avatar Stage / Live Camera Viewport (expands flexibly)
                centerAvatarArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 8)
                
                // Character Name & Badge
                nameSection
                    .padding(.bottom, 16)
                
                // Copy & Share Action Buttons Row
                actionButtonsRow
                    .padding(.bottom, 32)
            }
        }
    }
    
    // MARK: - Top Right Bar (Reset & Camera Icons)
    
    private var topRightBar: some View {
        HStack {
            Spacer()
            
            HStack(spacing: 10) {
                // Theme picker menu
                Menu {
                    ForEach(StudioLightingTheme.allCases) { theme in
                        Button(action: { lightingTheme = theme }) {
                            HStack {
                                Text(theme.rawValue)
                                if lightingTheme == theme {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .frame(width: 34, height: 34)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.primary.opacity(0.1), lineWidth: 1))
                }
                .menuStyle(.borderlessButton)
                .help("Change studio lighting theme")
                
                // Reset Camera & Pose Button
                Button(action: handleReset) {
                    ResetFramingIcon(size: 18)
                        .frame(width: 34, height: 34)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.primary.opacity(0.1), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Reset camera framing & neutral pose (⌘0)")
                
                // Live Camera Face-Tracking Toggle Button
                Button(action: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        isLiveCameraActive.toggle()
                    }
                }) {
                    ZStack {
                        LiveCameraIcon(size: 20, isActive: isLiveCameraActive)
                        
                        if isLiveCameraActive {
                            Circle()
                                .stroke(Color.green, lineWidth: 2)
                                .frame(width: 36, height: 36)
                        }
                    }
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(isLiveCameraActive ? Color.green.opacity(0.5) : Color.primary.opacity(0.1), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help(isLiveCameraActive ? "Switch back to 3D Stage" : "Live Camera Face-Tracking Mirror")
            }
        }
    }
    
    // MARK: - Center Avatar Stage
    
    private var centerAvatarArea: some View {
        ZStack {
            if isLiveCameraActive {
                // Live Camera Tracking Mode Viewport
                VStack(spacing: 12) {
                    LiveFaceMirrorRepresentable(avatar: avatarObject)
                        .frame(width: 440, height: 420)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(Color.primary.opacity(0.12), lineWidth: 1.5)
                        )
                        .shadow(color: Color.black.opacity(0.15), radius: 16, x: 0, y: 8)
                    
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 7, height: 7)
                        Text("Live Face-Tracking Active")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                }
            } else {
                // Interactive 3D AVTView Stage
                VStack(spacing: 8) {
                    Avatar3DStageRepresentable(
                        avatar: avatarObject,
                        activePoseName: activePoseName,
                        isAnimoji: isAnimoji,
                        animojiName: animojiName,
                        clone: true,
                        mutationId: stageMutationId,
                        stageController: stageController
                    )
                    .frame(width: 470, height: 440)
                    .contextMenu {
                        Button(action: copyAvatarToClipboard) {
                            Label("Copy Visual Transparent PNG", systemImage: "doc.on.doc")
                        }
                        
                        Button(action: shareAvatar) {
                            Label("Share Avatar...", systemImage: "square.and.arrow.up")
                        }
                        
                        Divider()
                        
                        Button(action: handleReset) {
                            Label("Reset Camera Framing & Pose", systemImage: "arrow.counterclockwise")
                        }
                        
                        if avatarItem.isEditable {
                            Button(action: onEditRequested) {
                                Label("Customize 3D Memoji...", systemImage: "paintbrush")
                            }
                        }
                    }
                    
                    // Subtle gesture hint
                    HStack(spacing: 5) {
                        Image(systemName: "hand.draw")
                            .font(.system(size: 10))
                        Text("Drag to rotate • Scroll to zoom")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3.5)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                }
            }
        }
    }
    
    // MARK: - Character Name Section
    
    private var nameSection: some View {
        VStack(spacing: 6) {
            if isEditingNameInline {
                HStack(spacing: 8) {
                    TextField("Character Name", text: $editedName, onCommit: saveInlineName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.primary.opacity(0.06))
                        )
                    
                    Button(action: saveInlineName) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                HStack(spacing: 8) {
                    Text(avatarItem.displayName)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    if isHoveringName && onRenameRequested != nil {
                        Button(action: {
                            editedName = avatarItem.displayName
                            isEditingNameInline = true
                        }) {
                            Image(systemName: "pencil")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .onHover { h in isHoveringName = h }
                .onTapGesture(count: 2) {
                    if onRenameRequested != nil {
                        editedName = avatarItem.displayName
                        isEditingNameInline = true
                    }
                }
            }
            
            // Category Badge Chip
            Text(categoryBadgeText)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.05))
                .clipShape(Capsule())
        }
    }
    
    // MARK: - Action Buttons Row (Copy & Share)
    
    private var actionButtonsRow: some View {
        HStack(spacing: 12) {
            // [ 📋 Copy ] Button with animated feedback
            Button(action: copyAvatarToClipboard) {
                HStack(spacing: 10) {
                    Image(systemName: showCopiedFeedback ? "checkmark.circle.fill" : "doc.on.doc.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(showCopiedFeedback ? .green : .primary)
                    
                    Text(showCopiedFeedback ? "Copied to Clipboard!" : "Copy Image")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                }
                .frame(width: 250, height: 48)
                .background(.ultraThickMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(showCopiedFeedback ? Color.green.opacity(0.6) : Color.primary.opacity(0.12), lineWidth: 1.5)
                )
                .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)
            }
            .buttonStyle(.plain)
            .help("Copy transparent PNG to clipboard (⌘C)")
            
            // [ 📤 ] Share / Export Button
            Button(action: shareAvatar) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 48, height: 48)
                    .background(.ultraThickMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1.5)
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)
            }
            .buttonStyle(.plain)
            .help("Share avatar (AirDrop, Messages, Mail)...")
        }
    }
    
    // MARK: - Helpers & Actions
    
    private var categoryBadgeText: String {
        switch avatarItem.sourceType {
        case .userMemoji: return "Personal Apple Memoji"
        case .customMemoji: return "Studio 3D Model"
        case .builtinAnimoji: return "Apple Animoji"
        case .randomMemoji: return "Generated Memoji"
        }
    }
    
    private func handleReset() {
        if let view = stageController.avtView {
            AvatarKitBridge.shared.resetCameraFraming(on: view)
        }
        onResetPoseAndCamera()
        stageMutationId = UUID()
        onCopiedNotification?("Framing and pose reset")
    }
    
    private func copyAvatarToClipboard() {
        var image: NSImage? = stageController.captureSnapshot(preferredSize: CGSize(width: 1024, height: 1024))
        
        if image == nil, let avatar = avatarObject {
            image = AvatarKitBridge.shared.snapshot(
                avatar: avatar,
                poseName: activePoseName,
                animojiNamed: isAnimoji ? animojiName : nil,
                size: CGSize(width: 1024, height: 1024)
            )
        }
        
        guard let finalImage = image else { return }
        
        StickerExportManager.shared.copyToClipboard(image: finalImage)
        
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
            showCopiedFeedback = true
        }
        onCopiedNotification?("Copied transparent PNG to clipboard")
        
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation {
                showCopiedFeedback = false
            }
        }
    }
    
    private func shareAvatar() {
        var image: NSImage? = stageController.captureSnapshot(preferredSize: CGSize(width: 1024, height: 1024))
        if image == nil, let avatar = avatarObject {
            image = AvatarKitBridge.shared.snapshot(
                avatar: avatar,
                poseName: activePoseName,
                animojiNamed: isAnimoji ? animojiName : nil,
                size: CGSize(width: 1024, height: 1024)
            )
        }
        guard let snap = image,
              let tempURL = StickerExportManager.shared.createTemporaryFile(for: snap, filename: "\(avatarItem.displayName)_Snapshot") else {
            return
        }
        
        let picker = NSSharingServicePicker(items: [tempURL])
        if let window = NSApplication.shared.keyWindow, let contentView = window.contentView {
            picker.show(relativeTo: NSRect(x: contentView.bounds.midX, y: contentView.bounds.minY + 60, width: 1, height: 1), of: contentView, preferredEdge: .maxY)
        }
    }
    
    private func saveInlineName() {
        let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            onRenameRequested?(trimmed)
        }
        isEditingNameInline = false
    }
}
