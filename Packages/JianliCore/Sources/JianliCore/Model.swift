import Foundation

// MARK: - 规则参数

public struct RuleProfile: Codable, Sendable, Hashable {
    public var name: String
    public var tileCount: Int
    /// 自摸
    public var selfDrawBase: Int
    /// 点杠（打出第四张，点杠者独付）
    public var pointGangBase: Int
    /// 暗杠（三家各付）
    public var concealedGangBase: Int
    /// 蓄杠 / 回头笑（碰后补杠，三家各付）
    public var addedGangBase: Int
    /// 四张红中全部打出，按暗杠计
    public var redGangBase: Int
    public var allowChi: Bool
    public var allowPointHu: Bool
    public var allowSevenPairs: Bool
    /// 红中是否是「皮子」，手上带红中不能胡
    public var redAsPizi: Bool
    public var playSeconds: Int
    public var claimSeconds: Int
    public var rounds: Int

    public init(name: String = "监利红中",
                tileCount: Int = 112,
                selfDrawBase: Int = 10,
                pointGangBase: Int = 10,
                concealedGangBase: Int = 15,
                addedGangBase: Int = 5,
                redGangBase: Int = 15,
                allowChi: Bool = false,
                allowPointHu: Bool = false,
                allowSevenPairs: Bool = true,
                redAsPizi: Bool = true,
                playSeconds: Int = 20,
                claimSeconds: Int = 8,
                rounds: Int = 8) {
        self.name = name
        self.tileCount = tileCount
        self.selfDrawBase = selfDrawBase
        self.pointGangBase = pointGangBase
        self.concealedGangBase = concealedGangBase
        self.addedGangBase = addedGangBase
        self.redGangBase = redGangBase
        self.allowChi = allowChi
        self.allowPointHu = allowPointHu
        self.allowSevenPairs = allowSevenPairs
        self.redAsPizi = redAsPizi
        self.playSeconds = playSeconds
        self.claimSeconds = claimSeconds
        self.rounds = rounds
    }

    public static let jianliRedDragon = RuleProfile()

    /// 规则指纹：握手时校验，两端不一致直接拒绝入座
    public var hash: String {
        let seed = "\(name)|\(tileCount)|\(selfDrawBase)|\(pointGangBase)|\(concealedGangBase)|\(addedGangBase)|\(redGangBase)|\(allowChi)|\(allowPointHu)|\(allowSevenPairs)|\(redAsPizi)"
        var h: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in seed.utf8 {
            h ^= UInt64(byte)
            h = h &* 0x0000_0100_0000_01B3
        }
        return String(h, radix: 16)
    }
}

// MARK: - 副露

public struct Meld: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case peng          // 碰
        case gangExposed   // 点杠（吃别人打出的第四张）
        case gangConcealed // 暗杠
        case gangAdded     // 蓄杠 / 回头笑
    }

    public var kind: Kind
    public var tile: Tile

    public init(kind: Kind, tile: Tile) {
        self.kind = kind
        self.tile = tile
    }

    public var isGang: Bool { kind != .peng }
    public var tileCount: Int { kind == .peng ? 3 : 4 }
}

// MARK: - 玩家

public struct PlayerState: Codable, Sendable, Identifiable {
    public var seat: Seat
    public var name: String
    public var hand: [Tile] = []
    public var melds: [Meld] = []
    public var river: [Tile] = []
    /// 本局已打出的红中张数（结算倍乘用）
    public var redsPlayed: Int = 0
    public var score: Int = 0
    public var isBot: Bool = false
    public var connected: Bool = true

    public var id: Int { seat.rawValue }

    public init(seat: Seat, name: String, isBot: Bool = false) {
        self.seat = seat
        self.name = name
        self.isBot = isBot
    }

    public var meldCount: Int { melds.count }
}

// MARK: - 阶段

public enum Phase: String, Codable, Sendable {
    case idle
    case awaitingDiscard
    case awaitingClaim
    case finished
}

public enum ClaimOption: String, Codable, Sendable, CaseIterable {
    case pass
    case peng
    case gang

    public var label: String {
        switch self {
        case .pass: return "过"
        case .peng: return "碰"
        case .gang: return "杠"
        }
    }
}

public struct PendingClaim: Codable, Sendable {
    public var discarder: Seat
    public var tile: Tile
    /// 座位 -> 可选声明
    public var options: [Int: [ClaimOption]]
    public var outstanding: [Int]
    public var answers: [Int: ClaimOption]

    public init(discarder: Seat, tile: Tile, options: [Int: [ClaimOption]], outstanding: [Int], answers: [Int: ClaimOption] = [:]) {
        self.discarder = discarder
        self.tile = tile
        self.options = options
        self.outstanding = outstanding
        self.answers = answers
    }
}

// MARK: - 动作

public enum Action: Codable, Sendable, Hashable {
    case discard(Tile)
    case peng
    case gangExposed
    case pass
    case gangConcealed(Tile)
    case gangAdded(Tile)
    case hu
}

public enum ScoreReason: String, Codable, Sendable {
    case selfDraw
    case pointGang
    case concealedGang
    case addedGang
    case redGang

    public var label: String {
        switch self {
        case .selfDraw: return "自摸"
        case .pointGang: return "点杠"
        case .concealedGang: return "暗杠"
        case .addedGang: return "蓄杠"
        case .redGang: return "红中暗杠"
        }
    }
}

// MARK: - 事件

public enum GameEvent: Codable, Sendable {
    case handStarted(dealer: Seat, seed: UInt64, roundIndex: Int)
    case turn(seat: Seat, drawn: Tile?)
    case discarded(seat: Seat, tile: Tile)
    case redDiscarded(seat: Seat, count: Int)
    case claimWindow(discarder: Seat, tile: Tile)
    case peng(seat: Seat, tile: Tile)
    case gang(seat: Seat, kind: Meld.Kind, tile: Tile, drawn: Tile?)
    case score(from: Seat, to: Seat, amount: Int, reason: ScoreReason)
    case hu(seat: Seat, payments: [Int: Int])
    case drawnGame
    case wallRemaining(Int)
}

// MARK: - 结算

public struct HandResult: Codable, Sendable {
    public var winner: Seat
    public var hand: [Tile]
    public var melds: [Meld]
    /// 座位 -> 该座位付给赢家的分数（赢家自己为 0）
    public var payments: [Int: Int]
    public var winnerReds: Int
    public var base: Int
    public var scores: [Int]
    public var roundIndex: Int
    public var seed: UInt64
}

// MARK: - 对局状态

public struct GameState: Codable, Sendable {
    public var players: [PlayerState]
    public var dealer: Seat
    public var current: Seat
    public var phase: Phase
    public var wall: Wall
    public var seed: UInt64
    public var roundIndex: Int
    public var pending: PendingClaim?
    public var lastDrawn: Tile?
    public var winner: Seat?
    public var drawnGame: Bool
    public var result: HandResult?

    public init(players: [PlayerState], dealer: Seat, seed: UInt64, roundIndex: Int) {
        self.players = players
        self.dealer = dealer
        self.current = dealer
        self.phase = .idle
        self.wall = Wall(seed: seed)
        self.seed = seed
        self.roundIndex = roundIndex
        self.pending = nil
        self.lastDrawn = nil
        self.winner = nil
        self.drawnGame = false
        self.result = nil
    }
}

public enum EngineError: Error, Equatable, CustomStringConvertible {
    case notYourTurn
    case wrongPhase
    case illegalAction(String)
    case gameOver

    public var description: String {
        switch self {
        case .notYourTurn: return "没轮到你"
        case .wrongPhase: return "当前阶段不允许这个操作"
        case .illegalAction(let m): return m
        case .gameOver: return "本局已结束"
        }
    }
}
