import AppKit
import SwiftUI
import StowiaCore

enum ClipFilter: String, CaseIterable {
    case all, favorites, text, link, image, file
    var title: String {
        switch self {
        case .all: return String(localized: "All Clips"); case .favorites: return String(localized: "Favorites")
        // In Turkish the filter is plural and the kind singular, so the filter can't share the kind's "Text".
        case .text: return String(localized: "filter.text", defaultValue: "Text"); case .link: return String(localized: "Links")
        case .image: return String(localized: "Images"); case .file: return String(localized: "Files")
        }
    }
    var symbol: String {
        switch self { case .all: return "square.stack.3d.up"; case .favorites: return "star"
        case .text: return "text.alignleft"; case .link: return "link"; case .image: return "photo"; case .file: return "folder" }
    }
    func includes(_ clip: Clip) -> Bool {
        switch self {
        case .all: return true
        case .favorites: return clip.favorite
        case .image: return clip.displayKind == .image
        case .file: return clip.kind == .file && clip.displayKind != .image
        case .text, .link: return clip.kind.rawValue == rawValue
        }
    }
}

@MainActor final class Store: ObservableObject {
    @Published var clips: [Clip] = [] { didSet { cachedVisibleClips = nil } }
    @Published var query = "" { didSet { cachedVisibleClips = nil } }
    @Published var filter: ClipFilter = .all { didSet { cachedVisibleClips = nil } }
    @Published var navigationSelection: UUID?
    @Published var selection: UUID?
    @Published var paused = false
    @Published var preferences = Preferences()
    @Published var error: String?
    @Published var notice: String?
    @Published var libraryVisible = false
    @Published var settingsVisible = false
    @Published var focusRequest = UUID()
    @Published var compactFocusRequest = UUID()
    @Published var compactDetailsVisible = false
    @Published var previewImage: NSImage?
    @Published var hotkeyAvailable = true
    let updater: Updater
    var searchFocused = false
    var compactSearchFocused = false
    let repository: ClipRepository?
    /// None in demo mode, which saves nothing.
    let defaults: UserDefaults?
    private var timer: Timer?
    private var lastChange: Int
    private var tickCount = 0
    private var cachedVisibleClips: [Clip]?
    private var previewTask: Task<Void, Never>?
    private var previewClipID: UUID?
    private var imageTasks: [String: Task<NSImage?, Never>] = [:]
    private let imageQueue = DispatchQueue(label: "com.hamzabasaran.stowia.previews", qos: .userInitiated)
    private let imageCache = NSCache<NSString, NSImage>()
    let demo: Bool
    var onUse: ((Clip, Bool, Bool) -> Void)?

    init(directory: URL, demo: Bool = false) {
        self.demo = demo
        imageCache.totalCostLimit = 32 * 1024 * 1024
        defaults = demo ? nil : .standard
        // The testing variables let the demo try an update, which then stores nothing either.
        updater = Updater(active: !demo || GitHubReleases.testing)
        lastChange = NSPasteboard.general.changeCount
        do { repository = try ClipRepository(directory: directory) }
        catch { repository = nil; self.error = String(localized: "The history couldn’t be opened, so nothing is being saved: \(error.localizedDescription)") }
        if let data = defaults?.data(forKey: "preferences"), let p = try? JSONDecoder().decode(Preferences.self, from: data) { preferences = p }
        paused = defaults?.bool(forKey: "paused") ?? false
        if demo { seedDemoImage(); seedDemo() }
        perform { try repository?.prune(preferences: preferences) }
        refresh()
        if !demo {
            timer = Timer.scheduledTimer(withTimeInterval: 0.65, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.poll() }
            }
        }
    }
    var visibleClips: [Clip] {
        if let cachedVisibleClips { return cachedVisibleClips }
        let values = filter == .all && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? clips : clips.filter { filter.includes($0) && $0.matches(query) }
        cachedVisibleClips = values
        return values
    }
    var selectedClip: Clip? { visibleClips.first { $0.id == selection } }
    var favoriteCount: Int { clips.filter(\.favorite).count }
    var totalBytes: Int { clips.reduce(0) { $0 + $1.byteCount } }
    func alignSelection() {
        if !visibleClips.contains(where: { $0.id == selection }) { selection = visibleClips.first?.id }
        loadPreview()
    }
    func moveSelection(_ offset: Int) {
        let values = visibleClips
        guard !values.isEmpty else { return }
        let index = values.firstIndex { $0.id == selection } ?? 0
        selection = values[max(0, min(values.count - 1, index + offset))].id
        navigationSelection = selection
    }
    func loadPreview() {
        let clip = selectedClip.flatMap { $0.displayKind == .image ? $0 : nil }
        guard previewClipID != clip?.id else { return }
        previewTask?.cancel()
        previewClipID = clip?.id
        if previewImage != nil { previewImage = nil }
        guard let clip else { return }
        previewTask = Task { [weak self] in
            // Let quick pointer/key navigation settle before decoding a large preview.
            try? await Task.sleep(nanoseconds: 60_000_000)
            guard !Task.isCancelled, let self else { return }
            let image = await self.image(for: clip, maxPixelSize: 960)
            guard !Task.isCancelled, self.selection == clip.id else { return }
            self.previewImage = image
        }
    }
    func image(for clip: Clip, maxPixelSize: Int) async -> NSImage? {
        guard clip.displayKind == .image, let directory = repository?.directory else { return nil }
        let key = "\(clip.id)-\(maxPixelSize)"
        if let cached = imageCache.object(forKey: key as NSString) { return cached }
        if let pending = imageTasks[key] { return await pending.value }
        let queue = imageQueue
        let url = directory.appendingPathComponent(clip.id.uuidString + ".clip")
        let task = Task<NSImage?, Never> {
            await withCheckedContinuation { continuation in
                queue.async {
                    let image: NSImage? = autoreleasepool {
                        guard let data = try? Data(contentsOf: url),
                              let payload = try? PropertyListDecoder().decode(ClipboardPayload.self, from: data) else { return nil }
                        return ImagePreview.make(from: payload, maxPixelSize: maxPixelSize)
                    }
                    continuation.resume(returning: image)
                }
            }
        }
        imageTasks[key] = task
        let image = await task.value
        imageTasks[key] = nil
        if let image {
            imageCache.setObject(image, forKey: key as NSString, cost: Int(image.size.width * image.size.height) * 4)
        }
        return image
    }
    func toggleFavorite(_ clip: Clip) {
        perform { try repository?.update(clip.id, favorite: !clip.favorite) }
        refresh()
    }
    func rename(_ clip: Clip, to name: String) {
        perform { try repository?.update(clip.id, name: name.trimmingCharacters(in: .whitespacesAndNewlines)) }
        refresh()
    }
    func delete(_ clip: Clip) { perform { try repository?.delete([clip.id]) }; refresh() }
    func clear(since: Date? = nil) { perform { try repository?.clearUnprotected(since: since) }; refresh() }
    func togglePause() {
        paused.toggle(); defaults?.set(paused, forKey: "paused")
        lastChange = NSPasteboard.general.changeCount
    }
    func savePreferences() {
        perform {
            defaults?.set(try JSONEncoder().encode(preferences), forKey: "preferences")
            try repository?.prune(preferences: preferences)
        }
        refresh()
    }
    func excludeCurrentSource() {
        guard let clip = selectedClip, !clip.sourceBundle.isEmpty else { return }
        if !preferences.excludedBundles.contains(clip.sourceBundle) { preferences.excludedBundles.append(clip.sourceBundle) }
        savePreferences(); showNotice(String(localized: "Copies from \(clip.source) won’t be saved anymore."))
    }
    @discardableResult func copy(_ clip: Clip, plain: Bool) -> Bool {
        guard let repository else { return false }
        do {
            let payload = try repository.payload(for: clip)
            guard PasteboardCapture.restore(payload, to: .general, plainText: plain ? clip.text : nil) else {
                error = String(localized: "The clip couldn’t be put on the clipboard."); return false
            }
            lastChange = NSPasteboard.general.changeCount
            return true
        } catch { self.error = String(localized: "The clip couldn’t be read: \(error.localizedDescription)"); return false }
    }
    func useSelected(plain: Bool = false, paste: Bool = true) {
        guard let clip = selectedClip else { return }
        onUse?(clip, plain && (clip.kind == .text || clip.kind == .link), paste)
    }
    func showNotice(_ message: String) {
        notice = message
        Task { try? await Task.sleep(nanoseconds: 3_000_000_000); if notice == message { notice = nil } }
    }
    func revealFile(_ clip: Clip) {
        guard let payload = try? repository?.payload(for: clip) else { return }
        let urls = payload.items.flatMap { $0 }.filter { $0.type == NSPasteboard.PasteboardType.fileURL.rawValue }
            .compactMap { String(data: $0.data, encoding: .utf8) }.compactMap(URL.init(string:))
        let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else { error = String(localized: "The file was moved or deleted. Stowia keeps only the location of files."); return }
        NSWorkspace.shared.activateFileViewerSelecting(existing)
    }
    func saveImage(_ clip: Clip) {
        guard let payload = try? repository?.payload(for: clip) else { return }
        let panel = NSSavePanel()
        let representations = payload.items.flatMap { $0 }
        if clip.isImageFile,
           let rep = representations.first(where: { $0.type == NSPasteboard.PasteboardType.fileURL.rawValue }),
           let source = String(data: rep.data, encoding: .utf8).flatMap(URL.init(string:)) {
            panel.nameFieldStringValue = source.lastPathComponent
            if panel.runModal() == .OK, let destination = panel.url {
                perform { try FileManager.default.copyItem(at: source, to: destination) }
            }
            return
        }
        guard let rep = representations.first(where: { $0.type == NSPasteboard.PasteboardType.png.rawValue || $0.type == NSPasteboard.PasteboardType.tiff.rawValue }) else { return }
        panel.nameFieldStringValue = String(localized: "Image") + "." + (rep.type == NSPasteboard.PasteboardType.png.rawValue ? "png" : "tiff")
        if panel.runModal() == .OK, let url = panel.url { perform { try rep.data.write(to: url) } }
    }
    private func refresh() {
        let next = repository?.clips ?? []
        if clips != next { clips = next }
        alignSelection()
    }
    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { self.error = String(localized: "The change couldn’t be saved: \(error.localizedDescription)") }
    }
    private func poll() {
        tickCount += 1
        if tickCount % 90 == 0 { perform { try repository?.prune(preferences: preferences) }; refresh() }
        let board = NSPasteboard.general
        guard board.changeCount != lastChange else { return }
        lastChange = board.changeCount
        guard !paused, let repository else { return }
        let front = NSWorkspace.shared.frontmostApplication
        guard let (clip, payload) = PasteboardCapture.read(board, source: front?.localizedName ?? String(localized: "Unknown app"),
                                                         bundle: front?.bundleIdentifier ?? "", preferences: preferences) else { return }
        perform { try repository.insert(clip, payload: payload, preferences: preferences) }
        refresh()
    }
    private func seedDemo() {
        guard let repository, repository.clips.allSatisfy({ $0.kind == .image }) else { return }
        let samples: [(String, String, ClipKind, String)] = [
            ("Search less today. Make more.", "Notes", .text, ""),
            ("https://developer.apple.com/design/human-interface-guidelines", "Safari", .link, "Apple design guidelines"),
            ("git log --oneline --graph --decorate -20", "Terminal", .text, "Git history"),
            ("Hi Sam,\n\nThanks for the feedback. I’ll finish the changes and send them over later today.\n\nBest,\nAlex", "Mail", .text, "Quick reply"),
            ("struct Idea: Identifiable {\n    let id = UUID()\n    var title: String\n    var isWorthKeeping = true\n}", "Xcode", .text, ""),
            ("The next idea is hiding in the last thing you copied.", "Notes", .text, "")
        ]
        for (index, sample) in samples.enumerated().reversed() {
            let payload = ClipboardPayload(items: [[Representation(type: NSPasteboard.PasteboardType.string.rawValue, data: Data(sample.0.utf8))]])
            var clip = Clip(fingerprint: payload.fingerprint, kind: sample.2, text: sample.0, source: sample.1,
                            date: Date().addingTimeInterval(Double(-index * 240)), byteCount: payload.byteCount)
            clip.name = sample.3; clip.favorite = !sample.3.isEmpty
            try? repository.insert(clip, payload: payload, preferences: preferences)
        }
    }
    private func seedDemoImage() {
        guard let repository, !repository.clips.contains(where: { $0.kind == .image }) else { return }
        // A deterministic native drawing for UI verification; no user clipboard data.
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 900, pixelsHigh: 500, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor(calibratedWhite: 0.87, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 900, height: 500).fill()
        NSColor(calibratedWhite: 0.2, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 55, y: 55, width: 790, height: 390), xRadius: 30, yRadius: 30).fill()
        let words = "One idea.\nOne next step." as NSString
        words.draw(in: NSRect(x: 105, y: 180, width: 700, height: 200), withAttributes: [
            .font: NSFont.systemFont(ofSize: 62, weight: .semibold), .foregroundColor: NSColor.white
        ])
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .png, properties: [:]) else { return }
        let payload = ClipboardPayload(items: [[Representation(type: NSPasteboard.PasteboardType.png.rawValue, data: data)]])
        var clip = Clip(fingerprint: payload.fingerprint, kind: .image, text: "", source: "Preview", date: Date().addingTimeInterval(-1680), byteCount: data.count)
        clip.name = "Design note"
        try? repository.insert(clip, payload: payload, preferences: preferences)
    }
}
