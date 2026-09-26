import SwiftUI
import AppKit

public enum StudioLightingTheme: String, CaseIterable, Identifiable {
    case studio = "Ambient Studio"
    case clean = "Clean Stage"
    case dark = "Graphite Dark"
    case velvet = "Keynote Velvet"
    
    public var id: String { rawValue }
    
    public func colors(for scheme: ColorScheme) -> [Color] {
        switch self {
        case .studio:
            return scheme == .dark
                ? [Color(red: 0.19, green: 0.20, blue: 0.25), Color(red: 0.10, green: 0.10, blue: 0.12)]
                : [Color.white, Color(red: 0.93, green: 0.94, blue: 0.96)]
        case .clean:
            return scheme == .dark
                ? [Color(white: 0.15), Color(white: 0.09)]
                : [Color.white, Color(white: 0.95)]
        case .dark:
            return [Color(red: 0.14, green: 0.15, blue: 0.17), Color(red: 0.07, green: 0.07, blue: 0.08)]
        case .velvet:
            return scheme == .dark
                ? [Color(red: 0.23, green: 0.13, blue: 0.27), Color(red: 0.09, green: 0.06, blue: 0.12)]
                : [Color(red: 0.98, green: 0.94, blue: 0.99), Color(red: 0.91, green: 0.88, blue: 0.95)]
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
    
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var stageController = StageViewController()
    @State private var isLiveCameraActive: Bool = false
    @State private var showCopiedFeedback: Bool = false
    @State private var isHoveringName: Bool = false
    @State private var isEditingNameInline: Bool = false
    @State private var editedName: String = ""
    @State private var stageMutationId: UUID = UUID()
    @State private var lightingTheme: StudioLightingTheme = .studio
    @State private var isHoveringCopy: Bool = false
    @State private var isHoveringShare: Bool = false
    
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
            // Studio Ambient Backdrop adaptive to Dark & Light mode
            RadialGradient(
                colors: lightingTheme.colors(for: colorScheme),
                center: .center,
                startRadius: 50,
                endRadius: 650
            )
            .ignoresSafeArea()
            
            // Full-Area 3D Viewport (fills full available area of stage without clipping)
            if isLiveCameraActive {
                VStack(spacing: 12) {
                    Spacer()
                    LiveFaceMirrorRepresentable(avatar: avatarObject)
                        .frame(maxWidth: 640, maxHeight: 540)
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
                    
                    Spacer()
                }
                .padding(.bottom, 130)
            } else {
                Avatar3DStageRepresentable(
                    avatarId: avatarItem.id,
                    avatar: avatarObject,
                    activePoseName: activePoseName,
                    isAnimoji: isAnimoji,
                    animojiName: animojiName,
                    clone: true,
                    mutationId: stageMutationId,
                    stageController: stageController
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, 130)
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
            }
            
            // Floating Bottom Controls: Gesture Hint, Character Name, Action Buttons
            VStack(spacing: 8) {
                Spacer()
                
                // Subtle gesture hint
                if !isLiveCameraActive {
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
                
                // Character Name & Badge
                nameSection
                
                // Copy & Share Action Buttons Row
                actionButtonsRow
                    .padding(.top, 4)
            }
            .padding(.bottom, 24)
            
            // Top Right Action Bar
            VStack {
                topRightBar
                    .padding(.top, 18)
                    .padding(.trailing, 22)
                
                Spacer()
            }
        }
    }
    
    // MARK: - Top Right Bar (Reset & Camera Icons)
    
    private var topRightBar: some View {
        HStack {
            Spacer()
            
            HStack(spacing: 8) {
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
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary.opacity(0.85))
                        .frame(width: 32, height: 32)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.primary.opacity(0.08), lineWidth: 1))
                }
                .menuStyle(.borderlessButton)
                .help("Studio Lighting Theme")
                
                // Reset Camera & Pose Button
                Button(action: handleReset) {
                    ResetFramingIcon(size: 16)
                        .frame(width: 32, height: 32)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.primary.opacity(0.08), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Reset camera framing & neutral pose (⌘0)")
                
                // Live Camera Face-Tracking Toggle Button
                Button(action: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        isLiveCameraActive.toggle()
                    }
                }) {
                    LiveCameraIcon(size: 17, isActive: isLiveCameraActive)
                        .frame(width: 32, height: 32)
                        .background(isLiveCameraActive ? Color.green.opacity(0.15) : Color.primary.opacity(0.06))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(isLiveCameraActive ? Color.green.opacity(0.6) : Color.primary.opacity(0.08), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help(isLiveCameraActive ? "Switch back to 3D Stage" : "Live Camera Face-Tracking Mirror")
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
                HStack(spacing: 9) {
                    Image(systemName: showCopiedFeedback ? "checkmark.circle.fill" : "doc.on.doc.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(showCopiedFeedback ? .green : .primary)
                    
                    Text(showCopiedFeedback ? "Copied to Clipboard!" : "Copy")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundColor(.primary)
                }
                .frame(width: 200, height: 42)
                .background(Color.primary.opacity(isHoveringCopy ? 0.12 : 0.07))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(showCopiedFeedback ? Color.green.opacity(0.6) : Color.primary.opacity(0.1), lineWidth: 1.2)
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04), radius: 6, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .onHover { h in isHoveringCopy = h }
            .help("Copy transparent PNG to clipboard (⌘C)")
            
            // [ 📤 ] Share / Export Button
            Button(action: shareAvatar) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 42, height: 42)
                    .background(Color.primary.opacity(isHoveringShare ? 0.12 : 0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1.2)
                    )
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04), radius: 6, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .onHover { h in isHoveringShare = h }
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
