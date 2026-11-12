import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// A photo chosen for the next message, already downscaled and JPEG-encoded.
struct DraftImage: Identifiable, Equatable {
    let id = UUID()
    let jpeg: Data
}

/// How the photo picker hands over a picture: any image type (HEIC, JPEG, PNG …). Loading plain `Data` can fail on
/// macOS, where the library item is not generic data.
struct PickedPhoto: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { PickedPhoto(data: $0) }
    }
}

/// Cross-platform (ImageIO) helpers: no UIKit / AppKit needed.
enum ImageProcessing {
    static let maxPhotosPerMessage = 4

    /// Downscales to `maxDimension` on the long side (respecting EXIF orientation) and encodes as JPEG, keeping
    /// the request small enough for the API.
    nonisolated static func downscaledJPEG(from data: Data, maxDimension: CGFloat = 1024, quality: CGFloat = 0.7) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = thumbnail(of: source, maxDimension: maxDimension) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// Decodes a display-sized image (long side `maxDimension`) from image data.
    nonisolated static func displayImage(from data: Data, maxDimension: CGFloat = 640) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return thumbnail(of: source, maxDimension: maxDimension)
    }

    nonisolated static func pixelSize(of data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else { return nil }
        return CGSize(width: width, height: height)
    }

    private nonisolated static func thumbnail(of source: CGImageSource, maxDimension: CGFloat) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// A square-cropped photo thumbnail that decodes off the main thread.
struct PhotoThumbnail: View {
    let data: Data
    var size: CGFloat
    var corner: CGFloat = 12
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            Theme.fill
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .accessibilityElement(children: .ignore)
        .task(id: data.count) {
            let data = data
            image = await Task.detached { ImageProcessing.displayImage(from: data, maxDimension: size * 3) }.value
        }
    }
}
