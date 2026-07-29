import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Renders strings as QR code bitmaps.
enum QRCodeRenderer {
    private static let context = CIContext()

    /// - Parameter size: desired edge length in pixels. The generator emits one pixel
    ///   per module, so the result is scaled up by an integer factor to stay crisp.
    static func image(for string: String, size: CGFloat = 512) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        // Medium correction is what Google Authenticator uses; it keeps the code small
        // enough to stay scannable while tolerating some screen glare.
        filter.correctionLevel = "M"

        guard let output = filter.outputImage else { return nil }

        let scale = max(1, (size / output.extent.width).rounded(.down))
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return context.createCGImage(scaled, from: scaled.extent)
    }

    static func nsImage(for string: String, size: CGFloat = 512) -> NSImage? {
        guard let cgImage = image(for: string, size: size) else { return nil }
        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
    }

    static func pngData(for cgImage: CGImage) -> Data? {
        let representation = NSBitmapImageRep(cgImage: cgImage)
        return representation.representation(using: .png, properties: [:])
    }
}
