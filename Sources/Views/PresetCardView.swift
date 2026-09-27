import SwiftUI
import AppKit

/// A visual card representing a Memoji preset (e.g. hairstyle, glasses shape, beard)
/// featuring a high-fidelity 3D rendered preview thumbnail, title, and interactive selection.
public struct PresetCardView: View {
    public let preset: PresetOption
    public let isSelected: Bool
    public let onSelect: () -> Void
    
    @State private var thumbnail: NSImage?
    @State private var isHovering: Bool = false
    @State private var isLoading: Bool = false
    
    public init(
        preset: PresetOption,
        isSelected: Bool,
        onSelect: @escaping () -> Void
    ) {
        self.preset = preset
        self.isSelected = isSelected
        self.onSelect = onSelect
        let cached = PresetThumbnailManager.shared.cachedThumbnail(for: preset)
        self._thumbnail = State(initialValue: cached)
    }
    
    private var isNoneOption: Bool {
        preset.id.lowercased() == "none"
    }
    
    public var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 6) {
                // 3D Preview Thumbnail Canvas
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
                    
                    if isNoneOption {
                        // Minimalist "None / Remove" icon
                        VStack(spacing: 4) {
                            Image(systemName: "slash.circle")
                                .font(.system(size: 26, weight: .light))
                                .foregroundColor(isSelected ? Color.accentColor : Color.secondary)
                            Text("None")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(isSelected ? Color.accentColor : Color.secondary)
                        }
                    } else if let img = thumbnail {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 72, height: 72)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    } else {
                        // Category silhouette placeholder while rendering in background
                        VStack(spacing: 5) {
                            Image(systemName: preset.category.iconName)
                                .font(.system(size: 22))
                                .foregroundColor(.secondary.opacity(0.45))
                            
                            ProgressView()
                                .scaleEffect(0.55)
                                .opacity(0.7)
                        }
                        .frame(width: 72, height: 72)
                    }
                    
                    // Selected checkmark badge in top-right corner
                    if isSelected {
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.accentColor)
                                    .background(Circle().fill(Color.white).padding(1.5))
                                    .offset(x: 3, y: -3)
                            }
                            Spacer()
                        }
                    }
                }
                .frame(width: 78, height: 78)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            isSelected ? Color.accentColor : (isHovering ? Color.primary.opacity(0.20) : Color.primary.opacity(0.06)),
                            lineWidth: isSelected ? 2.2 : 1
                        )
                )
                
                // Style Title Caption
                Text(preset.localizedName)
                    .font(.system(size: 10.5, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .accentColor : .primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 28, alignment: .top)
                    .padding(.horizontal, 2)
            }
            .padding(6)
            .frame(width: 90)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor.opacity(0.06) : (isHovering ? Color.primary.opacity(0.04) : Color.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(SpringPressButtonStyle(scale: 0.95))
        .onHover { h in isHovering = h }
        .help(preset.localizedName)
        .task(id: preset.id) {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        if isNoneOption { return }
        
        // Instant check (memory or disk cache)
        if let cached = PresetThumbnailManager.shared.cachedThumbnail(for: preset) {
            self.thumbnail = cached
            return
        }
        
        // Background load
        isLoading = true
        Task {
            let img = await PresetThumbnailManager.shared.loadThumbnail(for: preset)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.16)) {
                    self.thumbnail = img
                    self.isLoading = false
                }
            }
        }
    }
}
