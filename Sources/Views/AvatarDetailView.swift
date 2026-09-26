import SwiftUI
import AppKit

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
            // Pure white background matching design
            AppTheme.stageBackground
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Top Right Action Icons
                topRightBar
                    .padding(.top, 24)
                    .padding(.trailing, 28)
                
                Spacer()
                
                // Central Avatar / Live Camera Area
                centerAvatarArea
                    .frame(maxWidth: .infinity)
                    .frame(height: 480)
                
                Spacer()
                
                // Character Name
                nameSection
                    .padding(.bottom, 22)
                
                // Copy & Share Action Buttons Row
                actionButtonsRow
                    .padding(.bottom, 36)
            }
        }
    }
    
    // MARK: - Top Right Bar (Reset & Camera Icons)
    
    private var topRightBar: some View {
        HStack {
            Spacer()
            
            HStack(spacing: 22) {
                // Reset Orbit & Neutral Pose Button
                Button(action: handleReset) {
                    ResetFramingIcon(size: 26)
                }
                .buttonStyle(.plain)
                .help("Reset camera framing & neutral pose")
                
                // Live Camera Face-Tracking Toggle Button
                Button(action: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        isLiveCameraActive.toggle()
                    }
                }) {
                    LiveCameraIcon(size: 28, isActive: isLiveCameraActive)
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
                // Live Camera Tracking Mode
                LiveFaceMirrorRepresentable(avatar: avatarObject)
                    .frame(width: 440, height: 440)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.black.opacity(0.1), lineWidth: 1)
                    )
            } else {
                // Interactive 3D AVTView Stage
                Avatar3DStageRepresentable(
                    avatar: avatarObject,
                    activePoseName: activePoseName,
                    isAnimoji: isAnimoji,
                    animojiName: animojiName,
                    clone: true,
                    mutationId: stageMutationId,
                    stageController: stageController
                )
                .frame(width: 460, height: 460)
                .contextMenu {
                    Button(action: copyAvatarToClipboard) {
                        Label("Copy Visual PNG", systemImage: "doc.on.doc")
                    }
                    
                    Button(action: shareAvatar) {
                        Label("Share Avatar...", systemImage: "square.and.arrow.up")
                    }
                    
                    Divider()
                    
                    Button(action: handleReset) {
                        Label("Reset Framing & Pose", systemImage: "arrow.counterclockwise")
                    }
                    
                    if avatarItem.isEditable {
                        Button(action: onEditRequested) {
                            Label("Customize 3D Memoji...", systemImage: "pencil")
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Character Name Section
    
    private var nameSection: some View {
        Group {
            if isEditingNameInline {
                HStack(spacing: 8) {
                    TextField("Character Name", text: $editedName, onCommit: saveInlineName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 30, weight: .regular))
                        .foregroundColor(.black)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                    
                    Button(action: saveInlineName) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.black)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                HStack(spacing: 8) {
                    Text(avatarItem.displayName)
                        .font(.system(size: 30, weight: .regular))
                        .foregroundColor(.black)
                    
                    if isHoveringName && onRenameRequested != nil {
                        Button(action: {
                            editedName = avatarItem.displayName
                            isEditingNameInline = true
                        }) {
                            Image(systemName: "pencil")
                                .font(.system(size: 14))
                                .foregroundColor(Color.black.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .onHover { h in
                    isHoveringName = h
                }
                .onTapGesture(count: 2) {
                    if onRenameRequested != nil {
                        editedName = avatarItem.displayName
                        isEditingNameInline = true
                    }
                }
            }
        }
    }
    
    // MARK: - Action Buttons Row (Copy & Share)
    
    private var actionButtonsRow: some View {
        HStack(spacing: 14) {
            // [ 📋 Copy ] Button
            Button(action: copyAvatarToClipboard) {
                HStack(spacing: 12) {
                    Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(.black)
                    
                    Text(showCopiedFeedback ? "Copied!" : "Copy")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundColor(.black)
                }
                .frame(width: 260, height: 50)
                .background(AppTheme.buttonBackground)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .buttonStyle(.plain)
            .help("Copy transparent Memoji PNG to clipboard (⌘C)")
            
            // [ 📤 ] Share / Export Button
            Button(action: shareAvatar) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.black)
                    .frame(width: 50, height: 50)
                    .background(AppTheme.buttonBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .buttonStyle(.plain)
            .help("Share or export avatar")
        }
    }
    
    // MARK: - Actions
    
    private func handleReset() {
        if let view = stageController.avtView {
            AvatarKitBridge.shared.resetCameraFraming(on: view)
        }
        onResetPoseAndCamera()
        stageMutationId = UUID()
        onCopiedNotification?("Framing and pose reset")
    }
    
    private func copyAvatarToClipboard() {
        // 1. Try to capture from live 3D stage
        var image: NSImage? = stageController.captureSnapshot(preferredSize: CGSize(width: 1024, height: 1024))
        
        // 2. Fall back to on-demand render
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
            try? await Task.sleep(nanoseconds: 1_500_000_000)
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
