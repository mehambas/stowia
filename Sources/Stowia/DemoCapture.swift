import AppKit
import StowiaCore

/// Frames for the README animations: the quick panel under a menu bar on a desktop-like background, plus an ffmpeg
/// concat list. The panel itself is always dark; the background follows the README's light or dark version.
@MainActor private final class DemoRecorder {
    static let width: CGFloat = 620
    static let menuBar: CGFloat = 24
    static let gap: CGFloat = 5
    static let bottom: CGFloat = 36
    private let folder: URL
    private let dark: Bool
    private var frames: [(name: String, seconds: Double)] = []

    init(folder: URL, dark: Bool) {
        self.folder = folder
        self.dark = dark
    }

    func add(_ window: NSWindow, seconds: Double) throws {
        guard let view = window.contentView else { throw DemoError("No content view") }
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw DemoError("No panel bitmap") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let panel = bitmap.cgImage else { throw DemoError("No panel image") }
        let scale = CGFloat(panel.width) / view.bounds.width
        let height = Self.menuBar + Self.gap + view.bounds.height + Self.bottom
        let pixels = (width: Int(Self.width * scale), height: Int(height * scale))
        let colors = dark ? [CGColor(srgbRed: 0.11, green: 0.16, blue: 0.31, alpha: 1), CGColor(srgbRed: 0.33, green: 0.16, blue: 0.36, alpha: 1)]
                          : [CGColor(srgbRed: 0.80, green: 0.87, blue: 0.97, alpha: 1), CGColor(srgbRed: 0.97, green: 0.84, blue: 0.92, alpha: 1)]
        guard let context = CGContext(data: nil, width: pixels.width, height: pixels.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: [0, 1]) else {
            throw DemoError("No canvas")
        }
        context.scaleBy(x: scale, y: scale)
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height), end: CGPoint(x: Self.width, y: 0), options: [])
        drawMenuBar(in: context, top: height)

        let panelRect = CGRect(x: (Self.width - view.bounds.width) / 2, y: Self.bottom, width: view.bounds.width, height: view.bounds.height)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -10), blur: 32, color: CGColor(gray: 0, alpha: 0.45))
        context.draw(panel, in: panelRect)
        context.restoreGState()

        guard let image = context.makeImage() else { throw DemoError("No frame") }
        let name = String(format: "frame-%03d.png", frames.count)
        guard let destination = CGImageDestinationCreateWithURL(folder.appendingPathComponent(name) as CFURL, "public.png" as CFString, 1, nil) else {
            throw DemoError("Could not write \(name)")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw DemoError("Could not write \(name)") }
        frames.append((name, seconds))
    }

    private func drawMenuBar(in context: CGContext, top: CGFloat) {
        let bar = CGRect(x: 0, y: top - Self.menuBar, width: Self.width, height: Self.menuBar)
        context.setFillColor(dark ? CGColor(gray: 0, alpha: 0.32) : CGColor(gray: 1, alpha: 0.5))
        context.fill(bar)
        let ink = dark ? NSColor.white : NSColor.black
        let highlight = CGRect(x: Self.width / 2 - 15, y: bar.minY + 2, width: 30, height: Self.menuBar - 4)
        context.setFillColor(ink.withAlphaComponent(dark ? 0.22 : 0.12).cgColor)
        context.addPath(CGPath(roundedRect: highlight, cornerWidth: 5, cornerHeight: 5, transform: nil))
        context.fillPath()
        if let icon = NSImage(named: "MenuBarIconTemplate"), let mask = icon.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let rect = CGRect(x: highlight.midX - 9, y: highlight.midY - 9, width: 18, height: 18)
            context.saveGState()
            context.clip(to: rect, mask: mask)
            context.setFillColor(ink.cgColor)
            context.fill(rect)
            context.restoreGState()
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: ink]
        let clock = "Fri 16 Oct  10:41" as NSString
        let size = clock.size(withAttributes: attributes)
        clock.draw(at: CGPoint(x: Self.width - 14 - size.width, y: bar.midY - size.height / 2), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    }

    func hold(_ seconds: Double) { frames[frames.count - 1].seconds += seconds }

    func finish() throws {
        guard let last = frames.last else { throw DemoError("No frames") }
        // The concat demuxer drops the last duration unless the last file is listed once more.
        let list = frames.map { "file '\($0.name)'\nduration \($0.seconds)\n" }.joined() + "file '\(last.name)'\n"
        try list.write(to: folder.appendingPathComponent("frames.txt"), atomically: true, encoding: .utf8)
    }
}

private struct DemoError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

extension AppDelegate {
    /// Plays the quick panel with the demo clips and writes the frames to `<output>/dark` and `<output>/light`.
    func captureDemo() async {
        guard let index = CommandLine.arguments.firstIndex(of: "--capture-demo"), CommandLine.arguments.count > index + 1 else {
            print("Usage: Stowia --capture-demo <output-directory>")
            NSApp.terminate(nil); return
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[index + 1])
        do {
            for name in ["dark", "light"] {
                let folder = output.appendingPathComponent(name)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let recorder = DemoRecorder(folder: folder, dark: name == "dark")
                try await playDemo(recorder)
                try recorder.finish()
            }
            print("Demo frames: \(output.path)/dark, \(output.path)/light")
            NSApp.terminate(nil)
        } catch {
            fputs("Demo capture failed: \(error.localizedDescription)\n", stderr)
            NSApp.terminate(nil)
        }
    }

    private func playDemo(_ recorder: DemoRecorder) async throws {
        store.query = ""
        store.filter = .all
        store.compactDetailsVisible = false
        // Off screen and never key: rendering needs neither, and a key panel would take whatever the user is typing.
        compactPanel.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        compactPanel.orderFront(nil)
        store.selection = store.visibleClips.first?.id
        await settle()
        func frame(_ seconds: Double) async throws {
            await settle()
            try recorder.add(compactPanel, seconds: seconds)
        }
        func type(_ text: String) async throws {
            for end in text.indices {
                store.query = String(text[...end])
                store.alignSelection()
                try await frame(0.14)
            }
        }

        try await frame(1.6)
        try await type("reply")
        guard store.selectedClip?.name == "Quick reply" else { throw DemoError("“reply” did not find the quick reply") }
        recorder.hold(0.5)
        store.compactDetailsVisible = true
        try await frame(2.4)
        store.compactDetailsVisible = false
        store.query = ""
        store.selection = store.visibleClips.first?.id
        try await frame(0.6)
        for _ in 0..<2 {
            store.moveSelection(1)
            try await frame(0.45)
        }
        guard store.selectedClip?.name == "Git history" else { throw DemoError("The third clip is not the git command") }
        store.compactDetailsVisible = true
        try await frame(2.0)
        store.compactDetailsVisible = false
        store.filter = .favorites
        store.alignSelection()
        try await frame(1.8)
        store.filter = .image
        store.alignSelection()
        for _ in 0..<30 where store.previewImage == nil { try? await Task.sleep(nanoseconds: 100_000_000) }
        guard store.previewImage != nil else { throw DemoError("The image preview did not load") }
        try await frame(2.4)
        store.filter = .all
        store.alignSelection()
        try await frame(0.8)
    }

    private func settle() async {
        try? await Task.sleep(nanoseconds: 180_000_000)
    }
}
