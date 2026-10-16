import XCTest
import AppKit
@testable import StowiaCore

final class StowiaCoreTests: XCTestCase {
    func testImagePreviewsDownsamplePNGAndTIFFWithoutDistorting() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 200,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        for (format, type) in [(NSBitmapImageRep.FileType.png, NSPasteboard.PasteboardType.png), (.tiff, .tiff)] {
            let data = try XCTUnwrap(bitmap.representation(using: format, properties: [:]))
            let payload = ClipboardPayload(items: [[Representation(type: type.rawValue, data: data)]])
            let preview = try XCTUnwrap(ImagePreview.make(from: payload, maxPixelSize: 96))
            XCTAssertEqual(preview.size.width, 96)
            XCTAssertEqual(preview.size.height, 48)
        }
    }
    func testImagePreviewRejectsInvalidDataAndFallsBackToTIFF() throws {
        let invalid = Representation(type: NSPasteboard.PasteboardType.png.rawValue, data: Data("invalid".utf8))
        XCTAssertNil(ImagePreview.make(from: ClipboardPayload(items: [[invalid]]), maxPixelSize: 96))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 10, pixelsHigh: 20,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        let tiff = try XCTUnwrap(bitmap.representation(using: .tiff, properties: [:]))
        let payload = ClipboardPayload(items: [[invalid, Representation(type: NSPasteboard.PasteboardType.tiff.rawValue, data: tiff)]])
        XCTAssertNotNil(ImagePreview.make(from: payload, maxPixelSize: 96))
        XCTAssertNil(ImagePreview.make(from: payload, maxPixelSize: 0))
    }
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("stowia-tests-" + UUID().uuidString)
    }
    override func tearDownWithError() throws { if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) } }
    private func sample(_ text: String, date: Date = Date()) -> (Clip, ClipboardPayload) {
        let payload = ClipboardPayload(items: [[Representation(type: NSPasteboard.PasteboardType.string.rawValue, data: Data(text.utf8))]])
        return (Clip(fingerprint: payload.fingerprint, kind: .text, text: text, date: date, byteCount: payload.byteCount), payload)
    }
    func testDuplicatePreservesFavoriteNameAndSurvivesRelaunch() throws {
        let repo = try ClipRepository(directory: root)
        let first = sample("git status")
        try repo.insert(first.0, payload: first.1, preferences: Preferences())
        try repo.update(first.0.id, name: "İş komutu", favorite: true)
        let other = sample("başka kayıt")
        try repo.insert(other.0, payload: other.1, preferences: Preferences())
        let duplicate = sample("git status", date: Date().addingTimeInterval(5))
        try repo.insert(duplicate.0, payload: duplicate.1, preferences: Preferences())
        let reopened = try ClipRepository(directory: root)
        XCTAssertEqual(reopened.clips.count, 2)
        XCTAssertEqual(reopened.clips[0].id, first.0.id)
        XCTAssertTrue(reopened.clips[0].favorite)
        XCTAssertEqual(reopened.clips[0].name, "İş komutu")
        XCTAssertEqual(try reopened.payload(for: reopened.clips[0]), first.1)
    }
    func testRetentionAndClearProtectFavoritesAndDeletePayloads() throws {
        let repo = try ClipRepository(directory: root)
        let now = Date()
        let old = sample("koru", date: now.addingTimeInterval(-86400 * 5))
        try repo.insert(old.0, payload: old.1, preferences: Preferences(), now: now)
        try repo.update(old.0.id, favorite: true)
        let recent = sample("sil", date: now)
        try repo.insert(recent.0, payload: recent.1, preferences: Preferences(), now: now)
        var prefs = Preferences(); prefs.retentionDays = 1; prefs.maxItems = 0; prefs.maxMegabytes = 0
        try repo.prune(preferences: prefs, now: now)
        XCTAssertEqual(repo.clips.map(\.id), [old.0.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(recent.0.id.uuidString + ".clip").path))
        try repo.clearUnprotected()
        XCTAssertEqual(repo.clips.count, 1)
        try repo.delete([old.0.id])
        XCTAssertTrue(repo.clips.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(old.0.id.uuidString + ".clip").path))
    }
    func testCountByteBudgetAndHourClear() throws {
        let repo = try ClipRepository(directory: root)
        let now = Date()
        var prefs = Preferences(); prefs.maxItems = 2
        for (text, age) in [("a", 7200.0), ("b", 4000.0), ("c", 0.0)] {
            let value = sample(text, date: now.addingTimeInterval(-age))
            try repo.insert(value.0, payload: value.1, preferences: prefs, now: now)
        }
        XCTAssertEqual(repo.clips.map(\.text), ["c", "b"])
        try repo.clearUnprotected(since: now.addingTimeInterval(-3600))
        XCTAssertEqual(repo.clips.map(\.text), ["b"])
        prefs.maxMegabytes = 0
        try repo.prune(preferences: prefs, now: now)
        XCTAssertTrue(repo.clips.isEmpty)
    }
    func testSearchIncludesTurkishNameSourceAndAllWords() {
        var value = sample("Terminal komutu").0
        value.name = "İş bağlantısı"; value.source = "Safari"
        XCTAssertTrue(value.matches("iş safari"))
        XCTAssertTrue(value.matches("İŞ"))
        XCTAssertFalse(value.matches("iş chrome"))
    }
    func testEmptySearchAndLongMultilineTitle() {
        let text = "İlk satır\n" + String(repeating: "uzun içerik\n", count: 100_000)
        let clip = Clip(fingerprint: "large", kind: .text, text: text, byteCount: text.utf8.count)
        XCTAssertTrue(clip.matches(""))
        XCTAssertTrue(clip.matches(" \n\t"))
        XCTAssertEqual(clip.title, "İlk satır")
        var leadingNewlines = clip
        leadingNewlines.text = "\n\n" + text
        XCTAssertEqual(leadingNewlines.title, "İlk satır")
        var longLine = clip
        longLine.text = String(repeating: "ş", count: 200) + "\nson"
        XCTAssertEqual(longLine.title, String(repeating: "ş", count: 160))
    }
    func testLargeHistoryEmptySearchPerformance() {
        let text = String(repeating: "Geçmiş satırı\n", count: 10_000)
        let clips = (0..<500).map { _ in
            Clip(fingerprint: "large", kind: .text, text: text, byteCount: text.utf8.count)
        }
        measure {
            XCTAssertEqual(clips.filter { $0.matches("") }.count, 500)
        }
    }
    func testCorruptIndexIsNotSilentlyOverwritten() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("history.json")
        let invalid = Data("not json".utf8)
        try invalid.write(to: url)
        XCTAssertThrowsError(try ClipRepository(directory: root))
        XCTAssertEqual(try Data(contentsOf: url), invalid)
    }
    func testSensitiveExcludedAndOversizeClipboardAreRejected() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let item = NSPasteboardItem()
        item.setString("secret", forType: .string)
        item.setString("1", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        board.writeObjects([item])
        XCTAssertNil(PasteboardCapture.read(board, source: "Test", bundle: "test", preferences: Preferences()))
        board.clearContents(); board.setString("visible", forType: .string)
        XCTAssertNil(PasteboardCapture.read(board, source: "Passwords", bundle: "com.apple.Passwords", preferences: Preferences()))
        XCTAssertNil(PasteboardCapture.read(board, source: "Test", bundle: "test", preferences: Preferences(), maxBytes: 2))
    }
    func testRichTextRoundTripAndPlainTextRemovesFormatting() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let item = NSPasteboardItem()
        item.setString("Hello", forType: .string)
        item.setString("<b>Hello</b>", forType: .html)
        board.writeObjects([item])
        let result = try XCTUnwrap(PasteboardCapture.read(board, source: "Test", bundle: "test", preferences: Preferences()))
        XCTAssertEqual(result.0.kind, .text)
        XCTAssertTrue(PasteboardCapture.restore(result.1, to: board))
        XCTAssertEqual(board.string(forType: .html), "<b>Hello</b>")
        XCTAssertNil(PasteboardCapture.read(board, source: "Test", bundle: "test", preferences: Preferences()))
        XCTAssertTrue(PasteboardCapture.restore(result.1, to: board, plainText: result.0.text))
        XCTAssertNil(board.string(forType: .html))
        XCTAssertEqual(board.string(forType: .string), "Hello")
    }
    func testMultipleFileURLsAndImageRoundTrip() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let urls = [URL(fileURLWithPath: "/tmp/one.txt"), URL(fileURLWithPath: "/tmp/two.txt")]
        board.writeObjects(urls as [NSURL])
        let result = try XCTUnwrap(PasteboardCapture.read(board, source: "Finder", bundle: "com.apple.finder", preferences: Preferences()))
        XCTAssertEqual(result.0.kind, .file)
        XCTAssertEqual(result.1.items.count, 2)
        XCTAssertTrue(PasteboardCapture.restore(result.1, to: board))
        XCTAssertEqual(board.pasteboardItems?.count, 2)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        board.clearContents(); board.setData(png, forType: .png)
        let image = try XCTUnwrap(PasteboardCapture.read(board, source: "Preview", bundle: "preview", preferences: Preferences()))
        XCTAssertEqual(image.0.kind, .image)
        XCTAssertTrue(PasteboardCapture.restore(image.1, to: board))
        XCTAssertEqual(board.data(forType: .png), png)
    }
    func testLinkRecognitionAndRepresentationOrderIndependentHash() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("https://example.com/path", forType: .string)
        XCTAssertEqual(PasteboardCapture.read(board, source: "Test", bundle: "test", preferences: Preferences())?.0.kind, .link)
        let a = Representation(type: "text", data: Data("hi".utf8))
        let b = Representation(type: "html", data: Data("<b>hi</b>".utf8))
        XCTAssertEqual(ClipboardPayload(items: [[a,b]]).fingerprint, ClipboardPayload(items: [[b,a]]).fingerprint)
        XCTAssertNotEqual(ClipboardPayload(items: [[a,b]]).fingerprint, ClipboardPayload(items: [[a],[b]]).fingerprint)
    }
}
