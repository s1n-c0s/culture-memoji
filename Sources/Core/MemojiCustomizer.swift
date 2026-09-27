import Foundation
import AppKit
import SwiftUI

/// Categories available for Memoji customization.
/// Mapped directly to Apple's internal AVTPreset and AVTColorPreset category integers.
public enum CustomizerCategory: Int, CaseIterable, Identifiable, Sendable {
    case skin = 0
    case hair = 1
    case facialHair = 2
    case headwear = 4
    case eyewear = 5
    case eyebrows = 6
    case eyes = 7
    case nose = 9
    case mouth = 10
    case ears = 11
    case audio = 25
    case outfit = 34
    
    public var id: Int { rawValue }
    
    public var title: String {
        switch self {
        case .skin: return "Skin"
        case .hair: return "Hair"
        case .facialHair: return "Beard"
        case .eyebrows: return "Brows"
        case .eyes: return "Eyes"
        case .nose: return "Nose"
        case .mouth: return "Lips"
        case .ears: return "Ears"
        case .eyewear: return "Glasses"
        case .headwear: return "Headwear"
        case .audio: return "Audio"
        case .outfit: return "Outfit"
        }
    }
    
    public var iconName: String {
        switch self {
        case .skin: return "face.smiling"
        case .hair: return "comb"
        case .facialHair: return "mustache"
        case .eyebrows: return "waveform.path"
        case .eyes: return "eye"
        case .nose: return "nose"
        case .mouth: return "mouth"
        case .ears: return "ear"
        case .eyewear: return "eyeglasses"
        case .headwear: return "hat.widebrim"
        case .audio: return "airpodspro"
        case .outfit: return "tshirt"
        }
    }
    
    public var hasColors: Bool {
        switch self {
        case .skin, .hair, .facialHair, .eyewear, .headwear, .eyes, .mouth, .outfit:
            return true
        case .eyebrows, .nose, .ears, .audio:
            return false
        }
    }
}

/// Represents a single selectable visual preset for a category (e.g. specific haircut, glasses shape)
public struct PresetOption: Identifiable, Hashable {
    public let id: String
    public let localizedName: String
    public let category: CustomizerCategory
    public let rawPreset: AnyObject
    
    public init(id: String, localizedName: String, category: CustomizerCategory, rawPreset: AnyObject) {
        self.id = id
        self.localizedName = localizedName
        self.category = category
        self.rawPreset = rawPreset
    }
    
    public static func == (lhs: PresetOption, rhs: PresetOption) -> Bool {
        lhs.id == rhs.id && lhs.category == rhs.category
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(category)
    }
}

/// Represents a single selectable color preset (e.g. skin tone, hair color, glasses frame color)
public struct ColorOption: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let localizedName: String
    public let color: Color
    public let nsColor: NSColor
    public let category: CustomizerCategory
    public let rawColor: AnyObject
    
    public init(
        id: String,
        name: String,
        localizedName: String,
        color: Color,
        nsColor: NSColor,
        category: CustomizerCategory,
        rawColor: AnyObject
    ) {
        self.id = id
        self.name = name
        self.localizedName = localizedName
        self.color = color
        self.nsColor = nsColor
        self.category = category
        self.rawColor = rawColor
    }
    
    public static func == (lhs: ColorOption, rhs: ColorOption) -> Bool {
        lhs.id == rhs.id && lhs.category == rhs.category
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(category)
    }
}

/// High-level engine for inspecting and modifying Memoji features, styles, and colors in real time.
@MainActor
public final class MemojiCustomizer {
    public static let shared = MemojiCustomizer()
    
    private var avtPresetClass: AnyClass?
    private var avtColorPresetClass: AnyClass?
    private var avtMemojiClass: AnyClass?
    
    // In-memory option caches to avoid querying the runtime on every render pass
    private var presetCache: [CustomizerCategory: [PresetOption]] = [:]
    private var colorCache: [CustomizerCategory: [ColorOption]] = [:]
    
    // Pre-warmed neutral avatar template for instantaneous 0ms creation
    private var prewarmedNeutralAvatar: AnyObject?
    private var isPrewarming: Bool = false
    
    private init() {
        AvatarKitBridge.shared.loadFrameworksIfNeeded()
        self.avtPresetClass = NSClassFromString("AVTPreset")
        self.avtColorPresetClass = NSClassFromString("AVTColorPreset")
        self.avtMemojiClass = NSClassFromString("AVTMemoji")
    }
    
    // MARK: - Pre-warming
    
    /// Pre-warms the customizer engine, caches a base neutral Memoji in memory,
    /// and pre-populates preset and color caches in the background so opening
    /// the creation editor is completely instantaneous (0ms delay).
    public func prewarm() {
        guard !isPrewarming else { return }
        isPrewarming = true
        
        // 1. Pre-generate and cache a base neutral Memoji in memory
        if prewarmedNeutralAvatar == nil {
            prewarmedNeutralAvatar = AvatarKitBridge.shared.loadNeutralMemoji()
        }
        
        // 2. Pre-cache the default editor category (.hair) and primary (.skin)
        _ = availablePresets(for: .hair)
        _ = availableColors(for: .hair)
        _ = availablePresets(for: .skin)
        _ = availableColors(for: .skin)
        
        // 3. Cooperatively pre-cache remaining categories across runloop turns
        Task { @MainActor in
            for category in CustomizerCategory.allCases {
                if category == .hair || category == .skin { continue }
                await Task.yield()
                _ = self.availablePresets(for: category)
                if category.hasColors {
                    _ = self.availableColors(for: category)
                }
            }
            self.isPrewarming = false
        }
    }
    
    // MARK: - Available Presets & Colors
    
    /// Loads all available style presets for the given category (e.g. all hairstyles)
    public func availablePresets(for category: CustomizerCategory) -> [PresetOption] {
        if let cached = presetCache[category] {
            return cached
        }
        
        guard let presetCls = avtPresetClass else { return [] }
        let sel = NSSelectorFromString("availablePresetsForCategory:")
        guard let method = class_getClassMethod(presetCls, sel) else { return [] }
        
        typealias PresetsFunc = @convention(c) (AnyObject, Selector, Int) -> NSArray?
        let callable = unsafeBitCast(method_getImplementation(method), to: PresetsFunc.self)
        
        guard let rawList = callable(presetCls as AnyObject, sel, category.rawValue) as? [NSObject] else {
            return []
        }
        
        var options: [PresetOption] = []
        for obj in rawList {
            let id = obj.value(forKey: "identifier") as? String ?? ""
            guard !id.isEmpty else { continue }
            
            var locName = obj.value(forKey: "localizedName") as? String
            if locName == nil || locName?.isEmpty == true {
                locName = obj.value(forKey: "displayableName") as? String
            }
            let title = cleanLocalizedTitle(locName ?? id, id: id)
            
            options.append(PresetOption(
                id: id,
                localizedName: title,
                category: category,
                rawPreset: obj
            ))
        }
        
        // Ensure "None" is positioned first for optional accessories/facial features
        options.sort { p1, p2 in
            let isNone1 = p1.id.lowercased() == "none"
            let isNone2 = p2.id.lowercased() == "none"
            if isNone1 && !isNone2 { return true }
            if !isNone1 && isNone2 { return false }
            return false // Preserve natural catalog ordering
        }
        
        presetCache[category] = options
        return options
    }
    
    /// Loads all available color presets for the given category (e.g. hair colors, skin tones)
    public func availableColors(for category: CustomizerCategory) -> [ColorOption] {
        if let cached = colorCache[category] {
            return cached
        }
        
        guard let colorCls = avtColorPresetClass else { return [] }
        let sel = NSSelectorFromString("colorPresetsForCategory:")
        guard let method = class_getClassMethod(colorCls, sel) else { return [] }
        
        typealias ColorsFunc = @convention(c) (AnyObject, Selector, Int) -> NSArray?
        let callable = unsafeBitCast(method_getImplementation(method), to: ColorsFunc.self)
        
        guard let rawList = callable(colorCls as AnyObject, sel, category.rawValue) as? [NSObject] else {
            return []
        }
        
        var options: [ColorOption] = []
        for obj in rawList {
            let name = obj.value(forKey: "name") as? String ?? ""
            guard !name.isEmpty else { continue }
            
            let locName = obj.value(forKey: "localizedName") as? String ?? name
            
            // Extract preview NSColor
            let prevSel = NSSelectorFromString("previewColor")
            var displayColor = Color.primary
            var nsColor = NSColor.textColor
            
            if obj.responds(to: prevSel),
               let rawNsColor = obj.perform(prevSel)?.takeUnretainedValue() as? NSColor {
                nsColor = rawNsColor
                displayColor = Color(nsColor: rawNsColor)
            }
            
            options.append(ColorOption(
                id: "\(category.rawValue)_\(name)",
                name: name,
                localizedName: locName,
                color: displayColor,
                nsColor: nsColor,
                category: category,
                rawColor: obj
            ))
        }
        
        colorCache[category] = options
        return options
    }
    
    // MARK: - Applying Changes
    
    /// Applies a preset option to an AVTMemoji instance
    public func apply(preset: PresetOption, to memoji: AnyObject) {
        let sel = NSSelectorFromString("setPreset:forCategory:")
        guard let method = class_getInstanceMethod(type(of: memoji), sel) else { return }
        
        typealias SetPresetFunc = @convention(c) (AnyObject, Selector, AnyObject, Int) -> Void
        let callable = unsafeBitCast(method_getImplementation(method), to: SetPresetFunc.self)
        callable(memoji, sel, preset.rawPreset, preset.category.rawValue)
    }
    
    /// Applies a color option to an AVTMemoji instance
    public func apply(color: ColorOption, to memoji: AnyObject) {
        let sel = NSSelectorFromString("setColorPreset:forCategory:")
        guard let method = class_getInstanceMethod(type(of: memoji), sel) else { return }
        
        typealias SetColorFunc = @convention(c) (AnyObject, Selector, AnyObject, Int) -> Void
        let callable = unsafeBitCast(method_getImplementation(method), to: SetColorFunc.self)
        callable(memoji, sel, color.rawColor, color.category.rawValue)
    }
    
    /// Returns the currently active preset identifier for a category in the given Memoji
    public func currentPresetIdentifier(for category: CustomizerCategory, in memoji: AnyObject) -> String? {
        let sel = NSSelectorFromString("presetForCategory:")
        guard let method = class_getInstanceMethod(type(of: memoji), sel) else { return nil }
        
        typealias GetPresetFunc = @convention(c) (AnyObject, Selector, Int) -> AnyObject?
        let callable = unsafeBitCast(method_getImplementation(method), to: GetPresetFunc.self)
        guard let preset = callable(memoji, sel, category.rawValue) as? NSObject else { return nil }
        return preset.value(forKey: "identifier") as? String
    }
    
    /// Returns the currently active color name for a category in the given Memoji
    public func currentColorName(for category: CustomizerCategory, in memoji: AnyObject) -> String? {
        let sel = NSSelectorFromString("colorPresetForCategory:")
        guard let method = class_getInstanceMethod(type(of: memoji), sel) else { return nil }
        
        typealias GetColorFunc = @convention(c) (AnyObject, Selector, Int) -> AnyObject?
        let callable = unsafeBitCast(method_getImplementation(method), to: GetColorFunc.self)
        guard let color = callable(memoji, sel, category.rawValue) as? NSObject else { return nil }
        return color.value(forKey: "name") as? String
    }
    
    // MARK: - Creation & Randomization
    
    /// Creates a fresh neutral Memoji ready for customization.
    /// Returns instantly (0ms) using the pre-warmed in-memory template and refreshes the cache in the background.
    public func createNeutralMemoji() -> AnyObject? {
        if let cached = prewarmedNeutralAvatar {
            let clone = AvatarKitBridge.shared.cloneAvatar(cached) ?? cached
            // Re-stock pre-warmed template in background so subsequent creations remain instant
            Task { @MainActor in
                self.prewarmedNeutralAvatar = AvatarKitBridge.shared.loadNeutralMemoji()
            }
            return clone
        }
        
        let fresh = AvatarKitBridge.shared.loadNeutralMemoji()
        Task { @MainActor in
            self.prewarmedNeutralAvatar = AvatarKitBridge.shared.loadNeutralMemoji()
        }
        return fresh
    }
    
    /// Creates a fully randomized Memoji ready for customization
    public func createRandomMemoji() -> AnyObject? {
        return AvatarKitBridge.shared.createRandomMemoji()
    }
    
    /// In-place randomizes an existing Memoji
    public func randomize(memoji: AnyObject) {
        let sel = NSSelectorFromString("randomize")
        if (memoji as AnyObject).responds(to: sel) {
            _ = (memoji as AnyObject).perform(sel)
        }
    }
    
    // MARK: - Helpers
    
    private func cleanLocalizedTitle(_ raw: String, id: String) -> String {
        if raw == "none" { return "None" }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
