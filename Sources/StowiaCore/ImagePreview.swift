import AppKit
import ImageIO

public enum ImagePreview {
    /// Decode at the display size instead of expanding a full-resolution screenshot.
    public static func make(from payload: ClipboardPayload, maxPixelSize: Int) -> NSImage? {
        guard maxPixelSize > 0 else { return nil }
        let representations = payload.items.flatMap { $0 }
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            for representation in representations where representation.type == type.rawValue {
                guard let source = CGImageSourceCreateWithData(representation.data as CFData, nil),
                      let bitmap = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                        kCGImageSourceShouldCacheImmediately: true
                      ] as CFDictionary) else { continue }
                return NSImage(cgImage: bitmap, size: NSSize(width: bitmap.width, height: bitmap.height))
            }
        }
        for representation in representations where representation.type == NSPasteboard.PasteboardType.fileURL.rawValue {
            guard let value = String(data: representation.data, encoding: .utf8),
                  let url = URL(string: value), url.isFileURL,
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let bitmap = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { continue }
            return NSImage(cgImage: bitmap, size: NSSize(width: bitmap.width, height: bitmap.height))
        }
        return nil
    }
}
