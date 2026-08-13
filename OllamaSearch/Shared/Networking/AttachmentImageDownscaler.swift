import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Shrinks attached images before they go over the wire.
///
/// mira-core caps every image at `mira_mlx_vision_max_pixels` (1 MP by default)
/// the moment it arrives, so anything larger is decoded, resized and thrown away
/// server-side. Sending it full size only costs upload time, and it costs it in
/// the case the whole remote-access setup exists for: a phone off the LAN.
///
/// Measured on real files: a 5712x4284 photo is 6.3 MB on disk and 8.4 MB once
/// base64'd into the request body. At a 1600px longest edge it is roughly an
/// eighth of that, and the model sees exactly the same thing either way.
///
/// Nothing here is required for correctness — the server handles any size. This
/// is bandwidth, not behaviour.
///
/// `nonisolated` because it is pure CoreGraphics/ImageIO with no main-actor state
/// and is deliberately run in a detached task (see `ChatViewModel.send`) so the
/// resize does not block the UI. Under main-actor-by-default it would otherwise be
/// `@MainActor` and could not be called from that detached context.
nonisolated enum AttachmentImageDownscaler {

    /// Longest edge in pixels. 1600 gives ~1.9 MP on a 4:3 frame, comfortably
    /// above the server's 1 MP ceiling so the app is never the binding
    /// constraint if that ceiling is raised, and still ~6x smaller than a
    /// 12 MP phone photo.
    static let maxPixelSize = 1600

    static let jpegQuality = 0.85

    /// Non-image payloads and images already under the cap pass through
    /// untouched — this never re-encodes something it is not shrinking.
    static func downscaling(_ attachments: [AttachmentPayload]) -> [AttachmentPayload] {
        attachments.map { payload in
            guard case .fileData(let name, let data, let mimeType) = payload,
                  mimeType.hasPrefix("image/"),
                  let shrunk = downscale(data, mimeType: mimeType)
            else { return payload }
            return .fileData(name: name, data: shrunk, mimeType: mimeType)
        }
    }

    /// Returns nil when the image should be left alone: already small enough,
    /// undecodable, or an encoder we cannot write back out. Callers keep the
    /// original in every one of those cases.
    static func downscale(_ data: Data, mimeType: String) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }

        guard max(width, height) > maxPixelSize else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Bakes EXIF orientation into the pixels. Without it a portrait
            // photo shrinks correctly and then arrives on its side, because the
            // server reads pixels and never looks at the orientation tag.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source, 0, options as CFDictionary
        ) else { return nil }

        // Keep the source container. Re-encoding a PNG screenshot as JPEG puts
        // ringing around small text, and small text in screenshots is precisely
        // what the vision path is read for.
        let outType = UTType(mimeType: mimeType) ?? .jpeg
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            out, outType.identifier as CFString, 1, nil
        ) ?? CGImageDestinationCreateWithData(
            out, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }

        CGImageDestinationAddImage(dest, thumbnail, [
            kCGImageDestinationLossyCompressionQuality: jpegQuality
        ] as CFDictionary)

        guard CGImageDestinationFinalize(dest), out.length > 0 else { return nil }

        // Fewer pixels does not guarantee fewer bytes. Re-encoding an already
        // well-compressed source at quality 0.85 can land larger than the
        // original: measured on a 1440x1799 JPEG that went 627 KB -> 689 KB.
        // Keeping the original there costs nothing and avoids paying CPU and a
        // generation of quality loss to make the upload bigger.
        guard out.length < data.count else { return nil }
        return out as Data
    }
}
