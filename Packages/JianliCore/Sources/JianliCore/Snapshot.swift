import Foundation

/// 单个座位在桌面上的可见信息。别人手里的牌只给张数，不给牌面。
public struct SeatView: Codable, Sendable, Identifiable {
    public var seat: Seat
    public var name: String
    public var hand: [Tile]
    public var handCount: Int
    public var melds: [Meld]
    public var river: [Tile]
    public var redsPlayed: Int
    public var score: Int
    public var isBot: Bool
    public var connected: Bool

    public var id: Int { seat.rawValue }

    public init(seat: Seat, name: String, hand: [Tile], handCount: Int, melds: [Meld], river: [Tile], redsPlayed: Int, score: Int, isBot: Bool, connected: Bool) {
        self.seat = seat
        self.name = name
        self.hand = hand
        self.handCount = handCount
        self.melds = melds
        self.river = river
        self.redsPlayed = redsPlayed
        self.score = score
        self.isBot = isBot
        self.connected = connected
    }
}

public struct TableSnapshot: Codable, Sendable {
    public var you: Seat
    public var players: [SeatView]
    public var current: Seat
    public var phase: Phase
    public var wallRemaining: Int
    public var lastDrawn: Tile?
    public var dealer: Seat
    public var roundIndex: Int
    public var totalRounds: Int
    public var seed: UInt64
    /// 轮到别人出牌、正在等你表态时可选的声明
    public var claimOptions: [ClaimOption]
    public var claimTile: Tile?
    public var canDiscard: Bool
    public var canHu: Bool
    public var gangConcealedOptions: [Tile]
    public var gangAddedOptions: [Tile]
    public var result: HandResult?
    public var drawnGame: Bool
    public var waitingTiles: [Tile]
    public var ruleName: String
    public var redGangDone: Bool

    public var me: SeatView { players[you.rawValue] }
    public var totalRedsPlayed: Int { players.reduce(0) { $0 + $1.redsPlayed } }

    public init(you: Seat,
                players: [SeatView],
                current: Seat,
                phase: Phase,
                wallRemaining: Int,
                lastDrawn: Tile?,
                dealer: Seat,
                roundIndex: Int,
                totalRounds: Int,
                seed: UInt64,
                claimOptions: [ClaimOption],
                claimTile: Tile?,
                canDiscard: Bool,
                canHu: Bool,
                gangConcealedOptions: [Tile],
                gangAddedOptions: [Tile],
                result: HandResult?,
                drawnGame: Bool,
                waitingTiles: [Tile],
                ruleName: String,
                redGangDone: Bool) {
        self.you = you
        self.players = players
        self.current = current
        self.phase = phase
        self.wallRemaining = wallRemaining
        self.lastDrawn = lastDrawn
        self.dealer = dealer
        self.roundIndex = roundIndex
        self.totalRounds = totalRounds
        self.seed = seed
        self.claimOptions = claimOptions
        self.claimTile = claimTile
        self.canDiscard = canDiscard
        self.canHu = canHu
        self.gangConcealedOptions = gangConcealedOptions
        self.gangAddedOptions = gangAddedOptions
        self.result = result
        self.drawnGame = drawnGame
        self.waitingTiles = waitingTiles
        self.ruleName = ruleName
        self.redGangDone = redGangDone
    }
}

extension MahjongEngine {
    public func snapshot(for seat: Seat) -> TableSnapshot {
        let reveal = state.phase == .finished
        var views: [SeatView] = []
        for p in state.players {
            views.append(SeatView(seat: p.seat,
                                  name: p.name,
                                  hand: (reveal || p.seat == seat) ? p.hand : [],
                                  handCount: p.hand.count,
                                  melds: p.melds,
                                  river: p.river,
                                  redsPlayed: p.redsPlayed,
                                  score: p.score,
                                  isBot: p.isBot,
                                  connected: p.connected))
        }

        var claimOptions: [ClaimOption] = []
        var claimTile: Tile?
        if state.phase == .awaitingClaim, let pending = state.pending {
            claimOptions = pending.options[seat.rawValue] ?? []
            claimTile = pending.tile
        }

        let isMine = state.phase == .awaitingDiscard && state.current == seat
        var concealed: [Tile] = []
        var added: [Tile] = []
        if isMine {
            for option in options(for: seat) {
                switch option {
                case .gangConcealed(let tile): concealed.append(tile)
                case .gangAdded(let tile): added.append(tile)
                default: break
                }
            }
        }

        let me = state.players[seat.rawValue]
        let waiting = isMine ? WinChecker.waitingTiles(hand: me.hand, melds: me.melds, allowSevenPairs: rule.allowSevenPairs) : []

        return TableSnapshot(you: seat,
                             players: views,
                             current: state.current,
                             phase: state.phase,
                             wallRemaining: state.wall.remaining,
                             lastDrawn: state.lastDrawn,
                             dealer: state.dealer,
                             roundIndex: state.roundIndex,
                             totalRounds: rule.rounds,
                             seed: state.seed,
                             claimOptions: claimOptions,
                             claimTile: claimTile,
                             canDiscard: isMine,
                             canHu: isMine && canHu(seat),
                             gangConcealedOptions: concealed,
                             gangAddedOptions: added,
                             result: state.result,
                             drawnGame: state.drawnGame,
                             waitingTiles: waiting,
                             ruleName: rule.name,
                             redGangDone: me.redsPlayed >= 4)
    }
}
