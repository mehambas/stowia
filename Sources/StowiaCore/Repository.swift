import Foundation

public final class ClipRepository {
    public let directory: URL
    public private(set) var clips: [Clip] = []
    private let fm = FileManager.default
    private var indexURL: URL { directory.appendingPathComponent("history.json") }
    public init(directory: URL) throws {
        self.directory = directory
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if fm.fileExists(atPath: indexURL.path) {
            clips = try JSONDecoder().decode([Clip].self, from: Data(contentsOf: indexURL))
        }
    }
    public func payload(for clip: Clip) throws -> ClipboardPayload {
        try PropertyListDecoder().decode(ClipboardPayload.self, from: Data(contentsOf: payloadURL(clip.id)))
    }
    public func insert(_ clip: Clip, payload: ClipboardPayload, preferences: Preferences, now: Date = Date()) throws {
        var next = clips
        if let existing = next.firstIndex(where: { $0.fingerprint == clip.fingerprint }) {
            var duplicate = next.remove(at: existing)
            duplicate.copiedAt = clip.copiedAt
            duplicate.source = clip.source
            duplicate.sourceBundle = clip.sourceBundle
            next.insert(duplicate, at: 0)
        } else {
            let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
            try encoder.encode(payload).write(to: payloadURL(clip.id), options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: payloadURL(clip.id).path)
            next.insert(clip, at: 0)
        }
        try commit(pruned(next, preferences: preferences, now: now))
    }
    public func update(_ id: UUID, name: String? = nil, favorite: Bool? = nil) throws {
        var next = clips
        guard let i = next.firstIndex(where: { $0.id == id }) else { return }
        if let name { next[i].name = name }
        if let favorite { next[i].favorite = favorite }
        try commit(next)
    }
    public func delete(_ ids: Set<UUID>) throws { try commit(clips.filter { !ids.contains($0.id) }) }
    public func clearUnprotected(since: Date? = nil) throws {
        try commit(clips.filter { $0.favorite || (since != nil && $0.copiedAt < since!) })
    }
    public func prune(preferences: Preferences, now: Date = Date()) throws {
        let next = pruned(clips, preferences: preferences, now: now)
        if next != clips { try commit(next) }
    }
    private func pruned(_ values: [Clip], preferences: Preferences, now: Date) -> [Clip] {
        var count = 0, bytes = 0
        let cutoff = now.addingTimeInterval(-Double(preferences.retentionDays) * 86400)
        return values.filter { clip in
            if clip.favorite { return true }
            guard clip.copiedAt >= cutoff, count < preferences.maxItems,
                  bytes + clip.byteCount <= preferences.maxMegabytes * 1024 * 1024 else { return false }
            count += 1; bytes += clip.byteCount
            return true
        }
    }
    private func payloadURL(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".clip") }
    private func commit(_ next: [Clip]) throws {
        let removed = Set(clips.map(\.id)).subtracting(next.map(\.id))
        try JSONEncoder().encode(next).write(to: indexURL, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: indexURL.path)
        clips = next
        for id in removed { try? fm.removeItem(at: payloadURL(id)) }
        // Collect interrupted writes only after a successful index commit.
        let retained = Set(next.map { $0.id.uuidString + ".clip" })
        for url in (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            where url.pathExtension == "clip" && !retained.contains(url.lastPathComponent) {
            try? fm.removeItem(at: url)
        }
    }
}
