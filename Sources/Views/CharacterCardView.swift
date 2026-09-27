import SwiftUI
import AppKit

public struct CharacterCardView: View {
    public let item: AvatarItem
    public let avatarObject: AnyObject?
    public let isSelected: Bool
    public let isFavorite: Bool
    public let isSelectionMode: Bool
    public let isMarked: Bool
    public let isBeingDragged: Bool
    public let hasCustomOrder: Bool
    public let onSelect: () -> Void
    public let onToggleFavorite: () -> Void
    public let onEdit: () -> Void
    public let onDuplicate: (() -> Void)?
    public let onDelete: (() -> Void)?
    public let onRename: (() -> Void)?
    public let onHoldClick: (() -> Void)?
    public let onEnterSelectionMode: (() -> Void)?
    public let onMoveToTop: (() -> Void)?
    public let onMoveToBottom: (() -> Void)?
    public let onMoveForward: (() -> Void)?
    public let onMoveBackward: (() -> Void)?
    public let onResetOrder: (() -> Void)?
    
    @State private var thumbnail: NSImage?
    @State private var isHovered: Bool = false
    @State private var isHolding: Bool = false
    
    public init(
        item: AvatarItem,
        avatarObject: AnyObject?,
        isSelected: Bool,
        isFavorite: Bool,
        isSelectionMode: Bool = false,
        isMarked: Bool = false,
        isBeingDragged: Bool = false,
        hasCustomOrder: Bool = false,
        onSelect: @escaping () -> Void,
        onToggleFavorite: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onDuplicate: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        onRename: (() -> Void)? = nil,
        onHoldClick: (() -> Void)? = nil,
        onEnterSelectionMode: (() -> Void)? = nil,
        onMoveToTop: (() -> Void)? = nil,
        onMoveToBottom: (() -> Void)? = nil,
        onMoveForward: (() -> Void)? = nil,
        onMoveBackward: (() -> Void)? = nil,
        onResetOrder: (() -> Void)? = nil
    ) {
        self.item = item
        self.avatarObject = avatarObject
        self.isSelected = isSelected
        self.isFavorite = isFavorite
        self.isSelectionMode = isSelectionMode
        self.isMarked = isMarked
        self.isBeingDragged = isBeingDragged
        self.hasCustomOrder = hasCustomOrder
        self.onSelect = onSelect
        self.onToggleFavorite = onToggleFavorite
        self.onEdit = onEdit
        self.onDuplicate = onDuplicate
        self.onDelete = onDelete
        self.onRename = onRename
        self.onHoldClick = onHoldClick
        self.onEnterSelectionMode = onEnterSelectionMode
        self.onMoveToTop = onMoveToTop
        self.onMoveToBottom = onMoveToBottom
        self.onMoveForward = onMoveForward
        self.onMoveBackward = onMoveBackward
        self.onResetOrder = onResetOrder
        self._thumbnail = State(initialValue: ThumbnailCache.shared.cachedImage(forKey: "avatar_\(item.id)"))
    }
    
    private var cardBorderColor: Color {
        if isHolding {
            return Color.accentColor.opacity(0.8)
        }
        if isSelectionMode && isMarked {
            return Color.accentColor
        }
        if isSelected && !isSelectionMode {
            return Color.accentColor
        }
        return isHovered ? Color.primary.opacity(0.15) : Color.primary.opacity(0.06)
    }
    
    private var cardBorderWidth: CGFloat {
        if isHolding { return 2 }
        if (isSelectionMode && isMarked) || (isSelected && !isSelectionMode) { return 2.5 }
        return 1
    }
    
    private var cardShadowColor: Color {
        if isBeingDragged { return Color.clear }
        if isHolding { return Color.accentColor.opacity(0.35) }
        if (isSelectionMode && isMarked) || (isSelected && !isSelectionMode) {
            return Color.accentColor.opacity(0.22)
        }
        return isHovered ? Color.black.opacity(0.08) : Color.black.opacity(0.02)
    }
    
    private var cardShadowRadius: CGFloat {
        if isHolding { return 14 }
        if (isSelectionMode && isMarked) || (isSelected && !isSelectionMode) { return 8 }
        return isHovered ? 6 : 2
    }
    
    private var cardShadowY: CGFloat {
        if isHolding { return 5 }
        if (isSelectionMode && isMarked) || (isSelected && !isSelectionMode) { return 3 }
        return isHovered ? 3 : 1
    }
    
    private var cardScale: CGFloat {
        if isBeingDragged { return 0.95 }
        if isHolding { return 1.05 }
        return isHovered ? 1.02 : 1.0
    }
    
    public var body: some View {
        ZStack(alignment: .bottom) {
            // Card Canvas Background
            RoundedRectangle(cornerRadius: 14)
                .fill(AppTheme.cardBackground)
            
            // Subtle Ambient Spotlight inside Card
            RadialGradient(
                colors: [
                    Color.primary.opacity(isHolding ? 0.08 : (isHovered ? 0.05 : 0.02)),
                    Color.clear
                ],
                center: .center,
                startRadius: 20,
                endRadius: 90
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            
            // Centered Avatar Headshot
            if let img = thumbnail {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(14)
                    .shadow(color: Color.black.opacity(isHovered ? 0.12 : 0.05), radius: 6, x: 0, y: 3)
            } else {
                ProgressView()
                    .scaleEffect(0.65)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            // Bottom floating action badges (Star & Edit) - shown when not in batch selection mode
            if !isSelectionMode {
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
                    
                    // Edit pencil button
                    Button(action: onEdit) {
                        ZStack {
                            Circle()
                                .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
                                .frame(width: 26, height: 26)
                            
                            Image(systemName: "pencil")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(isHovered ? Color.primary.opacity(0.9) : Color.primary.opacity(0.4))
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Customize 3D Memoji")
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            
            // Selection Mark Indicator (Top-Leading) - shown in selection mode
            if isSelectionMode {
                VStack {
                    HStack {
                        ZStack {
                            Circle()
                                .fill(isMarked ? Color.accentColor : Color.black.opacity(0.35))
                                .frame(width: 22, height: 22)
                            
                            if isMarked {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                            } else {
                                Circle()
                                    .stroke(Color.white.opacity(0.85), lineWidth: 1.5)
                                    .frame(width: 20, height: 20)
                            }
                        }
                        .shadow(color: Color.black.opacity(0.25), radius: 3, x: 0, y: 1)
                        
                        Spacer()
                        
                        if isFavorite {
                            Image(systemName: "star.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(AppTheme.goldColor)
                                .padding(4)
                        }
                    }
                    Spacer()
                }
                .padding(8)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .aspectRatio(1.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(cardBorderColor, lineWidth: cardBorderWidth)
        )
        .shadow(
            color: cardShadowColor,
            radius: cardShadowRadius,
            x: 0,
            y: cardShadowY
        )
        .scaleEffect(cardScale)
        .opacity(isBeingDragged ? 0.35 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isHovered)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isHolding)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isSelected)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isMarked)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isBeingDragged)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture {
            onSelect()
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4)
                .onEnded { _ in
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    onHoldClick?()
                }
        )
        .onHover { h in
            isHovered = h
        }
        .contextMenu {
            if isSelectionMode {
                Button(action: onSelect) {
                    Label(isMarked ? "Deselect" : "Select", systemImage: isMarked ? "circle" : "checkmark.circle")
                }
            } else {
                Button(action: { onEnterSelectionMode?() }) {
                    Label("Select Characters...", systemImage: "checkmark.circle")
                }
                
                Divider()
                
                Button(action: onEdit) {
                    Label("Customize Memoji...", systemImage: "paintbrush")
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
                
                Divider()
                
                // Reorder Model submenu
                Menu("Reorder Model") {
                    if let onTop = onMoveToTop {
                        Button(action: onTop) {
                            Label("Move to Top", systemImage: "arrow.up.to.line")
                        }
                    }
                    if let onBack = onMoveBackward {
                        Button(action: onBack) {
                            Label("Move Left (Earlier)", systemImage: "arrow.left")
                        }
                    }
                    if let onFwd = onMoveForward {
                        Button(action: onFwd) {
                            Label("Move Right (Later)", systemImage: "arrow.right")
                        }
                    }
                    if let onBottom = onMoveToBottom {
                        Button(action: onBottom) {
                            Label("Move to Bottom", systemImage: "arrow.down.to.line")
                        }
                    }
                    if hasCustomOrder, let onReset = onResetOrder {
                        Divider()
                        Button(action: onReset) {
                            Label("Reset Order to Default", systemImage: "arrow.counterclockwise")
                        }
                    }
                }
                
                Divider()
                
                Button(action: onToggleFavorite) {
                    Label(isFavorite ? "Unfavorite" : "Favorite", systemImage: isFavorite ? "star.slash" : "star")
                }
                
                if let onDel = onDelete {
                    Divider()
                    Button(role: .destructive, action: onDel) {
                        Label("Delete Character", systemImage: "trash")
                    }
                }
            }
        }
        .task(id: item.id) {
            if thumbnail == nil {
                thumbnail = await ThumbnailCache.shared.getThumbnail(for: item, avatarObject: avatarObject)
            }
        }
    }
}

public struct CharacterListRowView: View {
    public let item: AvatarItem
    public let avatarObject: AnyObject?
    public let isSelected: Bool
    public let isFavorite: Bool
    public let isSelectionMode: Bool
    public let isMarked: Bool
    public let isBeingDragged: Bool
    public let hasCustomOrder: Bool
    public let onSelect: () -> Void
    public let onToggleFavorite: () -> Void
    public let onEdit: () -> Void
    public let onRename: (() -> Void)?
    public let onDuplicate: (() -> Void)?
    public let onDelete: (() -> Void)?
    public let onHoldClick: (() -> Void)?
    public let onEnterSelectionMode: (() -> Void)?
    public let onMoveToTop: (() -> Void)?
    public let onMoveToBottom: (() -> Void)?
    public let onMoveForward: (() -> Void)?
    public let onMoveBackward: (() -> Void)?
    public let onResetOrder: (() -> Void)?
    
    @State private var thumbnail: NSImage?
    @State private var isHovered: Bool = false
    @State private var isHolding: Bool = false
    
    public init(
        item: AvatarItem,
        avatarObject: AnyObject?,
        isSelected: Bool,
        isFavorite: Bool,
        isSelectionMode: Bool = false,
        isMarked: Bool = false,
        isBeingDragged: Bool = false,
        hasCustomOrder: Bool = false,
        onSelect: @escaping () -> Void,
        onToggleFavorite: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onRename: (() -> Void)? = nil,
        onDuplicate: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        onHoldClick: (() -> Void)? = nil,
        onEnterSelectionMode: (() -> Void)? = nil,
        onMoveToTop: (() -> Void)? = nil,
        onMoveToBottom: (() -> Void)? = nil,
        onMoveForward: (() -> Void)? = nil,
        onMoveBackward: (() -> Void)? = nil,
        onResetOrder: (() -> Void)? = nil
    ) {
        self.item = item
        self.avatarObject = avatarObject
        self.isSelected = isSelected
        self.isFavorite = isFavorite
        self.isSelectionMode = isSelectionMode
        self.isMarked = isMarked
        self.isBeingDragged = isBeingDragged
        self.hasCustomOrder = hasCustomOrder
        self.onSelect = onSelect
        self.onToggleFavorite = onToggleFavorite
        self.onEdit = onEdit
        self.onRename = onRename
        self.onDuplicate = onDuplicate
        self.onDelete = onDelete
        self.onHoldClick = onHoldClick
        self.onEnterSelectionMode = onEnterSelectionMode
        self.onMoveToTop = onMoveToTop
        self.onMoveToBottom = onMoveToBottom
        self.onMoveForward = onMoveForward
        self.onMoveBackward = onMoveBackward
        self.onResetOrder = onResetOrder
        self._thumbnail = State(initialValue: ThumbnailCache.shared.cachedImage(forKey: "avatar_\(item.id)"))
    }
    
    private var rowBackgroundColor: Color {
        if isHolding {
            return Color.accentColor.opacity(0.18)
        }
        if (isSelectionMode && isMarked) || (isSelected && !isSelectionMode) {
            return Color.accentColor.opacity(0.12)
        }
        return isHovered ? Color.primary.opacity(0.04) : Color.clear
    }
    
    private var rowBorderColor: Color {
        if isHolding {
            return Color.accentColor.opacity(0.7)
        }
        if (isSelectionMode && isMarked) || (isSelected && !isSelectionMode) {
            return Color.accentColor.opacity(0.5)
        }
        return Color.clear
    }
    
    private var rowScale: CGFloat {
        if isBeingDragged { return 0.98 }
        if isHolding { return 1.02 }
        return 1.0
    }
    
    public var body: some View {
        HStack(spacing: 12) {
            // Selection mark indicator in list mode
            if isSelectionMode {
                ZStack {
                    Circle()
                        .fill(isMarked ? Color.accentColor : Color.clear)
                        .frame(width: 18, height: 18)
                    
                    if isMarked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(.white)
                    } else {
                        Circle()
                            .stroke(Color.secondary.opacity(0.5), lineWidth: 1.5)
                            .frame(width: 16, height: 16)
                    }
                }
                .transition(.scale.combined(with: .opacity))
            }
            
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
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }
            .frame(width: 44, height: 44)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text(subtitleFor(item))
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if !isSelectionMode {
                Button(action: onToggleFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(isFavorite ? AppTheme.goldColor : Color.primary.opacity(0.35))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.primary.opacity(0.6))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                
                // Reorder handle grip indicator
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.primary.opacity(isHovered ? 0.35 : 0.15))
                    .frame(width: 16, height: 28)
                    .help("Hold & drag to reorder")
            } else if isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(AppTheme.goldColor)
                    .padding(.trailing, 4)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(rowBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(rowBorderColor, lineWidth: 1)
        )
        .scaleEffect(rowScale)
        .opacity(isBeingDragged ? 0.35 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isHolding)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isBeingDragged)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            onSelect()
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4)
                .onEnded { _ in
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    onHoldClick?()
                }
        )
        .onHover { h in isHovered = h }
        .contextMenu {
            if isSelectionMode {
                Button(action: onSelect) {
                    Label(isMarked ? "Deselect" : "Select", systemImage: isMarked ? "circle" : "checkmark.circle")
                }
            } else {
                Button(action: { onEnterSelectionMode?() }) {
                    Label("Select Characters...", systemImage: "checkmark.circle")
                }
                
                Divider()
                
                Button(action: onEdit) {
                    Label("Customize Memoji...", systemImage: "paintbrush")
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
                
                Divider()
                
                // Reorder Model submenu
                Menu("Reorder Model") {
                    if let onTop = onMoveToTop {
                        Button(action: onTop) {
                            Label("Move to Top", systemImage: "arrow.up.to.line")
                        }
                    }
                    if let onBack = onMoveBackward {
                        Button(action: onBack) {
                            Label("Move Up (Earlier)", systemImage: "arrow.up")
                        }
                    }
                    if let onFwd = onMoveForward {
                        Button(action: onFwd) {
                            Label("Move Down (Later)", systemImage: "arrow.down")
                        }
                    }
                    if let onBottom = onMoveToBottom {
                        Button(action: onBottom) {
                            Label("Move to Bottom", systemImage: "arrow.down.to.line")
                        }
                    }
                    if hasCustomOrder, let onReset = onResetOrder {
                        Divider()
                        Button(action: onReset) {
                            Label("Reset Order to Default", systemImage: "arrow.counterclockwise")
                        }
                    }
                }
                
                Divider()
                
                Button(action: onToggleFavorite) {
                    Label(isFavorite ? "Unfavorite" : "Favorite", systemImage: isFavorite ? "star.slash" : "star")
                }
                
                if let onDel = onDelete {
                    Divider()
                    Button(role: .destructive, action: onDel) {
                        Label("Delete Character", systemImage: "trash")
                    }
                }
            }
        }
        .task(id: item.id) {
            if thumbnail == nil {
                thumbnail = await ThumbnailCache.shared.getThumbnail(for: item, avatarObject: avatarObject)
            }
        }
    }
    
    private func subtitleFor(_ item: AvatarItem) -> String {
        switch item.sourceType {
        case .userMemoji: return "Personal Memoji"
        case .customMemoji: return "Studio Model"
        case .builtinAnimoji: return "Apple Animoji"
        case .randomMemoji: return "Generated Memoji"
        }
    }
}
