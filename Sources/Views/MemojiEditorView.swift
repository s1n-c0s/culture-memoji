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
        
        // Clone initial avatar to work on an isolated editing copy
        let cloned = AvatarKitBridge.shared.cloneAvatar(avatar) ?? avatar
        self._editingAvatar = State(initialValue: cloned)
        self._avatarName = State(initialValue: name)
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
                    .frame(minWidth: 340, maxWidth: 440)
                
                Divider()
                
                // Right: Customization Controls
                controlsPane
                    .frame(minWidth: 440, maxWidth: .infinity)
            }
        }
        .frame(minWidth: 880, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            syncActiveSelections()
        }
        .onChange(of: selectedCategory) { _, _ in
            searchText = ""
            syncActiveSelections()
        }
    }
    
    // MARK: - Header Bar
    
    private var headerBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: isNew ? "sparkles" : "pencil.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(isNew ? "Create New Memoji" : "Customize Memoji")
                        .font(.headline)
                    Text("Real-time 3D styling and configuration")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Memoji Name Field
            HStack(spacing: 6) {
                Text("Name:")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                TextField("Avatar Name", text: $avatarName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
            }
            
            // Randomize Button
            Button(action: randomizeAvatar) {
                Label("Randomize", systemImage: "dice.fill")
                    .font(.system(size: 12))
            }
            .help("Randomly generate all features")
            
            // Cancel Button
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
            
            // Save Button
            Button(action: {
                let trimmed = avatarName.trimmingCharacters(in: .whitespacesAndNewlines)
                let finalName = trimmed.isEmpty ? "My Memoji" : trimmed
                onSave(finalName, editingAvatar)
            }) {
                Text(isNew ? "Save Memoji" : "Save Changes")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    // MARK: - Stage Pane (Left)
    
    private var stagePane: some View {
        VStack(spacing: 0) {
            ZStack {
                // Subtle gradient background
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.08),
                        Color(nsColor: .windowBackgroundColor)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                
                // Live 3D AVTView (clone: false keeps it bound to our mutable editingAvatar)
                Avatar3DStageRepresentable(
                    avatar: editingAvatar,
                    activePoseName: previewPose,
                    clone: false,
                    mutationId: mutationId
                )
                .padding(16)
                
                // Interaction hint at bottom
                VStack {
                    Spacer()
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
                    .padding(.bottom, 12)
                }
            }
            
            Divider()
            
            // Quick Expression Tester Bar
            expressionBar
        }
    }
    
    // MARK: - Expression Bar
    
    private var expressionBar: some View {
        HStack(spacing: 8) {
            Text("Preview Expression:")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    expressionChip(title: "Neutral", emoji: "🙂", pose: nil)
                    expressionChip(title: "Smile", emoji: "😄", pose: "big_happy")
                    expressionChip(title: "Wink", emoji: "😉", pose: "winking_face")
                    expressionChip(title: "Heart Eyes", emoji: "😍", pose: "smiling_face_with_heart-shaped_eyes")
                    expressionChip(title: "Thinking", emoji: "🤔", pose: "thinking_face")
                    expressionChip(title: "Thumbs Up", emoji: "👍", pose: "thumbs_up")
                    expressionChip(title: "Mind Blown", emoji: "🤯", pose: "exploding_head")
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    private func expressionChip(title: String, emoji: String, pose: String?) -> some View {
        let isSelected = previewPose == pose
        return Button(action: {
            previewPose = pose
        }) {
            HStack(spacing: 4) {
                Text(emoji)
                    .font(.system(size: 12))
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
                        selectedCategory = category
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: category.iconName)
                                .font(.system(size: 13))
                            Text(category.title)
                                .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(isSelected ? Color.accentColor : Color.clear)
                        .foregroundColor(isSelected ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    // MARK: - Color Palette Section
    
    private var colorPaletteSection: some View {
        let colors = MemojiCustomizer.shared.availableColors(for: selectedCategory)
        
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(selectedCategory.title) Color")
                    .font(.system(size: 13, weight: .bold))
                
                Spacer()
                
                if let active = activeColorName {
                    Text(active)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 38, maximum: 44), spacing: 10)], spacing: 10) {
                ForEach(colors) { option in
                    let isSelected = activeColorName == option.name
                    Button(action: {
                        MemojiCustomizer.shared.apply(color: option, to: editingAvatar)
                        activeColorName = option.name
                        mutationId = UUID()
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
        
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(selectedCategory.title) Style")
                    .font(.system(size: 13, weight: .bold))
                
                Text("(\(allPresets.count))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Search bar if category has more than 8 presets
                if allPresets.count > 8 {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        TextField("Filter...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                            .frame(width: 120)
                        
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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 220), spacing: 8)], spacing: 8) {
                    ForEach(filtered) { preset in
                        let isSelected = activePresetId == preset.id
                        Button(action: {
                            MemojiCustomizer.shared.apply(preset: preset, to: editingAvatar)
                            activePresetId = preset.id
                            mutationId = UUID()
                        }) {
                            HStack(spacing: 8) {
                                if preset.id.lowercased() == "none" {
                                    Image(systemName: "slash.circle")
                                        .font(.system(size: 13))
                                        .foregroundColor(isSelected ? .white : .secondary)
                                }
                                
                                Text(preset.localizedName)
                                    .font(.system(size: 11, weight: isSelected ? .bold : .regular))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                
                                Spacer(minLength: 4)
                                
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                            .foregroundColor(isSelected ? .white : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(isSelected ? Color.clear : Color.primary.opacity(0.06), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
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
        syncActiveSelections()
    }
    
    private func checkmarkColor(for color: NSColor) -> Color {
        guard let rgb = color.usingColorSpace(.sRGB) else { return .white }
        let brightness = (rgb.redComponent * 299 + rgb.greenComponent * 587 + rgb.blueComponent * 114) / 1000
        return brightness > 0.6 ? .black : .white
    }
}
