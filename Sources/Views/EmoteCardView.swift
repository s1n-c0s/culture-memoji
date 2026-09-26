import SwiftUI
import AppKit

public struct EmoteCardView: View {
    public let sticker: StickerItem
    public let avatarObject: AnyObject?
    public let isAnimoji: Bool
    public let animojiName: String?
    public let isSelected: Bool
    public let isFavorite: Bool
    public let onSelect: () -> Void
    public let onToggleFavorite: () -> Void
    public let onCopy: () -> Void
    
    @State private var thumbnail: NSImage?
    @State private var isHovered: Bool = false
    
    public init(
        sticker: StickerItem,
        avatarObject: AnyObject?,
        isAnimoji: Bool,
        animojiName: String?,
        isSelected: Bool,
        isFavorite: Bool,
        onSelect: @escaping () -> Void,
        onToggleFavorite: @escaping () -> Void,
        onCopy: @escaping () -> Void
    ) {
        self.sticker = sticker
        self.avatarObject = avatarObject
        self.isAnimoji = isAnimoji
        self.animojiName = animojiName
        self.isSelected = isSelected
        self.isFavorite = isFavorite
        self.onSelect = onSelect
        self.onToggleFavorite = onToggleFavorite
        self.onCopy = onCopy
        self._thumbnail = State(initialValue: ThumbnailCache.shared.cachedEmoteThumbnail(for: sticker))
    }
    
    public var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .bottom) {
                // Card Canvas Background
                RoundedRectangle(cornerRadius: 14)
                    .fill(AppTheme.cardBackground)
                
                // Subtle Ambient Spotlight inside Card
                RadialGradient(
                    colors: [
                        Color.primary.opacity(isHovered ? 0.05 : 0.02),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 20,
                    endRadius: 90
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
                
                // Centered Posed Sticker Image
                if let img = thumbnail {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(14)
                        .shadow(color: Color.black.opacity(isHovered ? 0.12 : 0.05), radius: 6, x: 0, y: 3)
                } else {
                    VStack(spacing: 4) {
                        Text(sticker.emoji)
                            .font(.system(size: 26))
                        ProgressView()
                            .scaleEffect(0.6)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
                // Bottom row inside card (Star & Emoji / Title)
                HStack {
                    // Star button
                    Button(action: onToggleFavorite) {
                        ZStack {
                            Circle()
                                .fill(isFavorite ? AppTheme.goldColor.opacity(0.18) : (isHovered ? Color.primary.opacity(0.08) : Color.clear))
                                .frame(width: 26, height: 26)
                            
                            Image(systemName: isFavorite ? "star.fill" : "star")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(isFavorite ? AppTheme.goldColor : (isHovered ? Color.primary.opacity(0.8) : Color.primary.opacity(0.35)))
                        }
                    }
                    .buttonStyle(.plain)
                    .help(isFavorite ? "Remove from favorites" : "Add to favorites")
                    
                    Spacer()
                    
                    // Emoji / Title badge
                    Text(sticker.emoji)
                        .font(.system(size: 13))
                        .opacity(isHovered ? 1.0 : 0.75)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .aspectRatio(1.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isSelected ? Color.accentColor : (isHovered ? Color.primary.opacity(0.15) : Color.primary.opacity(0.06)),
                        lineWidth: isSelected ? 2.5 : 1
                    )
            )
            .shadow(
                color: isSelected ? Color.accentColor.opacity(0.22) : (isHovered ? Color.black.opacity(0.08) : Color.black.opacity(0.02)),
                radius: isSelected ? 8 : (isHovered ? 6 : 2),
                x: 0,
                y: isSelected ? 3 : (isHovered ? 3 : 1)
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isHovered)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isSelected)
        }
        .buttonStyle(.plain)
        .onHover { h in
            isHovered = h
        }
        .contextMenu {
            Button(action: onSelect) {
                Label("Animate Pose on Stage", systemImage: "sparkles")
            }
            
            Button(action: onCopy) {
                Label("Copy Sticker PNG", systemImage: "doc.on.doc")
            }
            
            Divider()
            
            Button(action: onToggleFavorite) {
                Label(isFavorite ? "Unfavorite" : "Favorite", systemImage: isFavorite ? "star.slash" : "star")
            }
        }
        .task(id: sticker.id) {
            if thumbnail == nil {
                thumbnail = await ThumbnailCache.shared.getEmoteThumbnail(
                    sticker: sticker,
                    avatarObject: avatarObject,
                    isAnimoji: isAnimoji,
                    animojiName: animojiName
                )
            }
        }
    }
}

public struct EmoteListRowView: View {
    public let sticker: StickerItem
    public let avatarObject: AnyObject?
    public let isAnimoji: Bool
    public let animojiName: String?
    public let isSelected: Bool
    public let isFavorite: Bool
    public let onSelect: () -> Void
    public let onToggleFavorite: () -> Void
    public let onCopy: () -> Void
    
    @State private var thumbnail: NSImage?
    @State private var isHovered: Bool = false
    
    public init(
        sticker: StickerItem,
        avatarObject: AnyObject?,
        isAnimoji: Bool,
        animojiName: String?,
        isSelected: Bool,
        isFavorite: Bool,
        onSelect: @escaping () -> Void,
        onToggleFavorite: @escaping () -> Void,
        onCopy: @escaping () -> Void
    ) {
        self.sticker = sticker
        self.avatarObject = avatarObject
        self.isAnimoji = isAnimoji
        self.animojiName = animojiName
        self.isSelected = isSelected
        self.isFavorite = isFavorite
        self.onSelect = onSelect
        self.onToggleFavorite = onToggleFavorite
        self.onCopy = onCopy
        self._thumbnail = State(initialValue: ThumbnailCache.shared.cachedEmoteThumbnail(for: sticker))
    }
    
    public var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Thumbnail Box
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppTheme.cardBackground)
                    
                    if let img = thumbnail {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(4)
                    } else {
                        Text(sticker.emoji)
                            .font(.system(size: 18))
                    }
                }
                .frame(width: 44, height: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(sticker.emoji)
                            .font(.system(size: 13))
                        Text(sticker.localizedTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                    
                    Text(sticker.category.rawValue)
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: onToggleFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(isFavorite ? AppTheme.goldColor : Color.primary.opacity(0.35))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.primary.opacity(0.6))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : (isHovered ? Color.primary.opacity(0.04) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { h in isHovered = h }
        .task(id: sticker.id) {
            if thumbnail == nil {
                thumbnail = await ThumbnailCache.shared.getEmoteThumbnail(
                    sticker: sticker,
                    avatarObject: avatarObject,
                    isAnimoji: isAnimoji,
                    animojiName: animojiName
                )
            }
        }
    }
}
