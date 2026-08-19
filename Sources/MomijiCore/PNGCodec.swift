import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum PNGCodec {
    static func decode(_ data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw MomijiError.invalidFormat("ImageIO could not decode an embedded image")
        }
        guard image.width > 0, image.height > 0, image.width <= 4096, image.height <= 4096 else {
            throw MomijiError.resourceLimit("image dimensions must be between 1 and 4096 pixels")
        }
        return image
    }

    static func encode(_ image: CGImage) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw MomijiError.invalidFormat("could not create a PNG encoder")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw MomijiError.invalidFormat("could not encode PNG data")
        }
        return output as Data
    }

    static func makeRGBAImage(width: Int, height: Int, pixels: Data) throws -> CGImage {
        guard width > 0, height > 0, pixels.count == width * height * 4 else {
            throw MomijiError.invalidFormat("invalid RGBA pixel buffer")
        }
        guard let provider = CGDataProvider(data: pixels as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            throw MomijiError.invalidFormat("could not create a cursor image")
        }
        return image
    }

    static func normalized(
        _ data: Data,
        canvasWidth: Int,
        canvasHeight: Int,
        imageWidth: Int,
        imageHeight: Int,
        sourceHotspot: CursorPoint,
        targetHotspot: CursorPoint
    ) throws -> Data {
        let image = try decode(data)
        guard canvasWidth > 0, canvasHeight > 0,
              imageWidth > 0, imageHeight > 0,
              canvasWidth <= 4096, canvasHeight <= 4096,
              imageWidth <= 4096, imageHeight <= 4096 else {
            throw MomijiError.resourceLimit("normalized cursor canvas is invalid")
        }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: canvasWidth,
            height: canvasHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw MomijiError.invalidFormat("could not create normalized cursor canvas")
        }
        context.clear(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))
        context.interpolationQuality = .high
        let offsetX = targetHotspot.x - sourceHotspot.x
        let topOffsetY = targetHotspot.y - sourceHotspot.y
        context.draw(
            image,
            in: CGRect(
                x: offsetX,
                y: Double(canvasHeight - imageHeight) - topOffsetY,
                width: Double(imageWidth),
                height: Double(imageHeight)
            )
        )
        guard let output = context.makeImage() else {
            throw MomijiError.invalidFormat("could not finalize normalized cursor canvas")
        }
        return try encode(output)
    }
}
