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
        VStack(spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Text(sticker.emoji)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Export \(sticker.localizedTitle)")
                            .font(.headline)
                        Text("Choose resolution, background, and format")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary.opacity(0.8))
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
                    .frame(width: 230, height: 230)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                    
                    Text("\(Int(selectedResolution)) × \(Int(selectedResolution)) px • \(selectedFormat.rawValue)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                // Right: Controls
                VStack(alignment: .leading, spacing: 14) {
                    // Resolution
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Resolution")
                                .font(.system(size: 12, weight: .bold))
                            Spacer()
                            Text(resolutionBadgeText(selectedResolution))
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.12))
                                .foregroundColor(.accentColor)
                                .clipShape(Capsule())
                        }
                        
                        Picker("", selection: $selectedResolution) {
                            Text("256px").tag(CGFloat(256))
                            Text("512px").tag(CGFloat(512))
                            Text("1024px").tag(CGFloat(1024))
                            Text("2048px").tag(CGFloat(2048))
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    // Background
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Background")
                                .font(.system(size: 12, weight: .bold))
                            Spacer()
                            Text(selectedBackground.rawValue)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        
                        // Circular visual swatch selector
                        HStack(spacing: 8) {
                            ForEach(ExportBackground.allCases) { bg in
                                let isSelected = selectedBackground == bg
                                Button(action: {
                                    selectedBackground = bg
                                    if bg == .transparent && selectedFormat == .jpeg {
                                        selectedFormat = .png
                                    }
                                }) {
                                    ZStack {
                                        if bg == .transparent {
                                            CheckerboardView()
                                                .frame(width: 26, height: 26)
                                                .clipShape(Circle())
                                        } else if bg.colors.count == 1 {
                                            Circle()
                                                .fill(Color(bg.colors[0]))
                                                .frame(width: 26, height: 26)
                                        } else {
                                            Circle()
                                                .fill(
                                                    LinearGradient(
                                                        colors: bg.colors.map { Color($0) },
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                                .frame(width: 26, height: 26)
                                        }
                                        
                                        if isSelected {
                                            Circle()
                                                .strokeBorder(Color.accentColor, lineWidth: 2.5)
                                                .frame(width: 32, height: 32)
                                        }
                                    }
                                    .frame(width: 32, height: 32)
                                }
                                .buttonStyle(.plain)
                                .help(bg.rawValue)
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
                    HStack(spacing: 8) {
                        Button(action: copyToClipboard) {
                            HStack(spacing: 4) {
                                Image(systemName: showCopiedAlert ? "checkmark" : "doc.on.doc")
                                    .foregroundColor(showCopiedAlert ? .green : .primary)
                                Text(showCopiedAlert ? "Copied" : "Copy")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        
                        Button(action: shareSheet) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .help("Share...")
                        
                        Button(action: saveToFile) {
                            Text("Save Image...")
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .frame(width: 290)
            }
        }
        .padding(22)
        .frame(width: 590, height: 380)
    }
    
    private func resolutionBadgeText(_ res: CGFloat) -> String {
        switch res {
        case 256: return "Emoji / Icon"
        case 512: return "Standard Sticker"
        case 1024: return "HD Avatar"
        case 2048: return "Ultra HD / Print"
        default: return "\(Int(res))px"
        }
    }
    
    private func copyToClipboard() {
        let processed = StickerExportManager.shared.renderProcessedImage(
            original: image,
            targetSize: selectedResolution,
            background: selectedBackground,
            format: selectedFormat
        )
        StickerExportManager.shared.copyToClipboard(image: processed)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showCopiedAlert = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopiedAlert = false
            }
        }
    }
    
    private func shareSheet() {
        let processed = StickerExportManager.shared.renderProcessedImage(
            original: image,
            targetSize: selectedResolution,
            background: selectedBackground,
            format: selectedFormat
        )
        guard let tempURL = StickerExportManager.shared.createTemporaryFile(for: processed, filename: sticker.name) else {
            return
        }
        
        let picker = NSSharingServicePicker(items: [tempURL])
        if let window = NSApplication.shared.keyWindow, let contentView = window.contentView {
            picker.show(relativeTo: NSRect(x: contentView.bounds.midX, y: contentView.bounds.midY, width: 1, height: 1), of: contentView, preferredEdge: .minY)
        }
    }
    
    private func saveToFile() {
        let processed = StickerExportManager.shared.renderProcessedImage(
            original: image,
            targetSize: selectedResolution,
            background: selectedBackground,
            format: selectedFormat
        )
        guard let data = StickerExportManager.shared.imageData(for: processed, format: selectedFormat) else { return }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = selectedFormat == .png ? [.png] : [.jpeg]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.title = "Save \(sticker.localizedTitle)"
        savePanel.nameFieldStringValue = "\(sticker.name).\(selectedFormat.fileExtension)"
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                try? data.write(to: url)
                dismiss()
            }
        }
    }
}

public struct CheckerboardView: View {
    public init() {}
    
    public var body: some View {
        Canvas { context, size in
            let tileSize: CGFloat = 8
            let rows = Int(ceil(size.height / tileSize))
            let cols = Int(ceil(size.width / tileSize))
            
            for row in 0..<rows {
                for col in 0..<cols {
                    let isEven = (row + col) % 2 == 0
                    let rect = CGRect(
                        x: CGFloat(col) * tileSize,
                        y: CGFloat(row) * tileSize,
                        width: tileSize,
                        height: tileSize
                    )
                    let color = isEven ? Color(white: 0.92) : Color(white: 0.78)
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
    }
}
