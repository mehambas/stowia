import Foundation
import CryptoKit
import UniformTypeIdentifiers

public enum ClipKind: String, Codable, CaseIterable {
    case text, link, image, file
    public var title: String {
        switch self {
        case .text: return String(localized: "Text"); case .link: return String(localized: "Link")
        case .image: return String(localized: "Image"); case .file: return String(localized: "File")
        }
    }
    public var symbol: String {
        switch self { case .text: return "text.alignleft"; case .link: return "link"; case .image: return "photo"; case .file: return "doc" }
    }
}

public struct Clip: Codable, Identifiable, Equatable {
    public var id: UUID
    public var fingerprint: String
    public var kind: ClipKind
    public var text: String
    public var name: String
    public var source: String
    public var sourceBundle: String
    public var createdAt: Date
    public var copiedAt: Date
    public var favorite: Bool
    public var byteCount: Int

    public init(id: UUID = UUID(), fingerprint: String, kind: ClipKind, text: String,
                source: String = "", sourceBundle: String = "", date: Date = Date(), byteCount: Int) {
        self.id = id; self.fingerprint = fingerprint; self.kind = kind; self.text = text
        self.name = ""; self.source = source; self.sourceBundle = sourceBundle
        self.createdAt = date; self.copiedAt = date; self.favorite = false; self.byteCount = byteCount
    }
    public var title: String {
        if !name.isEmpty { return name }
        if displayKind == .image {
            if isImageFile, let path = text.split(maxSplits: 1, whereSeparator: \.isNewline).first {
                return URL(fileURLWithPath: String(path)).lastPathComponent
            }
            return String(localized: "Copied image")
        }
        return String(text.drop(while: \.isNewline).prefix(160).prefix(while: { !$0.isNewline }))
    }
    public var isImageFile: Bool {
        guard kind == .file else { return false }
        let paths = text.split(whereSeparator: \.isNewline)
        return !paths.isEmpty && paths.allSatisfy { path in
            guard let type = UTType(filenameExtension: URL(fileURLWithPath: String(path)).pathExtension.lowercased()) else { return false }
            return type.conforms(to: .image)
        }
    }
    public var displayKind: ClipKind { isImageFile ? .image : kind }
    public func matches(_ query: String) -> Bool {
        let tokens = query.split(whereSeparator: \.isWhitespace)
        guard !tokens.isEmpty else { return true }
        func normalized(_ value: String) -> String {
            value.lowercased(with: Locale(identifier: "tr_TR"))
                .folding(options: .diacriticInsensitive, locale: Locale(identifier: "tr_TR"))
                .replacingOccurrences(of: "ı", with: "i")
        }
        let fields = [text, name, source, displayKind.title].map(normalized)
        return tokens.allSatisfy { token in
            fields.contains { $0.contains(normalized(String(token))) }
        }
    }
}

public struct Representation: Codable, Equatable {
    public var type: String
    public var data: Data
    public init(type: String, data: Data) { self.type = type; self.data = data }
}
public struct ClipboardPayload: Codable, Equatable {
    public var items: [[Representation]]
    public init(items: [[Representation]]) { self.items = items }
    public var byteCount: Int { items.flatMap { $0 }.reduce(0) { $0 + $1.data.count } }
    public var fingerprint: String {
        var hash = SHA256()
        for item in items {
            hash.update(data: Data("item\0".utf8))
            for rep in item.sorted(by: { $0.type < $1.type }) {
                hash.update(data: Data("\(rep.type.utf8.count):\(rep.type):\(rep.data.count):".utf8))
                hash.update(data: rep.data)
            }
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

public struct Preferences: Codable, Equatable {
    public var maxItems = 500
    public var retentionDays = 30
    public var maxMegabytes = 200
    public var excludedBundles = ["com.agilebits.onepassword7", "com.1password.1password", "com.bitwarden.desktop", "com.apple.Passwords"]
    public init() {}
}
