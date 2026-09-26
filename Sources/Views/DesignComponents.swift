import SwiftUI
import AppKit

public struct AppTheme {
    // Dynamic adaptive backgrounds
    public static var sidebarBackground: Color {
        Color(nsColor: .windowBackgroundColor)
    }
    
    public static var sidebarHeaderBackground: Color {
        Color(nsColor: .controlBackgroundColor).opacity(0.6)
    }
    
    // Card styling
    public static var cardBackground: Color {
        Color(nsColor: .controlBackgroundColor)
    }
    
    public static var cardBorder: Color {
        Color.primary.opacity(0.08)
    }
    
    public static var cardSelectedBorder: Color {
        Color.accentColor
    }
    
    // Button styling
    public static var buttonBackground: Color {
        Color(nsColor: .controlBackgroundColor)
    }
    
    public static var buttonHoverBackground: Color {
        Color(nsColor: .selectedControlColor).opacity(0.15)
    }
    
    public static var stageBackground: Color {
        Color(nsColor: .underPageBackgroundColor)
    }
    
    public static var primaryText: Color {
        Color.primary
    }
    
    public static var secondaryText: Color {
        Color.secondary
    }
    
    public static let goldColor = Color(red: 1.0, green: 0.72, blue: 0.0)
}

/// Circular counter-clockwise arrow matching Apple's standard reset framing icon
public struct ResetFramingIcon: View {
    public var size: CGFloat = 16
    
    public init(size: CGFloat = 16) {
        self.size = size
    }
    
    public var body: some View {
        Image(systemName: "arrow.counterclockwise")
            .font(.system(size: size, weight: .semibold))
            .foregroundColor(.primary)
            .frame(width: size + 6, height: size + 6)
    }
}

/// Video camera with silhouette person cutout matching the design
public struct LiveCameraIcon: View {
    public var size: CGFloat = 17
    public var isActive: Bool = false
    
    public init(size: CGFloat = 17, isActive: Bool = false) {
        self.size = size
        self.isActive = isActive
    }
    
    public var body: some View {
        ZStack {
            Image(systemName: "video.fill")
                .font(.system(size: size))
            
            // True alpha cutout of person silhouette
            Image(systemName: "person.fill")
                .font(.system(size: size * 0.44))
                .offset(x: -size * 0.08)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
        .foregroundColor(isActive ? Color.green : Color.primary)
        .frame(width: size + 6, height: size + 6)
    }
}

/// 2x2 Grid icon matching the sidebar footer
public struct Grid2x2Icon: View {
    public var isSelected: Bool
    
    public init(isSelected: Bool) {
        self.isSelected = isSelected
    }
    
    public var body: some View {
        Image(systemName: "square.grid.2x2")
            .font(.system(size: 16, weight: isSelected ? .bold : .regular))
            .foregroundColor(isSelected ? .primary : .secondary)
    }
}

/// 2 horizontal bars list icon matching the sidebar footer
public struct List2RowIcon: View {
    public var isSelected: Bool
    
    public init(isSelected: Bool) {
        self.isSelected = isSelected
    }
    
    public var body: some View {
        VStack(spacing: 2.5) {
            RoundedRectangle(cornerRadius: 1.5)
                .stroke(isSelected ? Color.primary : Color.secondary, lineWidth: 1.8)
                .frame(width: 17, height: 6.5)
            RoundedRectangle(cornerRadius: 1.5)
                .stroke(isSelected ? Color.primary : Color.secondary, lineWidth: 1.8)
                .frame(width: 17, height: 6.5)
        }
        .frame(width: 20, height: 20)
    }
}
