import Foundation
import JianliCore

// MARK: - 帧协议：4 字节大端长度 + JSON

enum Wire {
    static func encode(_ payload: Data) -> Data {
        var out = Data()
        let length = UInt32(payload.count).bigEndian
        out.append(contentsOf: withUnsafeBytes(of: length) { Array($0) })
        out.append(payload)
        return out
    }

    static func popFrame(from buffer: inout [UInt8]) -> Data? {
        guard buffer.count >= 4 else { return nil }
        let length = Int(buffer[0]) << 24 | Int(buffer[1]) << 16 | Int(buffer[2]) << 8 | Int(buffer[3])
        guard length > 0, length < 2_000_000, buffer.count >= 4 + length else { return nil }
        let payload = Data(buffer[4..<(4 + length)])
        buffer.removeFirst(4 + length)
        return payload
    }

    static func encodeJSON<T: Encodable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(value)
    }

    static func decodeJSON<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? JSONDecoder().decode(type, from: data)
    }
}

// MARK: - 房间与座位

struct SlotInfo: Codable, Identifiable, Hashable {
    var seat: Seat
    var name: String
    var connected: Bool
    var isBot: Bool
    var isMine: Bool

    var id: Int { seat.rawValue }
}

struct RoomInfo: Codable, Hashable {
    var code: String
    var hostName: String
    var ruleName: String
    var started: Bool
}

struct DiscoveredRoom: Identifiable, Hashable {
    let id: String
    let name: String
    let host: String
}

// MARK: - 消息

enum ClientMessage: Codable {
    case hello(name: String, token: String)
    case action(Action)
    case startWithBots
    case nextHand
    case leave
    case ping
}

enum HostMessage: Codable {
    case joined(seat: Seat, room: RoomInfo, slots: [SlotInfo])
    case rejected(String)
    case room(RoomInfo, [SlotInfo])
    case snapshot(TableSnapshot)
    case toast(String)
    case pong
}
