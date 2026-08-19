import CoreGraphics
import Foundation

public struct ParsedCursorRepresentation: Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var hotspotX: Int
    public var hotspotY: Int
    public var pngData: Data
}

public struct ParsedCUR: Equatable, Sendable {
    public var representations: [ParsedCursorRepresentation]
}

public struct CURParser: Sendable {
    public static let maximumFileSize = 64 * 1_024 * 1_024
    public static let maximumRepresentations = 64

    public init() {}

    public func parse(data: Data) throws -> ParsedCUR {
        guard data.count <= Self.maximumFileSize else {
            throw MomijiError.resourceLimit("CUR file exceeds 64 MiB")
        }
        let reader = BinaryReader(data: data)
        guard try reader.uint16LE(at: 0) == 0 else {
            throw MomijiError.invalidFormat("CUR reserved header must be zero")
        }
        let type = try reader.uint16LE(at: 2)
        guard type == 1 || type == 2 else {
            throw MomijiError.invalidFormat("embedded resource is neither ICO nor CUR")
        }
        let count = Int(try reader.uint16LE(at: 4))
        guard count > 0, count <= Self.maximumRepresentations else {
            throw MomijiError.resourceLimit("invalid CUR representation count \(count)")
        }
        try reader.require(6..<(6 + count * 16))

        var decoded: [ParsedCursorRepresentation] = []
        decoded.reserveCapacity(count)
        var totalPixels = 0
        for index in 0..<count {
            let entry = 6 + index * 16
            let declaredWidth = Int(try reader.byte(at: entry)).nonzeroOr256
            let declaredHeight = Int(try reader.byte(at: entry + 1)).nonzeroOr256
            let hotspotX = type == 2 ? Int(try reader.uint16LE(at: entry + 4)) : 0
            let hotspotY = type == 2 ? Int(try reader.uint16LE(at: entry + 6)) : 0
            let length = try checkedInt(try reader.uint32LE(at: entry + 8))
            let offset = try checkedInt(try reader.uint32LE(at: entry + 12))
            guard length > 0, offset >= 6 + count * 16, offset <= data.count, length <= data.count - offset else {
                throw MomijiError.truncatedData
            }
            let payload = try reader.slice(offset..<(offset + length))
            let image: CGImage
            if payload.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
                image = try PNGCodec.decode(payload)
            } else {
                image = try decodeDIB(payload)
            }
            guard image.width == declaredWidth, image.height == declaredHeight else {
                throw MomijiError.invalidFormat("CUR directory dimensions do not match image data")
            }
            guard hotspotX < image.width, hotspotY < image.height else {
                throw MomijiError.invalidFormat("CUR hotspot is outside the image")
            }
            let pixels = image.width.multipliedReportingOverflow(by: image.height)
            let aggregate = totalPixels.addingReportingOverflow(pixels.partialValue)
            guard !pixels.overflow, !aggregate.overflow, aggregate.partialValue <= 64 * 1_024 * 1_024 else {
                throw MomijiError.resourceLimit("CUR decoded images exceed 64 megapixels")
            }
            totalPixels = aggregate.partialValue
            decoded.append(.init(
                width: image.width,
                height: image.height,
                hotspotX: hotspotX,
                hotspotY: hotspotY,
                pngData: try PNGCodec.encode(image)
            ))
        }

        return ParsedCUR(representations: decoded.sorted {
            ($0.width * $0.height, $0.width) < ($1.width * $1.height, $1.width)
        })
    }

    private func decodeDIB(_ data: Data) throws -> CGImage {
        let reader = BinaryReader(data: data)
        let headerSize = try checkedInt(try reader.uint32LE(at: 0))
        guard headerSize >= 40, headerSize <= data.count else {
            throw MomijiError.unsupportedBitmap("only BITMAPINFOHEADER-compatible DIBs are supported")
        }
        let signedWidth = Int(try reader.int32LE(at: 4))
        let signedStoredHeight = Int(try reader.int32LE(at: 8))
        guard signedWidth > 0, signedStoredHeight != 0 else {
            throw MomijiError.invalidFormat("invalid DIB dimensions")
        }
        let width = signedWidth
        let storedHeight = abs(signedStoredHeight)
        guard storedHeight % 2 == 0 else {
            throw MomijiError.invalidFormat("cursor DIB height must include XOR and AND masks")
        }
        let height = storedHeight / 2
        guard width <= 4096, height > 0, height <= 4096 else {
            throw MomijiError.resourceLimit("DIB dimensions exceed 4096 pixels")
        }
        guard try reader.uint16LE(at: 12) == 1 else {
            throw MomijiError.unsupportedBitmap("DIB plane count is not 1")
        }
        let bitCount = Int(try reader.uint16LE(at: 14))
        guard [1, 4, 8, 24, 32].contains(bitCount) else {
            throw MomijiError.unsupportedBitmap("\(bitCount)-bit DIB")
        }
        let compression = try reader.uint32LE(at: 16)
        guard compression == 0 || (compression == 3 && bitCount == 32) else {
            throw MomijiError.unsupportedBitmap("compressed DIB type \(compression)")
        }

        let bitMasks: DIBBitMasks?
        if compression == 3 {
            guard headerSize == 40 || headerSize >= 52 else {
                throw MomijiError.unsupportedBitmap("BITFIELDS header does not contain RGB masks")
            }
            let redMask = try reader.uint32LE(at: 40)
            let greenMask = try reader.uint32LE(at: 44)
            let blueMask = try reader.uint32LE(at: 48)
            let alphaMask = headerSize >= 56 ? try reader.uint32LE(at: 52) : 0
            guard redMask != 0, greenMask != 0, blueMask != 0,
                  redMask & greenMask == 0, redMask & blueMask == 0, greenMask & blueMask == 0,
                  alphaMask == 0 || (alphaMask & (redMask | greenMask | blueMask)) == 0 else {
                throw MomijiError.invalidFormat("DIB color masks overlap or are empty")
            }
            bitMasks = DIBBitMasks(red: redMask, green: greenMask, blue: blueMask, alpha: alphaMask)
        } else {
            bitMasks = nil
        }

        let colorsUsed = Int(try reader.uint32LE(at: 32))
        let paletteCount = bitCount <= 8 ? (colorsUsed == 0 ? 1 << bitCount : colorsUsed) : 0
        guard paletteCount <= 256 else { throw MomijiError.resourceLimit("DIB palette is too large") }
        let masksSize = compression == 3 && headerSize == 40 ? 12 : 0
        let paletteOffset = headerSize + masksSize
        let paletteBytes = try checkedMultiply(paletteCount, 4)
        try reader.require(paletteOffset..<(paletteOffset + paletteBytes))
        var palette: [(UInt8, UInt8, UInt8)] = []
        palette.reserveCapacity(paletteCount)
        for index in 0..<paletteCount {
            let offset = paletteOffset + index * 4
            palette.append((try reader.byte(at: offset + 2), try reader.byte(at: offset + 1), try reader.byte(at: offset)))
        }

        let xorOffset = paletteOffset + paletteBytes
        let xorStride = ((try checkedMultiply(width, bitCount) + 31) / 32) * 4
        let xorBytes = try checkedMultiply(xorStride, height)
        let andOffset = xorOffset + xorBytes
        let andStride = ((width + 31) / 32) * 4
        let andBytes = try checkedMultiply(andStride, height)
        try reader.require(xorOffset..<(andOffset + andBytes))

        var usesAlpha = false
        if bitCount == 32, let bitMasks, bitMasks.alpha != 0 {
            for row in 0..<height where !usesAlpha {
                for column in 0..<width {
                    let value = try reader.uint32LE(at: xorOffset + row * xorStride + column * 4)
                    if extractChannel(value, mask: bitMasks.alpha) != 0 {
                        usesAlpha = true
                        break
                    }
                }
            }
        } else if bitCount == 32, bitMasks == nil {
            for row in 0..<height where !usesAlpha {
                for column in 0..<width {
                    if try reader.byte(at: xorOffset + row * xorStride + column * 4 + 3) != 0 {
                        usesAlpha = true
                        break
                    }
                }
            }
        }

        var pixels = Data(repeating: 0, count: try checkedMultiply(try checkedMultiply(width, height), 4))
        let bottomUp = signedStoredHeight > 0
        for sourceRow in 0..<height {
            let destinationRow = bottomUp ? height - sourceRow - 1 : sourceRow
            for column in 0..<width {
                let source = xorOffset + sourceRow * xorStride
                let rgba: (UInt8, UInt8, UInt8, UInt8)
                switch bitCount {
                case 32:
                    let pixel = source + column * 4
                    if let bitMasks {
                        let value = try reader.uint32LE(at: pixel)
                        rgba = (
                            extractChannel(value, mask: bitMasks.red),
                            extractChannel(value, mask: bitMasks.green),
                            extractChannel(value, mask: bitMasks.blue),
                            usesAlpha ? extractChannel(value, mask: bitMasks.alpha) : 255
                        )
                    } else {
                        rgba = (
                            try reader.byte(at: pixel + 2),
                            try reader.byte(at: pixel + 1),
                            try reader.byte(at: pixel),
                            usesAlpha ? try reader.byte(at: pixel + 3) : 255
                        )
                    }
                case 24:
                    let pixel = source + column * 3
                    rgba = (try reader.byte(at: pixel + 2), try reader.byte(at: pixel + 1), try reader.byte(at: pixel), 255)
                case 8:
                    rgba = try palettePixel(palette, index: Int(reader.byte(at: source + column)), alpha: 255)
                case 4:
                    let packed = try reader.byte(at: source + column / 2)
                    let index = column.isMultiple(of: 2) ? Int(packed >> 4) : Int(packed & 0x0F)
                    rgba = try palettePixel(palette, index: index, alpha: 255)
                case 1:
                    let packed = try reader.byte(at: source + column / 8)
                    let index = Int((packed >> UInt8(7 - (column % 8))) & 1)
                    rgba = try palettePixel(palette, index: index, alpha: 255)
                default:
                    throw MomijiError.unsupportedBitmap("unexpected bit depth")
                }

                let maskByte = try reader.byte(at: andOffset + sourceRow * andStride + column / 8)
                let masked = ((maskByte >> UInt8(7 - (column % 8))) & 1) == 1
                let output = (destinationRow * width + column) * 4
                pixels[output] = rgba.0
                pixels[output + 1] = rgba.1
                pixels[output + 2] = rgba.2
                pixels[output + 3] = masked ? 0 : rgba.3
            }
        }
        return try PNGCodec.makeRGBAImage(width: width, height: height, pixels: pixels)
    }
}

private struct DIBBitMasks {
    var red: UInt32
    var green: UInt32
    var blue: UInt32
    var alpha: UInt32
}

private extension Int {
    var nonzeroOr256: Int { self == 0 ? 256 : self }
}

private func checkedInt(_ value: UInt32) throws -> Int {
    return Int(value)
}

private func checkedMultiply(_ lhs: Int, _ rhs: Int) throws -> Int {
    let result = lhs.multipliedReportingOverflow(by: rhs)
    guard !result.overflow, result.partialValue >= 0 else {
        throw MomijiError.resourceLimit("integer overflow")
    }
    return result.partialValue
}

private func extractChannel(_ value: UInt32, mask: UInt32) -> UInt8 {
    guard mask != 0 else { return 0 }
    let shift = mask.trailingZeroBitCount
    let maximum = mask >> shift
    let component = (value & mask) >> shift
    return UInt8((UInt64(component) * 255 + UInt64(maximum / 2)) / UInt64(maximum))
}

private func palettePixel(
    _ palette: [(UInt8, UInt8, UInt8)],
    index: Int,
    alpha: UInt8
) throws -> (UInt8, UInt8, UInt8, UInt8) {
    guard palette.indices.contains(index) else {
        throw MomijiError.invalidFormat("DIB palette index is out of range")
    }
    let color = palette[index]
    return (color.0, color.1, color.2, alpha)
}
