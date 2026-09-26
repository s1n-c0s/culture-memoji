import SwiftUI
import AppKit

public struct CharacterCardView: View {
    public let item: AvatarItem
    public let avatarObject: AnyObject?
    public let isSelected: Bool
    public let isFavorite: Bool
    public let onSelect: () -> Void
    public let onToggleFavorite: () -> Void
    public let onEdit: () -> Void
    public let onDuplicate: (() -> Void)?
    public let onDelete: (() -> Void)?
    public let onRename: (() -> Void)?
    
    @State private var thumbnail: NSImage?
    @State private var isHovered: Bool = false
    
    public init(
        item: AvatarItem,
        avatarObject: AnyObject?,
        isSelected: Bool,
        isFavorite: Bool,
        onSelect: @escaping () -> Void,
        onToggleFavorite: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onDuplicate: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        onRename: (() -> Void)? = nil
    ) {
        self.item = item
        self.avatarObject = avatarObject
        self.isSelected = isSelected
        self.isFavorite = isFavorite
        self.onSelect = onSelect
        self.onToggleFavorite = onToggleFavorite
        self.onEdit = onEdit
        self.onDuplicate = onDuplicate
        self.onDelete = onDelete
        self.onRename = onRename
    }
    
    public var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .bottom) {
                // Card Background
                AppTheme.cardBackground
                
                // Centered Avatar Thumbnail
                if let img = thumbnail {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(14)
                } else {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
                // Bottom controls inside card (Star & Edit)
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
                    
                    // Edit pencil button
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color.black.opacity(isHovered ? 0.9 : 0.7))
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Customize Memoji")
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
            Button(action: onEdit) {
                Label("Customize Memoji...", systemImage: "pencil")
            }
            
            if let onRen = onRename {
                Button(action: onRen) {
                    Label("Rename...", systemImage: "pencil.line")
                }
            }
            
            if let onDup = onDuplicate {
                Button(action: onDup) {
                    Label("Duplicate Memoji", systemImage: "doc.on.doc")
                }
            }
            
            Button(action: onToggleFavorite) {
                Label(isFavorite ? "Unfavorite" : "Favorite", systemImage: isFavorite ? "star.slash" : "star")
            }
            
            if let onDel = onDelete {
                Divider()
                Button(role: .destructive, action: onDel) {
                    Label("Delete Memoji", systemImage: "trash")
                }
            }
        }
        .task(id: item.id) {
            thumbnail = await ThumbnailCache.shared.getThumbnail(for: item, avatarObject: avatarObject)
        }
    }
}

public struct CharacterListRowView: View {
    public let item: AvatarItem
    public let avatarObject: AnyObject?
    public let isSelected: Bool
    public let isFavorite: Bool
    public let onSelect: () -> Void
    public let onToggleFavorite: () -> Void
    public let onEdit: () -> Void
    
    @State private var thumbnail: NSImage?
    
    public init(
        item: AvatarItem,
        avatarObject: AnyObject?,
        isSelected: Bool,
        isFavorite: Bool,
        onSelect: @escaping () -> Void,
        onToggleFavorite: @escaping () -> Void,
        onEdit: @escaping () -> Void
    ) {
        self.item = item
        self.avatarObject = avatarObject
        self.isSelected = isSelected
        self.isFavorite = isFavorite
        self.onSelect = onSelect
        self.onToggleFavorite = onToggleFavorite
        self.onEdit = onEdit
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
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.black)
                    
                    Text(subtitleFor(item))
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
                
                Button(action: onEdit) {
                    Image(systemName: "pencil")
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
        .task(id: item.id) {
            thumbnail = await ThumbnailCache.shared.getThumbnail(for: item, avatarObject: avatarObject)
        }
    }
    
    private func subtitleFor(_ item: AvatarItem) -> String {
        switch item.sourceType {
        case .userMemoji: return "System Memoji"
        case .customMemoji: return "Studio Memoji"
        case .builtinAnimoji: return "Apple Animoji"
        case .randomMemoji: return "Generated Memoji"
        }
    }
}
