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
    }
    
    public var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .bottom) {
                // Card Background
                AppTheme.cardBackground
                
                // Centered Posed Sticker Image
                if let img = thumbnail {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(14)
                } else {
                    VStack(spacing: 4) {
                        Text(sticker.emoji)
                            .font(.system(size: 28))
                        ProgressView()
                            .scaleEffect(0.6)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
                // Bottom row inside card (Star & Label/Emoji)
                HStack {
                    // Star button
                    Button(action: onToggleFavorite) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(isFavorite ? Color.black : Color.black.opacity(isHovered ? 0.7 : 0.45))
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(isFavorite ? "Remove from favorites" : "Add to favorites")
                    
                    Spacer()
                    
                    // Emoji / Title hint
                    Text(sticker.emoji)
                        .font(.system(size: 13))
                        .opacity(0.85)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
            .aspectRatio(1.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.black : Color.black.opacity(0.12), lineWidth: isSelected ? 3 : 1)
            )
            .shadow(color: isSelected ? Color.black.opacity(0.2) : Color.clear, radius: 4, x: 0, y: 2)
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
            
            Button(action: onToggleFavorite) {
                Label(isFavorite ? "Unfavorite" : "Favorite", systemImage: isFavorite ? "star.slash" : "star")
            }
        }
        .task(id: "\(sticker.name)_\(avatarObject != nil ? UInt(bitPattern: ObjectIdentifier(avatarObject!)) : 0)") {
            thumbnail = await ThumbnailCache.shared.getEmoteThumbnail(
                sticker: sticker,
                avatarObject: avatarObject,
                isAnimoji: isAnimoji,
                animojiName: animojiName
            )
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
    }
    
    public var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Thumbnail Box
                ZStack {
                    AppTheme.cardBackground
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
                .clipShape(RoundedRectangle(cornerRadius: 6))
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(sticker.emoji)
                            .font(.system(size: 13))
                        Text(sticker.localizedTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.black)
                    }
                    
                    Text(sticker.category.rawValue)
                        .font(.system(size: 11))
                        .foregroundColor(Color.black.opacity(0.6))
                }
                
                Spacer()
                
                Button(action: onToggleFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isFavorite ? .black : Color.black.opacity(0.4))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.black.opacity(0.6))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.black.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.black : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .task(id: "\(sticker.name)_\(avatarObject != nil ? UInt(bitPattern: ObjectIdentifier(avatarObject!)) : 0)") {
            thumbnail = await ThumbnailCache.shared.getEmoteThumbnail(
                sticker: sticker,
                avatarObject: avatarObject,
                isAnimoji: isAnimoji,
                animojiName: animojiName
            )
        }
    }
}
