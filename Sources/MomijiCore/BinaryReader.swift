import Foundation

struct BinaryReader: Sendable {
    let data: Data

    var count: Int { data.count }

    func require(_ range: Range<Int>) throws {
        guard range.lowerBound >= 0, range.upperBound >= range.lowerBound, range.upperBound <= data.count else {
            throw MomijiError.truncatedData
        }
    }

    func byte(at offset: Int) throws -> UInt8 {
        try require(offset..<(offset + 1))
        return data[data.startIndex + offset]
    }

    func uint16LE(at offset: Int) throws -> UInt16 {
        try require(offset..<(offset + 2))
        return UInt16(try byte(at: offset)) | (UInt16(try byte(at: offset + 1)) << 8)
    }

    func uint32LE(at offset: Int) throws -> UInt32 {
        try require(offset..<(offset + 4))
        return UInt32(try byte(at: offset))
            | (UInt32(try byte(at: offset + 1)) << 8)
            | (UInt32(try byte(at: offset + 2)) << 16)
            | (UInt32(try byte(at: offset + 3)) << 24)
    }

    func int32LE(at offset: Int) throws -> Int32 {
        Int32(bitPattern: try uint32LE(at: offset))
    }

    func fourCC(at offset: Int) throws -> String {
        try require(offset..<(offset + 4))
        let bytes = (0..<4).map { try? byte(at: offset + $0) }
        guard bytes.allSatisfy({ $0 != nil }) else { throw MomijiError.truncatedData }
        return String(bytes: bytes.compactMap { $0 }, encoding: .ascii) ?? ""
    }

    func slice(_ range: Range<Int>) throws -> Data {
        try require(range)
        let lower = data.startIndex + range.lowerBound
        let upper = data.startIndex + range.upperBound
        return data.subdata(in: lower..<upper)
    }
}
