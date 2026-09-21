import SwiftUI
import AppKit

public struct ExportModalView: View {
    public let sticker: StickerItem
    public let image: NSImage
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedResolution: CGFloat = 512
    @State private var selectedBackground: ExportBackground = .transparent
    @State private var selectedFormat: ExportFormat = .png
    @State private var showCopiedAlert: Bool = false
    
    private let resolutions: [CGFloat] = [256, 512, 1024, 2048]
    
    public init(sticker: StickerItem, image: NSImage) {
        self.sticker = sticker
        self.image = image
    }
    
    public var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(sticker.emoji)
                            .font(.title3)
                        Text("Export \(sticker.localizedTitle)")
                            .font(.headline)
                    }
                    Text("Configure resolution, background, and format")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            HStack(spacing: 24) {
                // Left: Live Preview Container
                VStack(spacing: 8) {
                    ZStack {
                        // Background display
                        if selectedBackground == .transparent {
                            CheckerboardView()
                        } else if selectedBackground.colors.count == 1 {
                            Color(selectedBackground.colors[0])
                        } else if selectedBackground.colors.count > 1 {
                            LinearGradient(
                                colors: selectedBackground.colors.map { Color($0) },
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        }
                        
                        // Sticker
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(selectedBackground == .transparent ? 16 : 28)
                    }
                    .frame(width: 240, height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                    
                    Text("\(Int(selectedResolution)) × \(Int(selectedResolution)) px")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Right: Controls
                VStack(alignment: .leading, spacing: 16) {
                    // Resolution
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Resolution")
                            .font(.system(size: 12, weight: .bold))
                        Picker("", selection: $selectedResolution) {
                            Text("256px (Emoji/Icon)").tag(CGFloat(256))
                            Text("512px (Standard)").tag(CGFloat(512))
                            Text("1024px (HD)").tag(CGFloat(1024))
                            Text("2048px (Ultra HD)").tag(CGFloat(2048))
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    // Background
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Background")
                            .font(.system(size: 12, weight: .bold))
                        Picker("", selection: $selectedBackground) {
                            ForEach(ExportBackground.allCases) { bg in
                                Text(bg.rawValue).tag(bg)
                            }
                        }
                    }
                    
                    // Format
                    VStack(alignment: .leading, spacing: 6) {
                        Text("File Format")
                            .font(.system(size: 12, weight: .bold))
                        Picker("", selection: $selectedFormat) {
                            ForEach(ExportFormat.allCases) { fmt in
                                Text(fmt.rawValue).tag(fmt)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: selectedFormat) { _, newFmt in
                            if newFmt == .jpeg && selectedBackground == .transparent {
                                selectedBackground = .white
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Actions
                    HStack(spacing: 10) {
                        Button(action: copyToClipboard) {
                            HStack(spacing: 4) {
                                Image(systemName: showCopiedAlert ? "checkmark" : "doc.on.doc")
                                Text(showCopiedAlert ? "Copied!" : "Copy")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .controlSize(.large)
                        
                        Button(action: shareSheet) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .controlSize(.large)
                        .help("Share via AirDrop, Messages, etc.")
                        
                        Button(action: saveToFile) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down.doc.fill")
                                Text("Save...")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                }
                .frame(width: 280)
            }
        }
        .padding(24)
        .frame(width: 580, height: 380)
    }
    
    private func copyToClipboard() {
        let processed = StickerExportManager.shared.renderProcessedImage(
            original: image,
            targetSize: selectedResolution,
            background: selectedBackground,
            format: selectedFormat
        )
        StickerExportManager.shared.copyToClipboard(image: processed)
        withAnimation {
            showCopiedAlert = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopiedAlert = false
            }
        }
    }
    
    private func saveToFile() {
        StickerExportManager.shared.saveWithDialog(
            image: image,
            defaultFileName: "memoji_\(sticker.name)",
            targetSize: selectedResolution,
            background: selectedBackground,
            format: selectedFormat
        )
        dismiss()
    }
    
    private func shareSheet() {
        let processed = StickerExportManager.shared.renderProcessedImage(
            original: image,
            targetSize: selectedResolution,
            background: selectedBackground,
            format: selectedFormat
        )
        if let window = NSApp.keyWindow {
            let picker = NSSharingServicePicker(items: [processed])
            picker.show(relativeTo: .zero, of: window.contentView ?? NSView(), preferredEdge: .minY)
        }
    }
}

/// Checkerboard pattern for indicating transparent background
public struct CheckerboardView: View {
    public init() {}
    
    public var body: some View {
        Canvas { context, size in
            let tileSize: CGFloat = 10
            let cols = Int(ceil(size.width / tileSize))
            let rows = Int(ceil(size.height / tileSize))
            
            for row in 0..<rows {
                for col in 0..<cols {
                    let isEven = (row + col) % 2 == 0
                    let color = isEven ? Color.white : Color(nsColor: .lightGray).opacity(0.3)
                    let rect = CGRect(
                        x: CGFloat(col) * tileSize,
                        y: CGFloat(row) * tileSize,
                        width: tileSize,
                        height: tileSize
                    )
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
    }
}
