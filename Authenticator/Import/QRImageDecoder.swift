import CoreImage
import Foundation
import Vision

/// Pulls QR payload strings out of a still image.
enum QRImageDecoder {
    /// Vision is the primary engine; CoreImage's older detector is kept as a fallback
    /// because it occasionally reads low-contrast or unusual codes that Vision skips.
    static func payloads(in image: CGImage) async -> [String] {
        var results = await visionPayloads(in: image)
        if results.isEmpty {
            results = coreImagePayloads(in: image)
        }
        // Preserve order but drop repeats — a screenshot can contain the same code twice.
        var seen = Set<String>()
        return results.filter { seen.insert($0).inserted }
    }

    private static func visionPayloads(in image: CGImage) async -> [String] {
        var request = DetectBarcodesRequest()
        request.symbologies = [.qr]
        do {
            let observations = try await request.perform(on: image)
            return observations.compactMap(\.payloadString)
        } catch {
            return []
        }
    }

    private static func coreImagePayloads(in image: CGImage) -> [String] {
        let context = CIContext()
        let detector = CIDetector(
            ofType: CIDetectorTypeQRCode,
            context: context,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        )
        let features = detector?.features(in: CIImage(cgImage: image)) ?? []
        return features.compactMap { ($0 as? CIQRCodeFeature)?.messageString }
    }
}
