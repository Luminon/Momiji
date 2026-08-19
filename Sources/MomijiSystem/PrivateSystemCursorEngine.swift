import AppKit
import CoreGraphics
import Foundation
import MomijiCore
import MomijiSystemBridge

public final class PrivateSystemCursorEngine: SystemCursorApplying, @unchecked Sendable {
    public static let maximumRuntimeFrames = 240

    public init() {}

    public var availability: SystemCursorAvailability {
        MJCursorBridgeIsAvailable()
            ? .available
            : .unavailable(reason: MJCursorBridgeUnavailableReason())
    }

    public func apply(_ theme: CursorTheme) throws {
        guard case .available = availability else {
            if case .unavailable(let reason) = availability {
                throw MomijiError.systemCursorUnavailable(reason)
            }
            throw MomijiError.systemCursorUnavailable("unknown runtime failure")
        }
        let prepared = try theme.cursors.map(prepare)
        var bridgeError: NSError?
        guard MJCursorBridgeBeginTheme(&bridgeError) else {
            throw MomijiError.systemCursorFailure(bridgeError?.localizedDescription ?? "could not reset cursors")
        }

        do {
            for cursor in prepared {
                let identifiers = identifiers(for: cursor.role)
                for (index, identifier) in identifiers.enumerated() {
                    bridgeError = nil
                    let success = MJCursorBridgeRegister(
                        identifier,
                        cursor.spriteSheets,
                        cursor.size,
                        cursor.hotspot,
                        UInt(cursor.frameCount),
                        cursor.frameDuration,
                        &bridgeError
                    )
                    guard success || index > 0 else {
                        throw MomijiError.systemCursorFailure(
                            bridgeError?.localizedDescription ?? "could not register \(identifier)"
                        )
                    }
                }
            }
            MJCursorBridgeFinishTheme()
        } catch {
            _ = MJCursorBridgeRestoreDefaults(nil)
            throw error
        }
    }

    public func restoreDefaults() throws {
        var error: NSError?
        guard MJCursorBridgeRestoreDefaults(&error) else {
            throw MomijiError.systemCursorFailure(error?.localizedDescription ?? "could not restore defaults")
        }
    }

    private func prepare(_ asset: CursorAsset) throws -> PreparedCursor {
        guard asset.logicalSize.width > 0, asset.logicalSize.height > 0,
              asset.logicalSize.width <= 128, asset.logicalSize.height <= 128,
              asset.hotspot.x >= 0, asset.hotspot.y >= 0,
              asset.hotspot.x < asset.logicalSize.width,
              asset.hotspot.y < asset.logicalSize.height else {
            throw MomijiError.invalidFormat("\(asset.role.rawValue) has invalid runtime geometry")
        }
        let animation = asset.timeline.uniformlyExpanded(maxFrames: Self.maximumRuntimeFrames)
        guard !animation.frameIndices.isEmpty else {
            throw MomijiError.invalidFormat("\(asset.role.rawValue) has no animation frames")
        }
        let sheets: [CGImage] = try asset.representations.sorted(by: { $0.scale < $1.scale }).map { representation in
            let images = try animation.frameIndices.map { index -> CGImage in
                guard representation.frames.indices.contains(index) else {
                    throw MomijiError.invalidFormat("\(asset.role.rawValue) timeline references a missing frame")
                }
                return try decodeImage(representation.frames[index].pngData)
            }
            return try makeSpriteSheet(
                images: images,
                width: max(1, Int((asset.logicalSize.width * Double(representation.scale)).rounded())),
                height: max(1, Int((asset.logicalSize.height * Double(representation.scale)).rounded()))
            )
        }
        guard !sheets.isEmpty else { throw MomijiError.noUsableCursors }
        return PreparedCursor(
            role: asset.role,
            spriteSheets: sheets,
            size: CGSize(width: asset.logicalSize.width, height: asset.logicalSize.height),
            hotspot: CGPoint(x: asset.hotspot.x, y: asset.hotspot.y),
            frameCount: animation.frameIndices.count,
            frameDuration: animation.frameDuration / max(0.25, min(4, asset.playbackRate))
        )
    }

    private func identifiers(for role: CursorRole) -> [String] {
        var identifiers: [String]
        switch role {
        case .arrow: identifiers = ["com.apple.coregraphics.Arrow", "com.apple.cursor.0"]
        case .iBeam: identifiers = ["com.apple.coregraphics.IBeam", "com.apple.cursor.1"]
        case .pointingHand: identifiers = ["com.apple.cursor.13", "com.apple.coregraphics.PointingHand"]
        case .wait: identifiers = ["com.apple.coregraphics.Wait"]
        case .progress: identifiers = ["com.apple.cursor.4"]
        case .crosshair: identifiers = ["com.apple.cursor.7"]
        case .operationNotAllowed: identifiers = ["com.apple.cursor.3", "com.apple.coregraphics.NotAllowed"]
        case .resizeNorthSouth: identifiers = ["com.apple.cursor.23", "com.apple.coregraphics.ResizeUpDown"]
        case .resizeEastWest: identifiers = ["com.apple.cursor.19", "com.apple.coregraphics.ResizeLeftRight"]
        case .resizeNorthwestSoutheast: identifiers = ["com.apple.cursor.34", "com.apple.coregraphics.WindowResizeNorthwestSoutheast"]
        case .resizeNortheastSouthwest: identifiers = ["com.apple.cursor.30", "com.apple.coregraphics.WindowResizeNortheastSouthwest"]
        case .move: identifiers = ["com.apple.coregraphics.Move", "com.apple.cursor.39"]
        case .help: identifiers = ["com.apple.cursor.40", "com.apple.coregraphics.Help"]
        case .openHand: identifiers = ["com.apple.cursor.12", "com.apple.coregraphics.OpenHand"]
        case .closedHand: identifiers = ["com.apple.cursor.11", "com.apple.coregraphics.ClosedHand"]
        }
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 {
            if role == .arrow { identifiers.append("com.apple.coregraphics.ArrowS") }
            if role == .iBeam { identifiers.append("com.apple.coregraphics.IBeamS") }
        }
        return identifiers
    }
}

private struct PreparedCursor {
    var role: CursorRole
    var spriteSheets: [CGImage]
    var size: CGSize
    var hotspot: CGPoint
    var frameCount: Int
    var frameDuration: TimeInterval
}

private func decodeImage(_ data: Data) throws -> CGImage {
    guard let image = NSBitmapImageRep(data: data)?.cgImage else {
        throw MomijiError.invalidFormat("could not decode PNG frame")
    }
    return image
}

private func makeSpriteSheet(images: [CGImage], width: Int, height: Int) throws -> CGImage {
    guard !images.isEmpty, width > 0, height > 0,
          height <= Int.max / images.count,
          height * images.count <= 32_768 else {
        throw MomijiError.resourceLimit("animated cursor sprite sheet is too large")
    }
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height * images.count,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw MomijiError.invalidFormat("could not create sprite sheet")
    }
    context.clear(CGRect(x: 0, y: 0, width: width, height: height * images.count))
    context.interpolationQuality = .high
    for (index, image) in images.enumerated() {
        let y = (images.count - index - 1) * height
        context.draw(image, in: CGRect(x: 0, y: y, width: width, height: height))
    }
    guard let output = context.makeImage() else {
        throw MomijiError.invalidFormat("could not finalize sprite sheet")
    }
    return output
}
