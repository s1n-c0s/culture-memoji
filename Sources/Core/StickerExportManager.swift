import Foundation
import AppKit
import SwiftUI

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
        
        // Write TIFF representation
        if let tiffData = image.tiffRepresentation {
            pasteboard.setData(tiffData, forType: .tiff)
            
            // Write PNG representation for apps that prefer PNG (Slack, Chrome, Discord, etc.)
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
        
        // Draw background
        if !background.colors.isEmpty {
            if background.colors.count == 1 {
                background.colors[0].setFill()
                rect.fill()
            } else if background.colors.count > 1 {
                let gradient = NSGradient(colors: background.colors)
                gradient?.draw(in: rect, angle: 45.0)
            }
        }
        
        // Draw centered sticker
        // Add 10% padding if on colored background for aesthetic margins
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
    
    /// Prompts user with NSSavePanel to save image file
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
        savePanel.allowedContentTypes = format == .png ? [.png] : [.jpeg]
        savePanel.nameFieldStringValue = "\(defaultFileName).\(format.fileExtension)"
        
        savePanel.begin { response in
            if response == .OK, let destinationURL = savePanel.url {
                try? data.write(to: destinationURL)
            }
        }
    }
    
    /// Creates a temporary file URL for drag & drop operations
    public func createTemporaryFile(for image: NSImage, filename: String) -> URL? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("MemojiDrag", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let fileURL = tempDir.appendingPathComponent("\(filename).png")
        try? png.write(to: fileURL)
        return fileURL
    }
    
    /// Batch exports a collection of stickers to a selected directory
    public func batchExport(
        stickers: [(name: String, image: NSImage)],
        targetSize: CGFloat,
        background: ExportBackground,
        format: ExportFormat,
        completion: @escaping (Int) -> Void
    ) {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = true
        openPanel.prompt = "Export All Stickers Here"
        
        openPanel.begin { response in
            guard response == .OK, let targetFolder = openPanel.url else {
                completion(0)
                return
            }
            
            var count = 0
            for item in stickers {
                let processed = self.renderProcessedImage(
                    original: item.image,
                    targetSize: targetSize,
                    background: background,
                    format: format
                )
                if let data = self.imageData(for: processed, format: format) {
                    let sanitizedName = item.name.replacingOccurrences(of: "/", with: "-")
                    let fileURL = targetFolder.appendingPathComponent("\(sanitizedName).\(format.fileExtension)")
                    if (try? data.write(to: fileURL)) != nil {
                        count += 1
                    }
                }
            }
            completion(count)
        }
    }
}
