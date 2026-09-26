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
    public let isFullScreen: Bool
    public let onToggleFullScreen: (() -> Void)?
    
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
    @State private var isHoveringReset: Bool = false
    @State private var isHoveringHintReset: Bool = false
    @State private var isHoveringFullScreen: Bool = false
    @State private var resetSpinDegrees: Double = 0
    @State private var shareAnchorView: NSView? = nil
    @State private var sharePickerDelegate: SharePickerDelegate? = nil
    
    public init(
        avatarItem: AvatarItem,
        avatarObject: AnyObject?,
        activePoseName: String? = nil,
        isFullScreen: Bool = false,
        onResetPoseAndCamera: @escaping () -> Void,
        onEditRequested: @escaping () -> Void = {},
        onRenameRequested: ((String) -> Void)? = nil,
        onCopiedNotification: ((String) -> Void)? = nil,
        onToggleFullScreen: (() -> Void)? = nil
    ) {
        self.avatarItem = avatarItem
        self.avatarObject = avatarObject
        self.activePoseName = activePoseName
        self.isFullScreen = isFullScreen
        self.onResetPoseAndCamera = onResetPoseAndCamera
        self.onEditRequested = onEditRequested
        self.onRenameRequested = onRenameRequested
        self.onCopiedNotification = onCopiedNotification
        self.onToggleFullScreen = onToggleFullScreen
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
            .onTapGesture(count: 2) {
                handleDoubleTapResetAngle()
            }
            
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
                    stageController: stageController,
                    onDoubleTap: handleDoubleTapResetAngle
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, 130)
                .contextMenu {
                    Button(action: copyAvatarToClipboard) {
                        Label("Copy Visual Transparent PNG", systemImage: "doc.on.doc")
                    }
                    
                    Button(action: { downloadAvatarImage(showSavePanel: false) }) {
                        Label("Download Image", systemImage: "arrow.down.circle")
                    }
                    
                    Button(action: { downloadAvatarImage(showSavePanel: true) }) {
                        Label("Save Image As...", systemImage: "square.and.arrow.down")
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
                
                // Subtle gesture hint with Quick Reset
                if !isLiveCameraActive {
                    HStack(spacing: 6) {
                        Image(systemName: "hand.draw")
                            .font(.system(size: 10))
                        Text("Drag to rotate • Scroll to zoom")
                            .font(.system(size: 10.5, weight: .medium))
                        
                        Text("•")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary.opacity(0.35))
                        
                        Button(action: handleReset) {
                            HStack(spacing: 3.5) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .rotationEffect(.degrees(resetSpinDegrees))
                                Text("Reset")
                                    .font(.system(size: 10.5, weight: .semibold))
                            }
                            .foregroundColor(isHoveringHintReset ? .primary : .secondary)
                        }
                        .buttonStyle(.plain)
                        .onHover { h in isHoveringHintReset = h }
                        .help("Reset camera framing & neutral pose (⌘0)")
                    }
                    .foregroundColor(.secondary.opacity(0.75))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 4.5)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.04), radius: 4, y: 1)
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
        .onReceive(NotificationCenter.default.publisher(for: .copyCurrentAvatarRequested)) { _ in
            copyAvatarToClipboard()
        }
        .onReceive(NotificationCenter.default.publisher(for: .saveImageRequested)) { _ in
            downloadAvatarImage(showSavePanel: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .resetCameraAndPoseRequested)) { _ in
            handleReset()
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
                        .rotationEffect(.degrees(resetSpinDegrees))
                        .frame(width: 32, height: 32)
                        .background(Color.primary.opacity(isHoveringReset ? 0.12 : 0.06))
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(isHoveringReset ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: 1)
                        )
                        .scaleEffect(isHoveringReset ? 1.06 : 1.0)
                }
                .buttonStyle(.plain)
                .onHover { h in isHoveringReset = h }
                .keyboardShortcut("0", modifiers: .command)
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
                
                // Full Screen Toggle Button
                Button(action: {
                    onToggleFullScreen?()
                }) {
                    Image(systemName: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary.opacity(0.85))
                        .frame(width: 32, height: 32)
                        .background(Color.primary.opacity(isHoveringFullScreen ? 0.12 : 0.06))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.primary.opacity(0.08), lineWidth: 1))
                        .scaleEffect(isHoveringFullScreen ? 1.06 : 1.0)
                }
                .buttonStyle(.plain)
                .onHover { h in isHoveringFullScreen = h }
                .help(isFullScreen ? "Exit Full Screen (⌃⌘F)" : "Enter Full Screen (⌃⌘F)")
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
            .keyboardShortcut("c", modifiers: .command)
            .background(
                Button(action: copyAvatarToClipboard) {
                    EmptyView()
                }
                .keyboardShortcut("c", modifiers: .control)
                .opacity(0)
                .allowsHitTesting(false)
            )
            .onHover { h in isHoveringCopy = h }
            .help("Copy transparent PNG to clipboard (⌃C or ⌘C)")
            
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
            .background(ShareAnchorRepresentable(anchorView: $shareAnchorView))
            .onHover { h in isHoveringShare = h }
            .contextMenu {
                Button(action: { downloadAvatarImage(showSavePanel: false) }) {
                    Label("Download Image (Save to Downloads)", systemImage: "arrow.down.circle")
                }
                Button(action: { downloadAvatarImage(showSavePanel: true) }) {
                    Label("Save Image As...", systemImage: "square.and.arrow.down")
                }
                Button(action: shareAvatar) {
                    Label("Share via AirDrop, Messages...", systemImage: "square.and.arrow.up")
                }
            }
            .help("Share or download avatar (AirDrop, Messages, Downloads)...")
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
        withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) {
            resetSpinDegrees -= 360
        }
        if let view = stageController.avtView {
            AvatarKitBridge.shared.resetCameraFraming(on: view)
        }
        onResetPoseAndCamera()
        stageMutationId = UUID()
        onCopiedNotification?("Framing and pose reset")
    }
    
    private func handleDoubleTapResetAngle() {
        if let view = stageController.avtView {
            AvatarKitBridge.shared.applyCanonicalCameraFraming(to: view, animated: true, duration: 0.25)
        }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) {
            resetSpinDegrees -= 360
        }
        onCopiedNotification?("Facing angle centered")
    }
    
    private func getProcessedAvatarSnapshot() -> NSImage? {
        var image: NSImage? = stageController.captureSnapshot()
        
        if image == nil, let avatar = avatarObject {
            image = AvatarKitBridge.shared.snapshot(
                avatar: avatar,
                poseName: activePoseName,
                animojiNamed: isAnimoji ? animojiName : nil,
                size: CGSize(width: 1024, height: 1024)
            )
        }
        
        guard let rawImage = image else { return nil }
        return StickerExportManager.shared.trimTransparentMargins(image: rawImage)
    }
    
    private func downloadAvatarImage(showSavePanel: Bool = false) {
        guard let image = getProcessedAvatarSnapshot(),
              let data = StickerExportManager.shared.imageData(for: image, format: .png) else {
            return
        }
        
        let sanitizedName = avatarItem.displayName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let baseFilename = sanitizedName.isEmpty ? "Memoji" : sanitizedName
        
        if showSavePanel {
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.png]
            savePanel.canCreateDirectories = true
            savePanel.isExtensionHidden = false
            savePanel.title = "Save Avatar Image"
            savePanel.nameFieldStringValue = "\(baseFilename).png"
            if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
                savePanel.directoryURL = downloads
            }
            
            savePanel.begin { response in
                if response == .OK, let destURL = savePanel.url {
                    do {
                        try data.write(to: destURL)
                        onCopiedNotification?("Saved \(destURL.lastPathComponent)")
                    } catch {
                        onCopiedNotification?("Failed to save image")
                    }
                }
            }
        } else {
            // Direct download to ~/Downloads folder
            guard let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
                return
            }
            
            var destURL = downloadsURL.appendingPathComponent("\(baseFilename).png")
            var counter = 1
            while FileManager.default.fileExists(atPath: destURL.path) {
                destURL = downloadsURL.appendingPathComponent("\(baseFilename) \(counter).png")
                counter += 1
            }
            
            do {
                try data.write(to: destURL)
                onCopiedNotification?("Downloaded \(destURL.lastPathComponent) to Downloads")
            } catch {
                onCopiedNotification?("Failed to download image")
            }
        }
    }
    
    private func copyAvatarToClipboard() {
        guard let finalImage = getProcessedAvatarSnapshot() else { return }
        
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
        guard let snap = getProcessedAvatarSnapshot() else { return }
        guard let tempURL = StickerExportManager.shared.createTemporaryFile(for: snap, filename: "\(avatarItem.displayName)_Snapshot") else {
            return
        }
        
        let delegate = SharePickerDelegate(
            onDownload: { @MainActor in
                downloadAvatarImage(showSavePanel: false)
            },
            onSaveAs: { @MainActor in
                downloadAvatarImage(showSavePanel: true)
            }
        )
        self.sharePickerDelegate = delegate
        
        let picker = NSSharingServicePicker(items: [tempURL])
        picker.delegate = delegate
        
        if let anchor = shareAnchorView, anchor.window != nil {
            picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        } else if let window = NSApplication.shared.keyWindow, let contentView = window.contentView {
            let clickLoc = window.mouseLocationOutsideOfEventStream
            let viewLoc = contentView.convert(clickLoc, from: nil)
            picker.show(relativeTo: NSRect(origin: viewLoc, size: .zero), of: contentView, preferredEdge: .maxY)
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

// MARK: - Share Picker Delegate (Adds "Download Image" to NSSharingServicePicker)
@MainActor
final class SharePickerDelegate: NSObject, NSSharingServicePickerDelegate {
    let onDownload: @MainActor @Sendable () -> Void
    let onSaveAs: @MainActor @Sendable () -> Void
    
    init(onDownload: @escaping @MainActor @Sendable () -> Void, onSaveAs: @escaping @MainActor @Sendable () -> Void) {
        self.onDownload = onDownload
        self.onSaveAs = onSaveAs
    }
    
    nonisolated func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker,
        sharingServicesForItems items: [Any],
        proposedSharingServices proposedServices: [NSSharingService]
    ) -> [NSSharingService] {
        var customServices: [NSSharingService] = []
        let downloadAction = onDownload
        let saveAsAction = onSaveAs
        
        let downloadService = NSSharingService(
            title: "Download Image (Save to Downloads)",
            image: NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil) ?? NSImage(),
            alternateImage: nil
        ) {
            DispatchQueue.main.async {
                downloadAction()
            }
        }
        customServices.append(downloadService)
        
        let saveAsService = NSSharingService(
            title: "Save Image As...",
            image: NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil) ?? NSImage(),
            alternateImage: nil
        ) {
            DispatchQueue.main.async {
                saveAsAction()
            }
        }
        customServices.append(saveAsService)
        
        return customServices + proposedServices
    }
}

// MARK: - Share Anchor Representable (attaches NSSharingServicePicker to button frame)
private struct ShareAnchorRepresentable: NSViewRepresentable {
    @Binding var anchorView: NSView?
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            self.anchorView = view
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if self.anchorView !== nsView {
            DispatchQueue.main.async {
                self.anchorView = nsView
            }
        }
    }
}
