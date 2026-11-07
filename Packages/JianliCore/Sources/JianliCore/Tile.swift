import Foundation

// MARK: - 牌

public enum TileSuit: Int, Codable, CaseIterable, Sendable {
    case wan = 0      // 萬
    case tong = 1     // 筒
    case tiao = 2     // 條
    case red = 3      // 红中（皮子）

    public var symbol: String {
        switch self {
        case .wan: return "萬"
        case .tong: return "筒"
        case .tiao: return "條"
        case .red: return "中"
        }
    }

    /// 牌面主色，用十六进制字符串表达，避免 Core 依赖 UIKit
    public var hexColor: String {
        switch self {
        case .wan: return "21352B"
        case .tong: return "1C4B72"
        case .tiao: return "17683C"
        case .red: return "B02A20"
        }
    }
}

/// 一张牌。raw: 0-8 萬1-9，9-17 筒1-9，18-26 條1-9，27 红中。
public struct Tile: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public static let redRaw = 27

    public let raw: Int

    public init(raw: Int) {
        precondition(raw >= 0 && raw <= Tile.redRaw, "非法牌编码 \(raw)")
        self.raw = raw
    }

    public init(_ suit: TileSuit, _ rank: Int) {
        if suit == .red {
            self.init(raw: Tile.redRaw)
            return
        }
        precondition((1...9).contains(rank), "非法牌点 \(rank)")
        self.init(raw: suit.rawValue * 9 + rank - 1)
    }

    public var suit: TileSuit { raw == Tile.redRaw ? .red : TileSuit(rawValue: raw / 9) ?? .wan }
    public var rank: Int { raw == Tile.redRaw ? 0 : raw % 9 + 1 }
    public var isRed: Bool { raw == Tile.redRaw }

    public var numeral: String {
        guard !isRed else { return "中" }
        return ["一", "二", "三", "四", "五", "六", "七", "八", "九"][rank - 1]
    }

    public var symbol: String { suit.symbol }
    public var label: String { isRed ? "红中" : "\(numeral)\(suit.symbol)" }
    public var description: String { label }

    public static func < (lhs: Tile, rhs: Tile) -> Bool { lhs.raw < rhs.raw }

    public static let allKinds: [Tile] = (0...Tile.redRaw).map { Tile(raw: $0) }

    /// 112 张：萬筒條 1-9 各 4 张 + 红中 4 张
    public static let fullSet: [Tile] = allKinds.flatMap { kind in (0..<4).map { _ in kind } }
}

// MARK: - 座位

public enum Seat: Int, Codable, CaseIterable, Sendable, Hashable {
    case east = 0
    case south = 1
    case west = 2
    case north = 3

    public var label: String { ["东", "南", "西", "北"][rawValue] }
    public var next: Seat { Seat(rawValue: (rawValue + 1) % 4)! }
    public var others: [Seat] { Seat.allCases.filter { $0 != self } }

    /// 从 self 出发，到 other 的顺时针步数（1...3）
    public func distance(to other: Seat) -> Int { (other.rawValue - rawValue + 4) % 4 }
}

// MARK: - 确定性随机

/// xoshiro256** + splitmix64 播种。只用于发牌，局中不再取随机数。
public struct DeterministicRNG: Sendable {
    private var s0: UInt64
    private var s1: UInt64
    private var s2: UInt64
    private var s3: UInt64

    public init(seed: UInt64) {
        var x = seed
        func splitmix() -> UInt64 {
            x &+= 0x9E37_79B9_7F4A_7C15
            var z = x
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        s0 = splitmix()
        s1 = splitmix()
        s2 = splitmix()
        s3 = splitmix()
    }

    private static func rotl(_ x: UInt64, _ k: UInt64) -> UInt64 {
        (x << k) | (x >> (64 - k))
    }

    public mutating func next() -> UInt64 {
        let result = DeterministicRNG.rotl(s1 &* 5, 7) &* 9
        let t = s1 << 17
        s2 ^= s0
        s3 ^= s1
        s1 ^= s2
        s0 ^= s3
        s2 ^= t
        s3 = DeterministicRNG.rotl(s3, 45)
        return result
    }

    public mutating func integer(upperBound: Int) -> Int {
        guard upperBound > 0 else { return 0 }
        return Int(next() % UInt64(upperBound))
    }

    public mutating func shuffle<T>(_ array: [T]) -> [T] {
        var a = array
        guard a.count > 1 else { return a }
        for i in stride(from: a.count - 1, through: 1, by: -1) {
            let j = integer(upperBound: i + 1)
            a.swapAt(i, j)
        }
        return a
    }
}

// MARK: - 牌墙

public struct Wall: Codable, Sendable {
    public var tiles: [Tile]
    /// 牌墙头（正常摸牌）
    public var head: Int
    /// 牌墙尾（杠、皮子补摸）
    public var tail: Int

    public init(seed: UInt64) {
        var rng = DeterministicRNG(seed: seed)
        self.tiles = rng.shuffle(Tile.fullSet)
        self.head = 0
        self.tail = tiles.count - 1
    }

    /// 直接给定牌序（回放、单测构造牌局用）
    public init(tiles: [Tile], head: Int, tail: Int) {
        self.tiles = tiles
        self.head = head
        self.tail = tail
    }

    public var remaining: Int { max(0, tail - head + 1) }
    public var isEmpty: Bool { remaining <= 0 }

    public mutating func drawFront() -> Tile? {
        guard remaining > 0 else { return nil }
        let tile = tiles[head]
        head += 1
        return tile
    }

    public mutating func drawBack() -> Tile? {
        guard remaining > 0 else { return nil }
        let tile = tiles[tail]
        tail -= 1
        return tile
    }
}
