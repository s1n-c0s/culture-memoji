import SwiftUI
import AppKit

public struct MemojiEditorView: View {
    public let initialAvatar: AnyObject
    public let initialName: String
    public let isNew: Bool
    public let onSave: (String, AnyObject) -> Void
    public let onCancel: () -> Void
    
    // Active editing avatar (holds the live mutable AVTMemoji instance)
    @State private var editingAvatar: AnyObject
    @State private var avatarName: String
    @State private var selectedCategory: CustomizerCategory = .hair
    @State private var activePresetId: String?
    @State private var activeColorName: String?
    @State private var searchText: String = ""
    @State private var mutationId = UUID()
    @State private var previewPose: String? = nil
    @State private var hasUnsavedChanges: Bool = false
    @StateObject private var stageController = StageViewController()
    
    public init(
        avatar: AnyObject,
        name: String = "My Memoji",
        isNew: Bool = false,
        onSave: @escaping (String, AnyObject) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initialAvatar = avatar
        self.initialName = name
        self.isNew = isNew
        self.onSave = onSave
        self.onCancel = onCancel
        
        // Clone initial avatar to work on an isolated editing copy (skip redundant clone if it's already an isolated new instance)
        let cloned = isNew ? avatar : (AvatarKitBridge.shared.cloneAvatar(avatar) ?? avatar)
        self._editingAvatar = State(initialValue: cloned)
        self._avatarName = State(initialValue: name)
        
        // Pre-initialize active preset and color so first frame renders immediately without layout flicker
        let initialPreset = MemojiCustomizer.shared.currentPresetIdentifier(for: .hair, in: cloned)
        let initialColor = MemojiCustomizer.shared.currentColorName(for: .hair, in: cloned)
        self._activePresetId = State(initialValue: initialPreset)
        self._activeColorName = State(initialValue: initialColor)
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerBar
            
            Divider()
            
            // Studio Workspace (3D Stage on Left, Customizer on Right)
            HStack(spacing: 0) {
                // Left: Interactive 3D Stage
                stagePane
                    .frame(minWidth: 350, maxWidth: 440)
                
                Divider()
                
                // Right: Customization Controls
                controlsPane
                    .frame(minWidth: 460, maxWidth: .infinity)
            }
        }
        .frame(minWidth: 900, minHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if activePresetId == nil || activeColorName == nil {
                syncActiveSelections()
            }
        }
        .onChange(of: selectedCategory) { _, _ in
            searchText = ""
            syncActiveSelections()
        }
    }
    
    // MARK: - Header Bar
    
    private var headerBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: isNew ? "sparkles" : "paintbrush.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.accentColor)
                
                Text(isNew ? "New Memoji" : "Memoji Studio")
                    .font(.headline)
            }
            
            Spacer()
            
            // Memoji Name Field
            HStack(spacing: 6) {
                Image(systemName: "pencil")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                TextField("Avatar Name", text: $avatarName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 140)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            
            // Revert changes button if edits were made
            if hasUnsavedChanges {
                Button(action: revertChanges) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 10))
                        Text("Revert")
                            .font(.system(size: 11.5))
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("Revert changes back to original")
            }
            
            // Randomize Button
            Button(action: randomizeAvatar) {
                HStack(spacing: 4) {
                    Image(systemName: "dice")
                        .font(.system(size: 11))
                    Text("Randomize")
                        .font(.system(size: 11.5))
                }
            }
            .buttonStyle(.bordered)
            .help("Randomly generate all features (⌘R)")
            
            // Cancel Button
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
            
            // Save Button
            Button(action: {
                let trimmed = avatarName.trimmingCharacters(in: .whitespacesAndNewlines)
                let finalName = trimmed.isEmpty ? "My Memoji" : trimmed
                onSave(finalName, editingAvatar)
            }) {
                Text(isNew ? "Save Memoji" : "Done")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    // MARK: - Stage Pane (Left)
    
    private var stagePane: some View {
        VStack(spacing: 0) {
            ZStack {
                // Subtle studio vignette background
                RadialGradient(
                    colors: [
                        Color.accentColor.opacity(0.10),
                        Color(nsColor: .windowBackgroundColor)
                    ],
                    center: .center,
                    startRadius: 30,
                    endRadius: 350
                )
                
                // Live 3D AVTView (clone: false keeps it bound to our mutable editingAvatar)
                Avatar3DStageRepresentable(
                    avatar: editingAvatar,
                    activePoseName: previewPose,
                    clone: false,
                    mutationId: mutationId,
                    stageController: stageController,
                    onDoubleTap: {
                        if let view = stageController.avtView {
                            AvatarKitBridge.shared.applyCanonicalCameraFraming(to: view, animated: true, duration: 0.25)
                        }
                    }
                )
                .padding(16)
                
                // Camera reset and navigation hints
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        HStack(spacing: 5) {
                            Image(systemName: "hand.draw")
                                .font(.system(size: 10))
                            Text("Drag to rotate • Scroll to zoom")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.secondary)
                        
                        Divider().frame(height: 10)
                        
                        Button(action: {
                            if let view = stageController.avtView {
                                AvatarKitBridge.shared.resetCameraFraming(on: view)
                            }
                            previewPose = nil
                            mutationId = UUID()
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 9))
                                Text("Reset View")
                                    .font(.system(size: 10, weight: .medium))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.bottom, 10)
                }
            }
            
            Divider()
            
            // Expression Previewer Bar
            expressionBar
        }
    }
    
    // MARK: - Expression Bar
    
    private var expressionBar: some View {
        HStack(spacing: 8) {
            Text("Preview:")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    expressionChip(title: "Neutral", emoji: "🙂", pose: nil)
                    expressionChip(title: "Smile", emoji: "😄", pose: "big_happy")
                    expressionChip(title: "Wink", emoji: "😉", pose: "winking_face")
                    expressionChip(title: "Heart Eyes", emoji: "😍", pose: "smiling_face_with_heart-shaped_eyes")
                    expressionChip(title: "Think", emoji: "🤔", pose: "thinking_face")
                    expressionChip(title: "Thumbs Up", emoji: "👍", pose: "thumbs_up")
                    expressionChip(title: "Celebration", emoji: "🥳", pose: "face_with_party_horn")
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    private func expressionChip(title: String, emoji: String, pose: String?) -> some View {
        let isSelected = previewPose == pose
        return Button(action: {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                previewPose = pose
            }
        }) {
            HStack(spacing: 4) {
                Text(emoji)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .bold : .regular))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? Color.accentColor : Color(nsColor: .windowBackgroundColor))
            .foregroundColor(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Controls Pane (Right)
    
    private var controlsPane: some View {
        VStack(spacing: 0) {
            // Category Selector Tabs
            categorySelectorBar
            
            Divider()
            
            // Active Category Content (Color Palette + Presets Grid)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Color Palette Section (if category supports colors)
                    if selectedCategory.hasColors {
                        colorPaletteSection
                    }
                    
                    // Style Presets Section
                    presetsSection
                }
                .padding(20)
            }
        }
    }
    
    // MARK: - Category Selector Bar
    
    private var categorySelectorBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(CustomizerCategory.allCases) { category in
                    let isSelected = selectedCategory == category
                    Button(action: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            selectedCategory = category
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: category.iconName)
                                .font(.system(size: 11))
                            Text(category.title)
                                .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor).opacity(0.8))
                        .foregroundColor(isSelected ? .white : .primary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Color Palette Section
    
    private var colorPaletteSection: some View {
        let colors = MemojiCustomizer.shared.availableColors(for: selectedCategory)
        
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(selectedCategory.title) Tone / Color")
                    .font(.system(size: 13, weight: .bold))
                
                Spacer()
                
                if let active = activeColorName {
                    HStack(spacing: 4) {
                        Text(active)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 38, maximum: 44), spacing: 10)], spacing: 10) {
                ForEach(colors) { option in
                    let isSelected = activeColorName == option.name
                    Button(action: {
                        MemojiCustomizer.shared.apply(color: option, to: editingAvatar)
                        activeColorName = option.name
                        mutationId = UUID()
                        hasUnsavedChanges = true
                    }) {
                        ZStack {
                            Circle()
                                .fill(option.color)
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                                )
                            
                            if isSelected {
                                Circle()
                                    .strokeBorder(Color.accentColor, lineWidth: 3)
                                    .frame(width: 38, height: 38)
                                
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(checkmarkColor(for: option.nsColor))
                            }
                        }
                        .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .help(option.localizedName)
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    // MARK: - Presets Section
    
    private var presetsSection: some View {
        let allPresets = MemojiCustomizer.shared.availablePresets(for: selectedCategory)
        let filtered = filteredPresets(from: allPresets)
        let hasNoneOption = allPresets.contains { $0.id.lowercased() == "none" }
        
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(selectedCategory.title) Style")
                    .font(.system(size: 13, weight: .bold))
                
                Text("(\(allPresets.count))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // "Remove / None" quick button if applicable
                if hasNoneOption && activePresetId?.lowercased() != "none" {
                    Button(action: clearCurrentCategoryPreset) {
                        HStack(spacing: 3) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9))
                            Text("Remove")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .foregroundColor(.secondary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Remove \(selectedCategory.title)")
                }
                
                Spacer()
                
                // Search bar if category has more than 6 presets
                if allPresets.count > 6 {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        TextField("Filter styles...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                            .frame(width: 110)
                        
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(Capsule())
                }
            }
            
            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                    Text("No styles match '\(searchText)'")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92, maximum: 110), spacing: 10)], spacing: 12) {
                    ForEach(filtered) { preset in
                        PresetCardView(
                            preset: preset,
                            isSelected: activePresetId == preset.id,
                            onSelect: {
                                MemojiCustomizer.shared.apply(preset: preset, to: editingAvatar)
                                activePresetId = preset.id
                                mutationId = UUID()
                                hasUnsavedChanges = true
                            }
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - Actions & Helpers
    
    private func filteredPresets(from presets: [PresetOption]) -> [PresetOption] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty { return presets }
        return presets.filter {
            $0.localizedName.lowercased().contains(query) ||
            $0.id.lowercased().contains(query)
        }
    }
    
    private func syncActiveSelections() {
        activePresetId = MemojiCustomizer.shared.currentPresetIdentifier(for: selectedCategory, in: editingAvatar)
        activeColorName = MemojiCustomizer.shared.currentColorName(for: selectedCategory, in: editingAvatar)
    }
    
    private func randomizeAvatar() {
        MemojiCustomizer.shared.randomize(memoji: editingAvatar)
        mutationId = UUID()
        hasUnsavedChanges = true
        syncActiveSelections()
    }
    
    private func revertChanges() {
        let freshClone = AvatarKitBridge.shared.cloneAvatar(initialAvatar) ?? initialAvatar
        self.editingAvatar = freshClone
        self.avatarName = initialName
        self.hasUnsavedChanges = false
        self.mutationId = UUID()
        syncActiveSelections()
    }
    
    private func clearCurrentCategoryPreset() {
        let presets = MemojiCustomizer.shared.availablePresets(for: selectedCategory)
        if let nonePreset = presets.first(where: { $0.id.lowercased() == "none" }) {
            MemojiCustomizer.shared.apply(preset: nonePreset, to: editingAvatar)
            activePresetId = nonePreset.id
            mutationId = UUID()
            hasUnsavedChanges = true
        }
    }
    
    private func checkmarkColor(for color: NSColor) -> Color {
        guard let rgb = color.usingColorSpace(.sRGB) else { return .white }
        let brightness = (rgb.redComponent * 299 + rgb.greenComponent * 587 + rgb.blueComponent * 114) / 1000
        return brightness > 0.6 ? .black : .white
    }
}
