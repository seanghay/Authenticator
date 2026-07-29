import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Turns whatever the user dropped, opened or picked into decodable bitmaps.
enum ImageLoading {
    /// Image types we will try to read a QR code out of.
    static let supportedContentTypes: [UTType] = [.image, .png, .jpeg, .tiff, .heic, .pdf]

    static func images(at url: URL) -> [CGImage] {
        // Sandboxed reads of user-selected files need the security scope opened when
        // the URL came from a picker; harmless when it is already accessible.
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [] }
        return images(from: source)
    }

    static func images(from data: Data) -> [CGImage] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return [] }
        return images(from: source)
    }

    private static func images(from source: CGImageSource) -> [CGImage] {
        // Multi-page documents (PDF, multi-frame TIFF) can hold several codes; read a
        // bounded number of pages so a large document cannot stall the import.
        let count = min(CGImageSourceGetCount(source), 8)
        return (0..<count).compactMap { index in
            CGImageSourceCreateImageAtIndex(source, index, nil)
        }
    }

    /// Extracts images from a pasteboard-style item provider (drag and drop).
    static func images(from provider: NSItemProvider) async -> [CGImage] {
        if provider.canLoadObject(ofClass: NSImage.self) {
            let image: NSImage? = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: NSImage.self) { object, _ in
                    continuation.resume(returning: object as? NSImage)
                }
            }
            if let cgImage = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                return [cgImage]
            }
        }

        if let url: URL = await loadURL(from: provider) {
            return images(at: url)
        }
        return []
    }

    private static func loadURL(from provider: NSItemProvider) async -> URL? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }

    /// Reads QR codes off the current pasteboard, whether it holds an image or a file.
    static func imagesFromPasteboard() -> [CGImage] {
        let pasteboard = NSPasteboard.general
        if let image = NSImage(pasteboard: pasteboard),
           let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return [cgImage]
        }
        let urls =
            pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
        return urls.flatMap { images(at: $0) }
    }
}
