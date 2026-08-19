import Foundation
import Testing
@testable import MomijiCore

@Suite("Windows cursor parsers")
struct ParserTests {
    @Test("32-bit DIB CUR preserves geometry and hotspot")
    func parsesCUR() throws {
        let parsed = try CURParser().parse(data: makeCUR(red: 255, green: 0, blue: 0))
        #expect(parsed.representations.count == 1)
        #expect(parsed.representations[0].width == 1)
        #expect(parsed.representations[0].height == 1)
        #expect(parsed.representations[0].hotspotX == 0)
        #expect(!parsed.representations[0].pngData.isEmpty)
    }

    @Test("DIB CUR supports indexed and true-color bit depths", arguments: [1, 4, 8, 24, 32])
    func parsesSupportedDIBDepths(_ bitDepth: Int) throws {
        let parsed = try CURParser().parse(data: makeDIBCUR(bitDepth: bitDepth))
        #expect(parsed.representations.count == 1)
        #expect(parsed.representations[0].width == 1)
        #expect(parsed.representations[0].height == 1)
        #expect(try PNGCodec.decode(parsed.representations[0].pngData).width == 1)
    }

    @Test("32-bit BITFIELDS DIB masks are decoded")
    func parsesBitfieldDIB() throws {
        let parsed = try CURParser().parse(data: makeBitfieldCUR())
        #expect(parsed.representations.count == 1)
        #expect(try PNGCodec.decode(parsed.representations[0].pngData).height == 1)
    }

    @Test("PNG CUR and multiple resolutions are preserved")
    func parsesPNGAndMultipleResolutions() throws {
        let one = try makePNG(width: 1, height: 1, red: 255)
        let two = try makePNG(width: 2, height: 2, red: 64)
        let parsed = try CURParser().parse(data: makeCursor(entries: [
            (width: 1, height: 1, hotspotX: 0, hotspotY: 0, payload: one),
            (width: 2, height: 2, hotspotX: 1, hotspotY: 1, payload: two),
        ]))
        #expect(parsed.representations.map(\.width) == [1, 2])
        #expect(parsed.representations.map(\.hotspotX) == [0, 1])
    }

    @Test("ANI seq and rate chunks are preserved")
    func parsesANISequenceAndRate() throws {
        let parsed = try ANIParser().parse(data: makeANI())
        #expect(parsed.representations.first?.frames.count == 2)
        #expect(parsed.timeline.steps == [
            AnimationStep(frameIndex: 1, durationTicks: 6),
            AnimationStep(frameIndex: 0, durationTicks: 12),
        ])
        #expect(parsed.timeline.totalDuration == 0.3)
    }

    @Test("ANI uses sequential frames and the anih default rate when chunks are absent")
    func parsesANIDefaultSequenceAndRate() throws {
        let parsed = try ANIParser().parse(data: makeANI(
            frames: [makeCUR(red: 1, green: 2, blue: 3), makeCUR(red: 4, green: 5, blue: 6)],
            rates: nil,
            sequence: nil,
            defaultRate: 9
        ))
        #expect(parsed.timeline.steps == [
            AnimationStep(frameIndex: 0, durationTicks: 9),
            AnimationStep(frameIndex: 1, durationTicks: 9),
        ])
    }

    @Test("RIFF chunks with odd payload lengths honor WORD padding")
    func parsesOddChunkPadding() throws {
        let parsed = try ANIParser().parse(data: makeANI(addOddJunk: true))
        #expect(parsed.timeline.steps.count == 2)
    }

    @Test("Different frame hotspots are aligned on an expanded common canvas")
    func alignsFrameHotspots() throws {
        let png = try makePNG(width: 2, height: 2, red: 220)
        let first = makeCursor(entries: [(2, 2, 0, 0, png)])
        let second = makeCursor(entries: [(2, 2, 1, 0, png)])
        let parsed = try ANIParser().parse(data: makeANI(
            frames: [first, second],
            declaredWidth: 2,
            declaredHeight: 2
        ))
        #expect(parsed.logicalSize == CursorSize(width: 3, height: 2))
        #expect(parsed.hotspot == CursorPoint(x: 1, y: 0))
        #expect(parsed.warnings.contains(.hotspotNormalized(file: "cursor.ani")))
        let image = try PNGCodec.decode(parsed.representations[0].frames[0].pngData)
        #expect(image.width == 3)
        #expect(image.height == 2)
    }

    @Test("Truncated CUR input is rejected")
    func rejectsTruncatedCUR() {
        #expect(throws: (any Error).self) {
            try CURParser().parse(data: Data([0, 0, 2, 0, 1, 0]))
        }
    }

    @Test("Missing ANI headers and overflowing CUR offsets are rejected")
    func rejectsMalformedContainers() {
        #expect(throws: (any Error).self) {
            try ANIParser().parse(data: makeANI(includeHeader: false))
        }
        var cursor = makeCUR(red: 1, green: 1, blue: 1)
        cursor.replaceSubrange(18..<22, with: [0xFF, 0xFF, 0xFF, 0xFF])
        #expect(throws: (any Error).self) {
            try CURParser().parse(data: cursor)
        }
    }

    @Test("Variable durations expand exactly when under the limit")
    func expandsTimeline() {
        let timeline = AnimationTimeline(steps: [
            .init(frameIndex: 0, durationTicks: 2),
            .init(frameIndex: 1, durationTicks: 4),
        ])
        let expanded = timeline.uniformlyExpanded(maxFrames: 24)
        #expect(expanded.frameIndices == [0, 1, 1])
        #expect(expanded.frameDuration == 2.0 / 60.0)
        #expect(!expanded.wasQuantized)
    }

    @Test("Huge relatively-prime ANI ticks quantize without an incremental loop")
    func quantizesHugeTicks() {
        let timeline = AnimationTimeline(steps: [
            .init(frameIndex: 0, durationTicks: 4_294_967_291),
            .init(frameIndex: 1, durationTicks: 4_294_967_279),
        ])
        let expanded = timeline.uniformlyExpanded(maxFrames: 240)
        #expect(expanded.frameIndices.count <= 240)
        #expect(expanded.wasQuantized)
        #expect(expanded.frameDuration > 0)
    }
}

func makeCUR(red: UInt8, green: UInt8, blue: UInt8) -> Data {
    makeDIBCUR(bitDepth: 32, red: red, green: green, blue: blue)
}

func makeDIBCUR(
    bitDepth: Int,
    red: UInt8 = 255,
    green: UInt8 = 0,
    blue: UInt8 = 0
) -> Data {
    var dib = Data()
    dib.appendLE(UInt32(40))
    dib.appendLE(Int32(1))
    dib.appendLE(Int32(2))
    dib.appendLE(UInt16(1))
    dib.appendLE(UInt16(bitDepth))
    dib.appendLE(UInt32(0))
    dib.appendLE(UInt32(4))
    dib.appendLE(Int32(0))
    dib.appendLE(Int32(0))
    dib.appendLE(UInt32(bitDepth <= 8 ? 2 : 0))
    dib.appendLE(UInt32(0))
    if bitDepth <= 8 {
        dib.append(contentsOf: [0, 0, 0, 0])
        dib.append(contentsOf: [blue, green, red, 0])
    }
    switch bitDepth {
    case 1: dib.append(contentsOf: [0x80, 0, 0, 0])
    case 4: dib.append(contentsOf: [0x10, 0, 0, 0])
    case 8: dib.append(contentsOf: [0x01, 0, 0, 0])
    case 24: dib.append(contentsOf: [blue, green, red, 0])
    case 32: dib.append(contentsOf: [blue, green, red, 255])
    default: preconditionFailure("unsupported test bit depth")
    }
    dib.append(contentsOf: [0, 0, 0, 0])
    return makeCursor(entries: [(1, 1, 0, 0, dib)])
}

func makeBitfieldCUR() -> Data {
    var dib = Data()
    dib.appendLE(UInt32(40))
    dib.appendLE(Int32(1))
    dib.appendLE(Int32(2))
    dib.appendLE(UInt16(1))
    dib.appendLE(UInt16(32))
    dib.appendLE(UInt32(3))
    dib.appendLE(UInt32(4))
    dib.appendLE(Int32(0))
    dib.appendLE(Int32(0))
    dib.appendLE(UInt32(0))
    dib.appendLE(UInt32(0))
    dib.appendLE(UInt32(0x00FF_0000))
    dib.appendLE(UInt32(0x0000_FF00))
    dib.appendLE(UInt32(0x0000_00FF))
    dib.appendLE(UInt32(0x00FF_0000))
    dib.append(contentsOf: [0, 0, 0, 0])
    return makeCursor(entries: [(1, 1, 0, 0, dib)])
}

func makeANI(
    frames: [Data] = [
        makeCUR(red: 255, green: 0, blue: 0),
        makeCUR(red: 0, green: 255, blue: 0),
    ],
    rates: [UInt32]? = [6, 12],
    sequence: [UInt32]? = [1, 0],
    defaultRate: UInt32 = 6,
    declaredWidth: UInt32 = 1,
    declaredHeight: UInt32 = 1,
    addOddJunk: Bool = false,
    includeHeader: Bool = true
) -> Data {
    var header = Data()
    header.appendLE(UInt32(36))
    header.appendLE(UInt32(frames.count))
    header.appendLE(UInt32(sequence?.count ?? frames.count))
    header.appendLE(declaredWidth)
    header.appendLE(declaredHeight)
    header.appendLE(UInt32(32))
    header.appendLE(UInt32(1))
    header.appendLE(defaultRate)
    header.appendLE(UInt32(1))

    var frameList = Data("fram".utf8)
    for frame in frames { frameList.append(chunk("icon", frame)) }

    var body = Data("ACON".utf8)
    if addOddJunk { body.append(chunk("JUNK", Data([0x7F]))) }
    if includeHeader { body.append(chunk("anih", header)) }
    if let rates {
        var payload = Data()
        for rate in rates { payload.appendLE(rate) }
        body.append(chunk("rate", payload))
    }
    if let sequence {
        var payload = Data()
        for index in sequence { payload.appendLE(index) }
        body.append(chunk("seq ", payload))
    }
    body.append(chunk("LIST", frameList))

    var file = Data("RIFF".utf8)
    file.appendLE(UInt32(body.count))
    file.append(body)
    return file
}

func makeCursor(entries: [(width: Int, height: Int, hotspotX: Int, hotspotY: Int, payload: Data)]) -> Data {
    var cursor = Data()
    cursor.appendLE(UInt16(0))
    cursor.appendLE(UInt16(2))
    cursor.appendLE(UInt16(entries.count))
    var offset = 6 + entries.count * 16
    for entry in entries {
        cursor.append(UInt8(entry.width == 256 ? 0 : entry.width))
        cursor.append(UInt8(entry.height == 256 ? 0 : entry.height))
        cursor.append(contentsOf: [0, 0])
        cursor.appendLE(UInt16(entry.hotspotX))
        cursor.appendLE(UInt16(entry.hotspotY))
        cursor.appendLE(UInt32(entry.payload.count))
        cursor.appendLE(UInt32(offset))
        offset += entry.payload.count
    }
    for entry in entries { cursor.append(entry.payload) }
    return cursor
}

func makePNG(width: Int, height: Int, red: UInt8) throws -> Data {
    var pixels = Data()
    for _ in 0..<(width * height) { pixels.append(contentsOf: [red, 80, 40, 255]) }
    return try PNGCodec.encode(PNGCodec.makeRGBAImage(width: width, height: height, pixels: pixels))
}

private func chunk(_ name: String, _ payload: Data) -> Data {
    var output = Data(name.utf8)
    output.appendLE(UInt32(payload.count))
    output.append(payload)
    if !payload.count.isMultiple(of: 2) { output.append(0) }
    return output
}

extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
