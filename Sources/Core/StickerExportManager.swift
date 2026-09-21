import Foundation
import AppKit

public enum ExportFormat: String, CaseIterable, Identifiable {
    case png = "PNG (Transparent)"
    case jpeg = "JPEG"
    
    public var id: String { rawValue }
    public var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        }
    }
}

public enum ExportBackground: String, CaseIterable, Identifiable {
    case transparent = "Transparent"
    case white = "Pure White"
    case dark = "Dark Charcoal"
    case sunset = "Sunset Glow"
    case ocean = "Ocean Breeze"
    case pastelViolet = "Pastel Violet"
    case neonMint = "Neon Mint"
    
    public var id: String { rawValue }
    
    public var colors: [NSColor] {
        switch self {
        case .transparent:
            return []
        case .white:
            return [NSColor.white]
        case .dark:
            return [NSColor(red: 0.12, green: 0.12, blue: 0.15, alpha: 1.0)]
        case .sunset:
            return [
                NSColor(red: 1.0, green: 0.45, blue: 0.45, alpha: 1.0),
                NSColor(red: 0.95, green: 0.25, blue: 0.65, alpha: 1.0)
            ]
        case .ocean:
            return [
                NSColor(red: 0.15, green: 0.70, blue: 0.95, alpha: 1.0),
                NSColor(red: 0.20, green: 0.40, blue: 0.95, alpha: 1.0)
            ]
        case .pastelViolet:
            return [
                NSColor(red: 0.85, green: 0.75, blue: 0.98, alpha: 1.0),
                NSColor(red: 0.65, green: 0.60, blue: 0.95, alpha: 1.0)
            ]
        case .neonMint:
            return [
                NSColor(red: 0.15, green: 0.90, blue: 0.70, alpha: 1.0),
                NSColor(red: 0.10, green: 0.65, blue: 0.80, alpha: 1.0)
            ]
        }
    }
}

@MainActor
public final class StickerExportManager {
    public static let shared = StickerExportManager()
    
    private init() {}
    
    /// Copies an image to the general system clipboard with transparent PNG and TIFF support
    public func copyToClipboard(image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        
        if let tiffData = image.tiffRepresentation {
            pasteboard.setData(tiffData, forType: .tiff)
            if let rep = NSBitmapImageRep(data: tiffData),
               let pngData = rep.representation(using: .png, properties: [:]) {
                pasteboard.setData(pngData, forType: .png)
            }
        }
    }
    
    /// Renders an NSImage with chosen resolution and background styling
    public func renderProcessedImage(
        original: NSImage,
        targetSize: CGFloat,
        background: ExportBackground,
        format: ExportFormat
    ) -> NSImage {
        let finalSize = NSSize(width: targetSize, height: targetSize)
        let newImage = NSImage(size: finalSize)
        
        newImage.lockFocus()
        let rect = NSRect(origin: .zero, size: finalSize)
        
        if !background.colors.isEmpty {
            if background.colors.count == 1 {
                background.colors[0].setFill()
                rect.fill()
            } else {
                let gradient = NSGradient(colors: background.colors)
                gradient?.draw(in: rect, angle: 45.0)
            }
        }
        
        // Center sticker with padding on colored backgrounds
        let padding: CGFloat = background == .transparent ? 0 : targetSize * 0.08
        let drawRect = NSRect(
            x: padding,
            y: padding,
            width: targetSize - (padding * 2),
            height: targetSize - (padding * 2)
        )
        
        original.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        newImage.unlockFocus()
        
        return newImage
    }
    
    /// Composites an avatar image over a radial gradient studio backdrop
    public func renderWithRadialBackdrop(
        avatarImage: NSImage,
        backdropColors: [NSColor],
        targetSize: CGSize? = nil
    ) -> NSImage {
        let size = targetSize ?? avatarImage.size
        let newImage = NSImage(size: size)
        
        newImage.lockFocus()
        let rect = NSRect(origin: .zero, size: size)
        
        if backdropColors.count >= 2 {
            if let gradient = NSGradient(colors: backdropColors) {
                let center = NSPoint(x: rect.midX, y: rect.midY)
                let radius = max(size.width, size.height) * 0.72
                gradient.draw(
                    fromCenter: center,
                    radius: 0,
                    toCenter: center,
                    radius: radius,
                    options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation]
                )
            }
        } else if let single = backdropColors.first {
            single.setFill()
            rect.fill()
        }
        
        avatarImage.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
        newImage.unlockFocus()
        
        return newImage
    }
    
    /// Converts NSImage to file data
    public func imageData(for image: NSImage, format: ExportFormat) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        
        switch format {
        case .png:
            return bitmap.representation(using: .png, properties: [:])
        case .jpeg:
            return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.92])
        }
    }
    
    /// Prompts user with NSSavePanel to save image file — must be called on main thread
    public func saveWithDialog(
        image: NSImage,
        defaultFileName: String,
        targetSize: CGFloat = 512,
        background: ExportBackground = .transparent,
        format: ExportFormat = .png
    ) {
        let processed = renderProcessedImage(
            original: image,
            targetSize: targetSize,
            background: background,
            format: format
        )
        
        guard let data = imageData(for: processed, format: format) else { return }
        
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        if format == .png {
            savePanel.allowedContentTypes = [.png]
        } else {
            savePanel.allowedContentTypes = [.jpeg]
        }
        savePanel.nameFieldStringValue = "\(defaultFileName).\(format.fileExtension)"
        
        savePanel.begin { response in
            if response == .OK, let destinationURL = savePanel.url {
                try? data.write(to: destinationURL)
            }
        }
    }
    
    /// Creates a temporary file URL for drag & drop operations — must be called on main thread
    public func createTemporaryFile(for image: NSImage, filename: String) -> URL? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        
        // Sanitize filename to avoid path separator issues
        let safe = filename.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MemojiDrag", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let fileURL = tempDir.appendingPathComponent("\(safe).png")
        try? png.write(to: fileURL)
        return fileURL
    }
    
    /// Batch exports a collection of stickers to a folder chosen by user — must be called on main thread
    public func batchExport(
        stickers: [(name: String, image: NSImage)],
        targetSize: CGFloat,
        background: ExportBackground,
        format: ExportFormat,
        completion: @escaping @MainActor (Int) -> Void
    ) {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = true
        openPanel.prompt = "Export All Stickers Here"
        
        openPanel.begin { response in
            guard response == .OK, let targetFolder = openPanel.url else {
                Task { @MainActor in completion(0) }
                return
            }
            
            // Capture all needed values as Sendable types before leaving main actor
            let targetFolderCopy = targetFolder
            let fileExtension = format.fileExtension
            
            // Render all images on main actor synchronously, then write on background
            var renderedFiles: [(name: String, data: Data)] = []
            for item in stickers {
                let processed = self.renderProcessedImage(
                    original: item.image,
                    targetSize: targetSize,
                    background: background,
                    format: format
                )
                if let data = self.imageData(for: processed, format: format) {
                    renderedFiles.append((item.name, data))
                }
            }
            
            // Write files off main thread
            let fileExtCopy = fileExtension
            Task.detached(priority: .utility) {
                var count = 0
                for file in renderedFiles {
                    let safe = file.name.replacingOccurrences(of: "/", with: "-")
                    let fileURL = targetFolderCopy.appendingPathComponent("\(safe).\(fileExtCopy)")
                    if (try? file.data.write(to: fileURL)) != nil {
                        count += 1
                    }
                }
                await MainActor.run {
                    completion(count)
                }
            }
        }
    }
}
