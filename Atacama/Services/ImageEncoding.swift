//
//  ImageEncoding.swift
//  Atacama
//
//  Transcodes picked/captured photos to JPEG before upload. Photos from the
//  library are often HEIC, which the newslettr backend's metadata reader doesn't
//  decode (it handles jpg/png/gif/webp), so the app normalizes to JPEG and
//  downscales oversized images to keep uploads small. Platform-branched: UIKit on
//  iOS, AppKit for the macOS build target.
//

import CoreGraphics
import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum ImageEncoding {
    /// Re-encode arbitrary image data (HEIC/PNG/…) as JPEG, downscaled so the
    /// longest edge is at most `maxDimension`. Returns nil when the data is not a
    /// decodable image.
    static func jpegData(from data: Data, maxDimension: CGFloat = 2048, quality: CGFloat = 0.82) -> Data? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        return jpegData(from: image, maxDimension: maxDimension, quality: quality)
        #elseif canImport(AppKit)
        guard let image = NSImage(data: data),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
        #else
        return nil
        #endif
    }

    #if canImport(UIKit)
    /// Re-encode a UIImage (e.g. from the camera) as downscaled JPEG.
    static func jpegData(from image: UIImage, maxDimension: CGFloat = 2048, quality: CGFloat = 0.82) -> Data? {
        downscaled(image, maxDimension: maxDimension).jpegData(compressionQuality: quality)
    }

    private static func downscaled(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longestEdge = max(image.size.width, image.size.height)
        guard longestEdge > maxDimension, longestEdge > 0 else { return image }
        let scale = maxDimension / longestEdge
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
    #endif
}
