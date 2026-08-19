import Foundation

public struct ParsedWindowsCursor: Equatable, Sendable {
    public var logicalSize: CursorSize
    public var hotspot: CursorPoint
    public var representations: [CursorRepresentation]
    public var timeline: AnimationTimeline
    public var warnings: [ImportWarning]

    public func asset(role: CursorRole = .arrow) -> CursorAsset {
        CursorAsset(
            role: role,
            logicalSize: logicalSize,
            hotspot: hotspot,
            representations: representations,
            timeline: timeline
        )
    }
}

public struct ANIParser: Sendable {
    public static let maximumFileSize = 64 * 1_024 * 1_024
    public static let maximumFrames = 256

    private let curParser = CURParser()

    public init() {}

    public func parse(data: Data, sourceName: String = "cursor.ani") throws -> ParsedWindowsCursor {
        guard data.count <= Self.maximumFileSize else {
            throw MomijiError.resourceLimit("ANI file exceeds 64 MiB")
        }
        let reader = BinaryReader(data: data)
        guard try reader.fourCC(at: 0) == "RIFF", try reader.fourCC(at: 8) == "ACON" else {
            throw MomijiError.invalidFormat("ANI must be a RIFF ACON container")
        }
        let riffSize = Int(try reader.uint32LE(at: 4))
        guard riffSize >= 4, riffSize <= data.count - 8 else {
            throw MomijiError.truncatedData
        }
        let end = 8 + riffSize
        var offset = 12
        var header: ANIHeader?
        var rates: [Int] = []
        var sequence: [Int] = []
        var frames: [ParsedCUR] = []

        while offset + 8 <= end {
            let id = try reader.fourCC(at: offset)
            let length = Int(try reader.uint32LE(at: offset + 4))
            let payloadStart = offset + 8
            guard length >= 0, payloadStart <= end, length <= end - payloadStart else {
                throw MomijiError.truncatedData
            }
            let payloadEnd = payloadStart + length
            switch id {
            case "anih":
                header = try parseHeader(reader, range: payloadStart..<payloadEnd)
            case "rate":
                rates = try parseUInt32Array(reader, range: payloadStart..<payloadEnd)
            case "seq ":
                sequence = try parseUInt32Array(reader, range: payloadStart..<payloadEnd)
            case "LIST":
                if length >= 4, try reader.fourCC(at: payloadStart) == "fram" {
                    frames.append(contentsOf: try parseFrameList(reader, range: (payloadStart + 4)..<payloadEnd))
                }
            default:
                break
            }
            offset = payloadEnd + (length & 1)
        }

        guard let header else { throw MomijiError.invalidFormat("ANI is missing anih") }
        guard !frames.isEmpty else { throw MomijiError.invalidFormat("ANI contains no icon frames") }
        guard frames.count <= Self.maximumFrames else {
            throw MomijiError.resourceLimit("ANI contains more than \(Self.maximumFrames) frames")
        }
        if header.frameCount > 0, header.frameCount != frames.count {
            throw MomijiError.invalidFormat("ANI frame count does not match fram data")
        }

        let stepCount = header.stepCount > 0 ? header.stepCount : frames.count
        guard stepCount <= Self.maximumFrames else {
            throw MomijiError.resourceLimit("ANI contains too many animation steps")
        }
        let resolvedSequence = sequence.isEmpty ? Array(0..<stepCount).map { $0 % frames.count } : sequence
        guard resolvedSequence.count >= stepCount else {
            throw MomijiError.invalidFormat("ANI seq chunk is shorter than cSteps")
        }
        guard resolvedSequence.prefix(stepCount).allSatisfy({ frames.indices.contains($0) }) else {
            throw MomijiError.invalidFormat("ANI seq references a missing frame")
        }
        let defaultRate = max(1, header.defaultRate)
        let steps = (0..<stepCount).map { index in
            AnimationStep(
                frameIndex: resolvedSequence[index],
                durationTicks: index < rates.count ? max(1, rates[index]) : defaultRate
            )
        }

        return try buildParsedCursor(
            frames: frames,
            declaredWidth: header.width,
            declaredHeight: header.height,
            timeline: AnimationTimeline(steps: steps),
            sourceName: sourceName
        )
    }

    public func parseCUR(data: Data, sourceName: String = "cursor.cur") throws -> ParsedWindowsCursor {
        try buildParsedCursor(
            frames: [curParser.parse(data: data)],
            declaredWidth: 0,
            declaredHeight: 0,
            timeline: .still,
            sourceName: sourceName
        )
    }

    private func parseHeader(_ reader: BinaryReader, range: Range<Int>) throws -> ANIHeader {
        guard range.count >= 36 else { throw MomijiError.truncatedData }
        let start = range.lowerBound
        return ANIHeader(
            frameCount: Int(try reader.uint32LE(at: start + 4)),
            stepCount: Int(try reader.uint32LE(at: start + 8)),
            width: Int(try reader.uint32LE(at: start + 12)),
            height: Int(try reader.uint32LE(at: start + 16)),
            defaultRate: Int(try reader.uint32LE(at: start + 28))
        )
    }

    private func parseUInt32Array(_ reader: BinaryReader, range: Range<Int>) throws -> [Int] {
        guard range.count.isMultiple(of: 4) else {
            throw MomijiError.invalidFormat("ANI integer array is not DWORD aligned")
        }
        guard range.count / 4 <= Self.maximumFrames else {
            throw MomijiError.resourceLimit("ANI integer array contains too many entries")
        }
        return try stride(from: range.lowerBound, to: range.upperBound, by: 4).map {
            Int(try reader.uint32LE(at: $0))
        }
    }

    private func parseFrameList(_ reader: BinaryReader, range: Range<Int>) throws -> [ParsedCUR] {
        var frames: [ParsedCUR] = []
        var offset = range.lowerBound
        while offset + 8 <= range.upperBound {
            let id = try reader.fourCC(at: offset)
            let length = Int(try reader.uint32LE(at: offset + 4))
            let start = offset + 8
            guard length >= 0, start <= range.upperBound, length <= range.upperBound - start else {
                throw MomijiError.truncatedData
            }
            if id == "icon" {
                frames.append(try curParser.parse(data: reader.slice(start..<(start + length))))
                guard frames.count <= Self.maximumFrames else {
                    throw MomijiError.resourceLimit("ANI contains too many icon frames")
                }
            }
            offset = start + length + (length & 1)
        }
        return frames
    }

    private func buildParsedCursor(
        frames: [ParsedCUR],
        declaredWidth: Int,
        declaredHeight: Int,
        timeline: AnimationTimeline,
        sourceName: String
    ) throws -> ParsedWindowsCursor {
        guard let first = frames.first?.representations.first else {
            throw MomijiError.invalidFormat("cursor frame has no representations")
        }
        let baseWidth = declaredWidth > 0 ? declaredWidth : first.width
        let baseHeight = declaredHeight > 0 ? declaredHeight : first.height
        guard baseWidth > 0, baseHeight > 0, baseWidth <= 1024, baseHeight <= 1024 else {
            throw MomijiError.resourceLimit("logical cursor dimensions are invalid")
        }

        let baseSelections = try selectRepresentations(
            frames: frames,
            targetWidth: baseWidth,
            targetHeight: baseHeight
        )
        let baseSourceHotspots = baseSelections.map {
            CursorPoint(
                x: Double($0.hotspotX) * Double(baseWidth) / Double($0.width),
                y: Double($0.hotspotY) * Double(baseHeight) / Double($0.height)
            )
        }
        let leftExtent = baseSourceHotspots.map(\.x).max() ?? 0
        let topExtent = baseSourceHotspots.map(\.y).max() ?? 0
        let rightExtent = baseSourceHotspots.map {
            Double(baseWidth) - $0.x
        }.max() ?? Double(baseWidth)
        let bottomExtent = baseSourceHotspots.map {
            Double(baseHeight) - $0.y
        }.max() ?? Double(baseHeight)
        let canvasWidth = Int(ceil(leftExtent + rightExtent))
        let canvasHeight = Int(ceil(topExtent + bottomExtent))
        guard canvasWidth > 0, canvasHeight > 0, canvasWidth <= 1024, canvasHeight <= 1024 else {
            throw MomijiError.resourceLimit("aligned cursor canvas dimensions are invalid")
        }
        let decodedPixels = frames.count * canvasWidth * canvasHeight * 5
        guard decodedPixels <= 64 * 1_024 * 1_024 else {
            throw MomijiError.resourceLimit("ANI decoded frame canvases exceed 64 megapixels")
        }

        var output: [CursorRepresentation] = []
        for scale in [1, 2] {
            let imageWidth = baseWidth * scale
            let imageHeight = baseHeight * scale
            let targetCanvasWidth = canvasWidth * scale
            let targetCanvasHeight = canvasHeight * scale
            let selected = try selectRepresentations(
                frames: frames,
                targetWidth: imageWidth,
                targetHeight: imageHeight
            )
            let targetHotspot = CursorPoint(
                x: leftExtent * Double(scale),
                y: topExtent * Double(scale)
            )
            let normalizedFrames = try selected.map { representation -> CursorFrame in
                let sourceHotspot = CursorPoint(
                    x: Double(representation.hotspotX) * Double(imageWidth) / Double(representation.width),
                    y: Double(representation.hotspotY) * Double(imageHeight) / Double(representation.height)
                )
                return CursorFrame(pngData: try PNGCodec.normalized(
                    representation.pngData,
                    canvasWidth: targetCanvasWidth,
                    canvasHeight: targetCanvasHeight,
                    imageWidth: imageWidth,
                    imageHeight: imageHeight,
                    sourceHotspot: sourceHotspot,
                    targetHotspot: targetHotspot
                ))
            }
            output.append(CursorRepresentation(
                scale: scale,
                frames: normalizedFrames
            ))
        }

        let hotspot = CursorPoint(x: leftExtent, y: topExtent)
        let firstHotspot = baseSourceHotspots[0]
        let hotspotVaries = baseSourceHotspots.dropFirst().contains { frameHotspot in
            abs(frameHotspot.x - firstHotspot.x) > 0.5
                || abs(frameHotspot.y - firstHotspot.y) > 0.5
        }
        let warnings: [ImportWarning] = hotspotVaries ? [.hotspotNormalized(file: sourceName)] : []
        return ParsedWindowsCursor(
            logicalSize: CursorSize(width: Double(canvasWidth), height: Double(canvasHeight)),
            hotspot: hotspot,
            representations: output,
            timeline: timeline,
            warnings: warnings
        )
    }

    private func selectRepresentations(
        frames: [ParsedCUR],
        targetWidth: Int,
        targetHeight: Int
    ) throws -> [ParsedCursorRepresentation] {
        try frames.map { frame in
            guard let representation = frame.representations.min(by: {
                distance($0, targetWidth, targetHeight) < distance($1, targetWidth, targetHeight)
            }) else {
                throw MomijiError.invalidFormat("ANI frame is missing image data")
            }
            return representation
        }
    }
}

private struct ANIHeader {
    var frameCount: Int
    var stepCount: Int
    var width: Int
    var height: Int
    var defaultRate: Int
}

private func distance(_ representation: ParsedCursorRepresentation, _ width: Int, _ height: Int) -> Int {
    abs(representation.width - width) + abs(representation.height - height)
}
