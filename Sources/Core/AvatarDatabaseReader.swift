import Foundation
import AppKit
import SQLite3

public final class AvatarDatabaseReader: Sendable {
    public static let shared = AvatarDatabaseReader()
    
    private let dbPath: String
    private let stickersDirectoryPath: String
    private let customAvatarsDirectoryPath: String
    
    public init() {
        let home = NSHomeDirectory()
        self.dbPath = (home as NSString).appendingPathComponent("Library/Application Support/Animoji/CoreDataBackend/avatars.db")
        self.stickersDirectoryPath = (home as NSString).appendingPathComponent("Library/Application Support/Animoji/Stickers")
        self.customAvatarsDirectoryPath = (home as NSString).appendingPathComponent("Library/Application Support/CultureMemoji/CustomAvatars")
        
        // Ensure custom avatars directory exists
        try? FileManager.default.createDirectory(atPath: customAvatarsDirectoryPath, withIntermediateDirectories: true)
    }
    
    public var hasUserMemojis: Bool {
        return FileManager.default.fileExists(atPath: dbPath)
    }
    
    // MARK: - Custom Memojis (Culture Memoji Storage)
    
    /// Reads all locally created custom Memojis
    public func fetchCustomAvatars() -> [AvatarItem] {
        guard FileManager.default.fileExists(atPath: customAvatarsDirectoryPath) else {
            return []
        }
        
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(atPath: customAvatarsDirectoryPath) else {
            return []
        }
        
        let hiddenIds = hiddenAvatarIds()
        var items: [AvatarItem] = []
        for file in files where file.hasSuffix(".json") {
            let path = (customAvatarsDirectoryPath as NSString).appendingPathComponent(file)
            guard let fileData = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let json = try? JSONSerialization.jsonObject(with: fileData) as? [String: Any],
                  let id = json["id"] as? String,
                  !hiddenIds.contains(id),
                  let name = json["name"] as? String else {
                continue
            }
            
            var avatarData: Data?
            if let base64Str = json["avatarDataBase64"] as? String {
                avatarData = Data(base64Encoded: base64Str)
            } else if let rawString = json["avatarData"] as? String {
                avatarData = Data(rawString.utf8)
            }
            
            let item = AvatarItem(
                id: id,
                displayName: name,
                sourceType: .customMemoji(id: id),
                rawData: avatarData,
                cachedStickerCount: 0
            )
            items.append(item)
        }
        
        items.sort { $0.displayName < $1.displayName }
        return items
    }
    
    /// Saves a custom Memoji to persistent disk storage
    @discardableResult
    public func saveCustomMemoji(name: String, data: Data, existingId: String? = nil) -> AvatarItem {
        try? FileManager.default.createDirectory(atPath: customAvatarsDirectoryPath, withIntermediateDirectories: true)
        
        let id: String
        if let existing = existingId, !existing.isEmpty {
            id = existing
        } else {
            id = "custom_\(UUID().uuidString)"
        }
        
        let filePath = (customAvatarsDirectoryPath as NSString).appendingPathComponent("\(id).json")
        let base64 = data.base64EncodedString()
        let rawString = String(data: data, encoding: .utf8) ?? ""
        
        let payload: [String: Any] = [
            "id": id,
            "name": name,
            "updatedAt": Date().timeIntervalSince1970,
            "avatarDataBase64": base64,
            "avatarData": rawString
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted) {
            try? jsonData.write(to: URL(fileURLWithPath: filePath))
        }
        
        return AvatarItem(
            id: id,
            displayName: name,
            sourceType: .customMemoji(id: id),
            rawData: data,
            cachedStickerCount: 0
        )
    }
    
    /// Deletes a custom Memoji from persistent disk storage
    public func deleteCustomMemoji(id: String) -> Bool {
        let filePath = (customAvatarsDirectoryPath as NSString).appendingPathComponent("\(id).json")
        guard FileManager.default.fileExists(atPath: filePath) else { return false }
        do {
            try FileManager.default.removeItem(atPath: filePath)
            return true
        } catch {
            return false
        }
    }
    
    /// Renames a custom avatar in persistent storage
    public func renameCustomMemoji(id: String, newName: String) -> Bool {
        let filePath = (customAvatarsDirectoryPath as NSString).appendingPathComponent("\(id).json")
        guard FileManager.default.fileExists(atPath: filePath),
              let fileData = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
              var json = (try? JSONSerialization.jsonObject(with: fileData)) as? [String: Any] else {
            return false
        }
        json["name"] = newName
        json["updatedAt"] = Date().timeIntervalSince1970
        if let jsonData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted) {
            try? jsonData.write(to: URL(fileURLWithPath: filePath))
            return true
        }
        return false
    }
    
    /// Updates an existing system Memoji in Apple's CoreData avatars.db

    public func updateUserMemojiInSystemDatabase(uuid: String, data: Data) -> Bool {
        guard FileManager.default.fileExists(atPath: dbPath) else { return false }
        
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_close(db) }
        
        let query = "UPDATE ZAVATAR SET ZAVATARDATA = ? WHERE hex(ZIDENTIFIER) = ? OR Z_PK = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(stmt) }
        
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_blob(stmt, 1, (data as NSData).bytes, Int32(data.count), SQLITE_TRANSIENT)
        
        let cleanHex = uuid.replacingOccurrences(of: "-", with: "").uppercased()
        sqlite3_bind_text(stmt, 2, (cleanHex as NSString).utf8String, -1, SQLITE_TRANSIENT)
        
        var pk = 0
        if uuid.hasPrefix("Avatar-"), let parsedPk = Int(uuid.replacingOccurrences(of: "Avatar-", with: "")) {
            pk = parsedPk
        }
        sqlite3_bind_int(stmt, 3, Int32(pk))
        
        let stepResult = sqlite3_step(stmt)
        return stepResult == SQLITE_DONE && sqlite3_changes(db) > 0
    }
    
    /// Deletes a system Memoji from Apple's CoreData avatars.db and clears its cached stickers
    public func deleteUserMemoji(uuid: String) -> Bool {
        // Also remove any cached stickers on disk
        if FileManager.default.fileExists(atPath: stickersDirectoryPath),
           let files = try? FileManager.default.contentsOfDirectory(atPath: stickersDirectoryPath) {
            let prefix = uuid.uppercased()
            for file in files where file.uppercased().hasPrefix(prefix) {
                let filePath = (stickersDirectoryPath as NSString).appendingPathComponent(file)
                try? FileManager.default.removeItem(atPath: filePath)
            }
        }
        
        hideAvatar(id: uuid)
        
        guard FileManager.default.fileExists(atPath: dbPath) else { return true }
        
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_close(db) }
        
        let query = "DELETE FROM ZAVATAR WHERE hex(ZIDENTIFIER) = ? OR Z_PK = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(stmt) }
        
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let cleanHex = uuid.replacingOccurrences(of: "-", with: "").uppercased()
        sqlite3_bind_text(stmt, 1, (cleanHex as NSString).utf8String, -1, SQLITE_TRANSIENT)
        
        var pk = 0
        if uuid.hasPrefix("Avatar-"), let parsedPk = Int(uuid.replacingOccurrences(of: "Avatar-", with: "")) {
            pk = parsedPk
        }
        sqlite3_bind_int(stmt, 2, Int32(pk))
        
        let stepResult = sqlite3_step(stmt)
        return stepResult == SQLITE_DONE
    }
    
    // MARK: - Hidden / Deleted Avatars Persistence
    
    private let hiddenAvatarsKey = "culture_memoji_hidden_avatar_ids"
    
    public func hiddenAvatarIds() -> Set<String> {
        let arr = UserDefaults.standard.stringArray(forKey: hiddenAvatarsKey) ?? []
        return Set(arr)
    }
    
    public func hideAvatar(id: String) {
        var set = hiddenAvatarIds()
        set.insert(id)
        UserDefaults.standard.set(Array(set), forKey: hiddenAvatarsKey)
    }
    
    public func unhideAvatar(id: String) {
        var set = hiddenAvatarIds()
        set.remove(id)
        UserDefaults.standard.set(Array(set), forKey: hiddenAvatarsKey)
    }
    
    /// Reads all user-created Memojis stored in Apple's Animoji SQLite CoreData database
    public func fetchUserMemojis() -> [AvatarItem] {
        guard FileManager.default.fileExists(atPath: dbPath) else {
            return []
        }
        
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_close(db) }
        
        let hiddenIds = hiddenAvatarIds()
        var items: [AvatarItem] = []
        let query = "SELECT Z_PK, hex(ZIDENTIFIER), ZAVATARDATA FROM ZAVATAR ORDER BY Z_PK ASC;"
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            var index = 1
            while sqlite3_step(stmt) == SQLITE_ROW {
                let pk = sqlite3_column_int(stmt, 0)
                var uuidString = "Avatar-\(pk)"
                if let cStr = sqlite3_column_text(stmt, 1) {
                    let hexStr = String(cString: cStr)
                    uuidString = formatUUID(hexStr)
                }
                
                if hiddenIds.contains(uuidString) || hiddenIds.contains("Avatar-\(pk)") {
                    continue
                }
                
                var data: Data?
                if let blob = sqlite3_column_blob(stmt, 2) {
                    let length = sqlite3_column_bytes(stmt, 2)
                    data = Data(bytes: blob, count: Int(length))
                }
                
                let stickers = findCachedStickers(forUUID: uuidString)
                
                let item = AvatarItem(
                    id: uuidString,
                    displayName: "My Memoji \(index)",
                    sourceType: .userMemoji(uuid: uuidString),
                    rawData: data,
                    cachedStickerCount: stickers.count
                )
                items.append(item)
                index += 1
            }
            sqlite3_finalize(stmt)
        }
        
        return items
    }
    
    /// Finds all cached transparent PNG stickers on disk for a given avatar UUID
    public func findCachedStickers(forUUID uuid: String) -> [StickerItem] {
        guard FileManager.default.fileExists(atPath: stickersDirectoryPath) else { return [] }
        
        var results: [StickerItem] = []
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(atPath: stickersDirectoryPath) else { return [] }
        
        let prefix = uuid.uppercased()
        for file in files where file.hasSuffix(".png") && file.uppercased().hasPrefix(prefix) {
            let fileURL = URL(fileURLWithPath: stickersDirectoryPath).appendingPathComponent(file)
            
            // Format: UUID_AK<ver>_<hash>_<stickerName>.png
            let nameWithoutExtension = (file as NSString).deletingPathExtension
            let parts = nameWithoutExtension.components(separatedBy: "_")
            
            let stickerName: String
            if parts.count >= 4 {
                stickerName = parts[3...].joined(separator: "_")
            } else {
                stickerName = nameWithoutExtension
            }
            
            let (title, category, emoji) = metadata(forStickerName: stickerName)
            
            let sticker = StickerItem(
                id: "\(uuid)_\(stickerName)",
                name: stickerName,
                localizedTitle: title,
                category: category,
                emoji: emoji,
                localFileURL: fileURL
            )
            results.append(sticker)
        }
        
        // Sort by friendly localized title
        results.sort { $0.localizedTitle < $1.localizedTitle }
        return results
    }
    
    /// Finds all cached transparent PNG stickers on disk for an Apple built-in Animoji name
    public func findCachedStickers(forAnimojiNamed name: String) -> [StickerItem] {
        guard FileManager.default.fileExists(atPath: stickersDirectoryPath) else { return [] }
        
        var results: [StickerItem] = []
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(atPath: stickersDirectoryPath) else { return [] }
        
        let prefix = "\(name.lowercased())_"
        for file in files where file.hasSuffix(".png") && file.lowercased().hasPrefix(prefix) {
            let fileURL = URL(fileURLWithPath: stickersDirectoryPath).appendingPathComponent(file)
            
            // Format: animojiName_AK<ver>_<stickerName>.png
            let nameWithoutExtension = (file as NSString).deletingPathExtension
            let parts = nameWithoutExtension.components(separatedBy: "_")
            
            let stickerName: String
            if parts.count >= 3 {
                stickerName = parts[2...].joined(separator: "_")
            } else {
                stickerName = nameWithoutExtension
            }
            
            let (title, category, emoji) = metadata(forStickerName: stickerName)
            
            let sticker = StickerItem(
                id: "animoji_\(name)_\(stickerName)",
                name: stickerName,
                localizedTitle: title,
                category: category,
                emoji: emoji,
                localFileURL: fileURL
            )
            results.append(sticker)
        }
        
        results.sort { $0.localizedTitle < $1.localizedTitle }
        return results
    }
    
    /// Directory for CultureMemoji generated stickers persistent cache
    public var appStickerCacheDirectory: URL {
        let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = cachesURL.appendingPathComponent("CultureMemoji/Stickers")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    /// Finds all previously generated stickers saved in the app's persistent disk cache
    public func findAppCachedStickers(forAvatarId avatarId: String) -> [StickerItem] {
        let dir = appStickerCacheDirectory.appendingPathComponent(avatarId)
        guard FileManager.default.fileExists(atPath: dir.path) else { return [] }
        
        var results: [StickerItem] = []
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(atPath: dir.path) else { return [] }
        
        for file in files where file.hasSuffix(".png") {
            let fileURL = dir.appendingPathComponent(file)
            let stickerName = (file as NSString).deletingPathExtension
            let (title, category, emoji) = metadata(forStickerName: stickerName)
            
            let sticker = StickerItem(
                id: "\(avatarId)_\(stickerName)",
                name: stickerName,
                localizedTitle: title,
                category: category,
                emoji: emoji,
                localFileURL: fileURL
            )
            results.append(sticker)
        }
        
        results.sort { $0.localizedTitle < $1.localizedTitle }
        return results
    }
    
    /// Converts raw 32-hex characters to 8-4-4-4-12 UUID standard string
    private func formatUUID(_ raw: String) -> String {
        guard raw.count == 32 else { return raw }
        let p1 = raw.prefix(8)
        let p2 = raw.dropFirst(8).prefix(4)
        let p3 = raw.dropFirst(12).prefix(4)
        let p4 = raw.dropFirst(16).prefix(4)
        let p5 = raw.dropFirst(20)
        return "\(p1)-\(p2)-\(p3)-\(p4)-\(p5)"
    }
    
    /// Rich metadata lookup for sticker names
    public func metadata(forStickerName name: String) -> (title: String, category: StickerCategory, emoji: String) {
        switch name {
        case "beKind":
            return ("Be Kind / Heart Hands", .gestures, "🫶")
        case "callMe":
            return ("Call Me Hand", .gestures, "🤙")
        case "chefs_kiss":
            return ("Chef's Kiss", .gestures, "🤌")
        case "crossed_fingers":
            return ("Fingers Crossed", .gestures, "🤞")
        case "finger_heart":
            return ("Finger Heart", .gestures, "🫰")
        case "fist_bump":
            return ("Fist Bump", .gestures, "👊")
        case "folded_hands":
            return ("Folded Hands / Thank You", .gestures, "🙏")
        case "hands_on_hips":
            return ("Hands on Hips", .gestures, "💁")
        case "happy_person_raising_one_hand":
            return ("Raising Hand", .gestures, "🙋")
        case "person_face_palm":
            return ("Facepalm", .gestures, "🤦")
        case "person_gesturing_no":
            return ("Gesturing No", .gestures, "🙅")
        case "person_shrugging":
            return ("Shrug", .gestures, "🤷")
        case "person_tipping_hand":
            return ("Tipping Hand / Sassy", .gestures, "💁")
        case "person_waving":
            return ("Waving Hand / Hello", .gestures, "👋")
        case "talk_to_the_hand":
            return ("Talk to the Hand", .gestures, "✋")
        case "thumbs_down":
            return ("Thumbs Down", .gestures, "👎")
        case "thumbs_up":
            return ("Thumbs Up", .gestures, "👍")
        case "victory_hand":
            return ("Peace / Victory", .gestures, "✌️")
            
        case "annoyed":
            return ("Annoyed", .expressions, "😒")
        case "big_happy", "happy":
            return ("Big Happy Smile", .expressions, "😁")
        case "crying_face":
            return ("Crying / Tears", .expressions, "😭")
        case "dizzy_birds":
            return ("Dizzy / Seeing Stars", .expressions, "💫")
        case "exploding_head":
            return ("Mind Blown", .expressions, "🤯")
        case "face_blowing_a_kiss":
            return ("Blowing a Kiss", .reactions, "😘")
        case "face_screaming_in_fear":
            return ("Screaming / Shocked", .reactions, "😱")
        case "face_with_hand_over_mouth":
            return ("Gasp / Oops", .expressions, "🫢")
        case "face_with_party_horn":
            return ("Party Time / Celebration", .activities, "🥳")
        case "face_with_rolling_eyes":
            return ("Eye Roll", .expressions, "🙄")
        case "face_with_starry_eyes":
            return ("Star Struck", .reactions, "🤩")
        case "face_with_steam_from_nose":
            return ("Steaming / Triumphant", .expressions, "😤")
        case "face_with_symbols_over_mouth":
            return ("Swearing / Censored", .expressions, "🤬")
        case "face_with_tears_of_joy":
            return ("Tears of Joy / LOL", .expressions, "😂")
        case "front_pucker":
            return ("Pucker Lips", .expressions, "😗")
        case "grace_face":
            return ("Grace / Radiant", .expressions, "✨")
        case "grinning_face_with_sweat":
            return ("Nervous Smile / Sweat", .expressions, "😅")
        case "grizzled":
            return ("Grizzled / Serious", .expressions, "🗿")
        case "halo":
            return ("Angel / Halo", .reactions, "😇")
        case "head_in_clouds":
            return ("Head in the Clouds", .activities, "😶‍🌫️")
        case "head_tilt":
            return ("Head Tilt / Curious", .expressions, "🤔")
        case "hugging_face":
            return ("Hugging / Warm", .reactions, "🤗")
        case "hushed_face":
            return ("Hushed / Surprised", .expressions, "😯")
        case "one_raised_eyebrow":
            return ("Skeptical / Eyebrow Raise", .expressions, "🤨")
        case "peekaboo":
            return ("Peekaboo", .reactions, "🙈")
        case "person_gossiping":
            return ("Whispering / Secret", .activities, "🤫")
        case "person_meditating":
            return ("Meditating / Zen", .activities, "🧘")
        case "person_nervous":
            return ("Nervous / Anxious", .expressions, "😬")
        case "person_with_lightbulb":
            return ("Idea / Eureka", .activities, "💡")
        case "person_with_tissue":
            return ("Sick / Tissue", .activities, "🤧")
        case "pouting_face":
            return ("Angry / Pouting", .expressions, "😡")
        case "shushing_face":
            return ("Shh / Quiet", .gestures, "🤫")
        case "sleeping_face":
            return ("Sleeping / Zzz", .activities, "😴")
        case "slightly_frowning_face":
            return ("Slight Frown", .expressions, "🙁")
        case "smiling_face_with_heart-shaped_eyes", "face_with_heart-shaped_eyes":
            return ("Heart Eyes / In Love", .reactions, "😍")
        case "smiling_face_with_open_mouth_and_smiling_eyes":
            return ("Joyful Smile", .expressions, "😃")
        case "smiling_face_with_smiling_eyes_and_three_hearts":
            return ("In Love / Hearts", .reactions, "🥰")
        case "smirk":
            return ("Smirk", .expressions, "😏")
        case "technologist":
            return ("Mac Developer / Tech", .activities, "💻")
        case "thinking_face":
            return ("Thinking / Hmm", .expressions, "🤔")
        case "winking_face":
            return ("Winking", .expressions, "😉")
        case "winking_face_with_stuck_out_tongue":
            return ("Wink & Tongue", .expressions, "😜")
        case "yawn":
            return ("Yawn / Tired", .activities, "🥱")
        case "yearbook":
            return ("Yearbook Portrait", .activities, "📸")
        default:
            let friendly = name
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
            return (friendly, .expressions, "🙂")
        }
    }
}
