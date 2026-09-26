import SwiftUI
import AppKit

public struct AppTheme {
    public static let sidebarBackground = Color(red: 217/255, green: 217/255, blue: 217/255)
    public static let cardBackground = Color(red: 161/255, green: 161/255, blue: 161/255)
    public static let cardSelectedBorder = Color.black
    public static let buttonBackground = Color(red: 217/255, green: 217/255, blue: 217/255)
    public static let buttonHoverBackground = Color(red: 200/255, green: 200/255, blue: 200/255)
    public static let stageBackground = Color.white
    public static let primaryText = Color.black
    public static let secondaryText = Color.black.opacity(0.65)
}

/// Circular counter-clockwise arrow with center dot matching the design
public struct ResetFramingIcon: View {
    public var size: CGFloat = 26
    
    public init(size: CGFloat = 26) {
        self.size = size
    }
    
    public var body: some View {
        ZStack {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: size, weight: .bold))
                .foregroundColor(.black)
            
            Circle()
                .fill(Color.black)
                .frame(width: size * 0.22, height: size * 0.22)
        }
        .frame(width: size + 6, height: size + 6)
    }
}

/// Video camera with silhouette person cutout matching the design
public struct LiveCameraIcon: View {
    public var size: CGFloat = 28
    public var isActive: Bool = false
    
    public init(size: CGFloat = 28, isActive: Bool = false) {
        self.size = size
        self.isActive = isActive
    }
    
    public var body: some View {
        ZStack {
            // Camera body
            Image(systemName: "video.fill")
                .font(.system(size: size))
                .foregroundColor(isActive ? Color.accentColor : Color.black)
            
            // Person bust cutout
            VStack(spacing: size * 0.04) {
                Circle()
                    .fill(Color.white)
                    .frame(width: size * 0.22, height: size * 0.22)
                
                // Shoulders
                Path { path in
                    path.addArc(
                        center: CGPoint(x: size * 0.22, y: size * 0.22),
                        radius: size * 0.22,
                        startAngle: .degrees(180),
                        endAngle: .degrees(0),
                        clockwise: false
                    )
                    path.closeSubpath()
                }
                .fill(Color.white)
                .frame(width: size * 0.44, height: size * 0.22)
            }
            .offset(x: -size * 0.13)
        }
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
            .font(.system(size: 20, weight: isSelected ? .bold : .regular))
            .foregroundColor(isSelected ? .black : Color.black.opacity(0.4))
    }
}

/// 2 horizontal bars list icon matching the sidebar footer
public struct List2RowIcon: View {
    public var isSelected: Bool
    
    public init(isSelected: Bool) {
        self.isSelected = isSelected
    }
    
    public var body: some View {
        VStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 2)
                .stroke(isSelected ? Color.black : Color.black.opacity(0.4), lineWidth: 2)
                .frame(width: 20, height: 8)
            RoundedRectangle(cornerRadius: 2)
                .stroke(isSelected ? Color.black : Color.black.opacity(0.4), lineWidth: 2)
                .frame(width: 20, height: 8)
        }
        .frame(width: 24, height: 24)
    }
}
