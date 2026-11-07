import Foundation

/// 房主权威的规则引擎：纯函数式推进，输入 Action 输出 Event。
/// 全程只有发牌用随机数，局中不再取随机，保证 seed + 动作日志可逐帧重放。
public struct MahjongEngine: Sendable {

    public private(set) var state: GameState
    public let rule: RuleProfile
    public private(set) var events: [GameEvent] = []

    public init(rule: RuleProfile = .jianliRedDragon,
                seed: UInt64,
                names: [String],
                dealer: Seat = .east,
                roundIndex: Int = 1,
                botSeats: Set<Seat> = []) {
        var players: [PlayerState] = []
        for i in 0..<4 {
            let seat = Seat(rawValue: i)!
            let name = i < names.count && !names[i].isEmpty ? names[i] : "\(seat.label)家"
            players.append(PlayerState(seat: seat, name: name, isBot: botSeats.contains(seat)))
        }
        self.rule = rule
        self.state = GameState(players: players, dealer: dealer, seed: seed, roundIndex: roundIndex)
    }

    /// 从既有状态恢复（重连、回放、单测构造牌局都用它）
    public init(state: GameState, rule: RuleProfile = .jianliRedDragon) {
        self.rule = rule
        self.state = state
    }

    // MARK: - 开局

    @discardableResult
    public mutating func startHand() -> [GameEvent] {
        state.wall = Wall(seed: state.seed &+ UInt64(state.roundIndex) &* 0x9E37_79B9_7F4A_7C15)
        for i in 0..<4 {
            state.players[i].hand = []
            state.players[i].melds = []
            state.players[i].river = []
            state.players[i].redsPlayed = 0
        }
        state.pending = nil
        state.lastDrawn = nil
        state.winner = nil
        state.drawnGame = false
        state.result = nil
        state.current = state.dealer
        state.phase = .idle

        for _ in 0..<13 {
            for k in 0..<4 {
                let seat = Seat(rawValue: (state.dealer.rawValue + k) % 4)!
                if let tile = state.wall.drawFront() {
                    state.players[seat.rawValue].hand.append(tile)
                }
            }
        }
        var out: [GameEvent] = []

        // 起手摸到的红中同样必打：直接摆上自己台面，从尾牌换进来
        for i in 0..<4 {
            let seat = Seat(rawValue: i)!
            var guardCount = 0
            while let idx = state.players[i].hand.firstIndex(where: { $0.isRed }), guardCount < 8 {
                guardCount += 1
                state.players[i].hand.remove(at: idx)
                state.players[i].redsPlayed += 1
                out.append(.redDiscarded(seat: seat, count: state.players[i].redsPlayed))
                if let replacement = state.wall.drawBack() {
                    state.players[i].hand.append(replacement)
                }
            }
            state.players[i].hand.sort()
        }

        out.insert(.handStarted(dealer: state.dealer, seed: state.seed, roundIndex: state.roundIndex), at: 0)
        out.append(contentsOf: drawTurn(state.dealer))
        events = out
        return out
    }

    /// 下一局：谁胡谁坐庄，流局庄家不变；分数跨局累计，不清零。
    @discardableResult
    public mutating func startNextHand(seed: UInt64) -> [GameEvent] {
        if let winner = state.winner { state.dealer = winner }
        state.seed = seed
        state.roundIndex += 1
        return startHand()
    }

    // MARK: - 动作入口

    public mutating func apply(_ action: Action, by seat: Seat) throws -> [GameEvent] {
        guard state.phase != .finished else { throw EngineError.gameOver }
        let out: [GameEvent]
        switch action {
        case .discard(let tile):
            out = try discard(tile, by: seat)
        case .peng:
            out = try respond(.peng, by: seat)
        case .gangExposed:
            out = try respond(.gang, by: seat)
        case .pass:
            out = try respond(.pass, by: seat)
        case .gangConcealed(let tile):
            out = try concealedGang(tile, by: seat)
        case .gangAdded(let tile):
            out = try addedGang(tile, by: seat)
        case .hu:
            out = try hu(by: seat)
        }
        events.append(contentsOf: out)
        return out
    }

    // MARK: - 出牌

    private mutating func discard(_ tile: Tile, by seat: Seat) throws -> [GameEvent] {
        guard state.phase == .awaitingDiscard, state.current == seat else { throw EngineError.notYourTurn }
        let p = seat.rawValue
        guard let idx = state.players[p].hand.firstIndex(of: tile) else {
            throw EngineError.illegalAction("手里没有这张牌")
        }
        state.players[p].hand.remove(at: idx)
        state.lastDrawn = nil
        // 红中是皮子，摆在台面不进牌河，别人也碰不到
        if !tile.isRed { state.players[p].river.append(tile) }

        var out: [GameEvent] = [.discarded(seat: seat, tile: tile), .wallRemaining(state.wall.remaining)]

        // 皮子：红中必打，摆在自己台面，从尾牌换一张，结算翻倍
        if tile.isRed {
            state.players[p].redsPlayed += 1
            out.append(.redDiscarded(seat: seat, count: state.players[p].redsPlayed))

            if state.players[p].redsPlayed >= 4 {
                out.append(contentsOf: pay(base: rule.redGangBase, winner: seat, payers: seat.others, reason: .redGang))
            }

            if let replacement = state.wall.drawBack() {
                state.players[p].hand.append(replacement)
                state.players[p].hand.sort()
                state.lastDrawn = replacement
                state.current = seat
                state.phase = .awaitingDiscard
                out.append(.turn(seat: seat, drawn: replacement))
                out.append(.wallRemaining(state.wall.remaining))
            } else {
                out.append(finishDrawn())
            }
            return out
        }

        // 常规出牌，开声明窗口（只能碰、杠；不能吃；不能点炮胡）
        var options: [Int: [ClaimOption]] = [:]
        for s in 0..<4 where s != p {
            let count = state.players[s].hand.filter { $0 == tile }.count
            if count >= 3 {
                options[s] = [.pass, .gang]
            } else if count == 2 {
                options[s] = [.pass, .peng]
            }
        }

        if options.isEmpty {
            out.append(contentsOf: drawTurn(seat.next))
        } else {
            state.phase = .awaitingClaim
            state.pending = PendingClaim(discarder: seat,
                                         tile: tile,
                                         options: options,
                                         outstanding: options.keys.sorted())
            out.append(.claimWindow(discarder: seat, tile: tile))
        }
        return out
    }

    // MARK: - 声明

    private mutating func respond(_ option: ClaimOption, by seat: Seat) throws -> [GameEvent] {
        guard state.phase == .awaitingClaim, let pending = state.pending else { throw EngineError.wrongPhase }
        guard pending.options[seat.rawValue]?.contains(option) == true else {
            throw EngineError.illegalAction("当前不能这样声明")
        }
        var updated = pending
        updated.answers[seat.rawValue] = option
        updated.outstanding.removeAll { $0 == seat.rawValue }
        state.pending = updated

        guard updated.outstanding.isEmpty else { return [] }
        return try resolve(updated)
    }

    private mutating func resolve(_ pending: PendingClaim) throws -> [GameEvent] {
        // 优先级：杠 > 碰，同级按离出牌人近者优先
        func nearest(_ seats: [Int]) -> Int? {
            seats.min { lhs, rhs in
                state.players[lhs].seat.distance(to: pending.discarder) < state.players[rhs].seat.distance(to: pending.discarder)
            }
        }

        let gangSeats = pending.answers.filter { $0.value == .gang }.keys.sorted()
        let pengSeats = pending.answers.filter { $0.value == .peng }.keys.sorted()
        state.pending = nil

        if let s = nearest(gangSeats), let seat = Seat(rawValue: s) {
            return try claimGang(by: seat, pending: pending)
        }
        if let s = nearest(pengSeats), let seat = Seat(rawValue: s) {
            return try claimPeng(by: seat, pending: pending)
        }
        // 全部过牌，下家摸牌
        return drawTurn(pending.discarder.next)
    }

    private mutating func claimPeng(by seat: Seat, pending: PendingClaim) throws -> [GameEvent] {
        let p = seat.rawValue
        try removeTiles(pending.tile, count: 2, from: p)
        state.players[p].melds.append(Meld(kind: .peng, tile: pending.tile))
        removeFromRiver(tile: pending.tile, seat: pending.discarder)

        state.current = seat
        state.phase = .awaitingDiscard
        state.lastDrawn = nil
        return [.peng(seat: seat, tile: pending.tile)]
    }

    private mutating func claimGang(by seat: Seat, pending: PendingClaim) throws -> [GameEvent] {
        let p = seat.rawValue
        try removeTiles(pending.tile, count: 3, from: p)
        state.players[p].melds.append(Meld(kind: .gangExposed, tile: pending.tile))
        removeFromRiver(tile: pending.tile, seat: pending.discarder)

        var out: [GameEvent] = [.gang(seat: seat, kind: .gangExposed, tile: pending.tile, drawn: nil)]
        // 点杠：打出第四张的人独付
        out.append(contentsOf: pay(base: rule.pointGangBase, winner: seat, payers: [pending.discarder], reason: .pointGang))
        out.append(contentsOf: drawTurn(seat, fromBack: true))
        return out
    }

    // MARK: - 自己回合的杠

    private mutating func concealedGang(_ tile: Tile, by seat: Seat) throws -> [GameEvent] {
        guard state.phase == .awaitingDiscard, state.current == seat else { throw EngineError.notYourTurn }
        let p = seat.rawValue
        guard tile.raw < 27, state.players[p].hand.filter({ $0 == tile }).count == 4 else {
            throw EngineError.illegalAction("没有四张一样的牌")
        }
        try removeTiles(tile, count: 4, from: p)
        state.players[p].melds.append(Meld(kind: .gangConcealed, tile: tile))

        var out: [GameEvent] = [.gang(seat: seat, kind: .gangConcealed, tile: tile, drawn: nil)]
        out.append(contentsOf: pay(base: rule.concealedGangBase, winner: seat, payers: seat.others, reason: .concealedGang))
        out.append(contentsOf: drawTurn(seat, fromBack: true))
        return out
    }

    private mutating func addedGang(_ tile: Tile, by seat: Seat) throws -> [GameEvent] {
        guard state.phase == .awaitingDiscard, state.current == seat else { throw EngineError.notYourTurn }
        let p = seat.rawValue
        guard let meldIndex = state.players[p].melds.firstIndex(where: { $0.tile == tile && $0.kind == .peng }) else {
            throw EngineError.illegalAction("没有这张牌的碰")
        }
        guard state.players[p].hand.contains(tile) else {
            throw EngineError.illegalAction("手里没有第四张")
        }
        try removeTiles(tile, count: 1, from: p)
        state.players[p].melds[meldIndex].kind = .gangAdded

        var out: [GameEvent] = [.gang(seat: seat, kind: .gangAdded, tile: tile, drawn: nil)]
        // 蓄杠（回头笑）5 分，三家各付。本玩法不能抢杠，所以没有抢杠窗口。
        out.append(contentsOf: pay(base: rule.addedGangBase, winner: seat, payers: seat.others, reason: .addedGang))
        out.append(contentsOf: drawTurn(seat, fromBack: true))
        return out
    }

    // MARK: - 胡

    private mutating func hu(by seat: Seat) throws -> [GameEvent] {
        guard state.phase == .awaitingDiscard, state.current == seat else { throw EngineError.notYourTurn }
        let p = seat.rawValue
        let hand = state.players[p].hand
        guard !hand.contains(where: { $0.isRed }) else {
            throw EngineError.illegalAction("手上带红中，不能胡")
        }
        guard WinChecker.isWinning(hand: hand, melds: state.players[p].melds, allowSevenPairs: rule.allowSevenPairs) else {
            throw EngineError.illegalAction("牌型不成和")
        }

        var payments: [Int: Int] = [:]
        for other in seat.others {
            payments[other.rawValue] = amount(base: rule.selfDrawBase, winner: seat, payer: other)
        }
        for other in seat.others {
            let value = payments[other.rawValue] ?? 0
            state.players[other.rawValue].score -= value
            state.players[p].score += value
        }

        let result = HandResult(winner: seat,
                                hand: hand,
                                melds: state.players[p].melds,
                                payments: payments,
                                winnerReds: state.players[p].redsPlayed,
                                base: rule.selfDrawBase,
                                scores: state.players.map { $0.score },
                                roundIndex: state.roundIndex,
                                seed: state.seed)

        state.phase = .finished
        state.winner = seat
        state.drawnGame = false
        state.result = result
        return [.hu(seat: seat, payments: payments)]
    }

    // MARK: - 摸牌与流局

    @discardableResult
    private mutating func drawTurn(_ seat: Seat, fromBack: Bool = false) -> [GameEvent] {
        let p = seat.rawValue
        var out: [GameEvent] = []
        var back = fromBack

        // 红中必打：摸到红中不能留在手上，直接摆上自己台面，再从尾牌换一张。
        // 一直换到摸到真牌为止（最多四张，不会死循环）。
        while true {
            guard let drawn = back ? state.wall.drawBack() : state.wall.drawFront() else {
                out.append(finishDrawn())
                return out
            }
            state.lastDrawn = drawn
            state.lastDrawnFromTail = back

            if drawn.isRed {
                state.players[p].redsPlayed += 1
                out.append(.redDiscarded(seat: seat, count: state.players[p].redsPlayed))
                if state.players[p].redsPlayed >= 4 {
                    out.append(contentsOf: pay(base: rule.redGangBase, winner: seat, payers: seat.others, reason: .redGang))
                }
                out.append(.wallRemaining(state.wall.remaining))
                back = true
                continue
            }

            state.players[p].hand.append(drawn)
            state.players[p].hand.sort()
            state.current = seat
            state.phase = .awaitingDiscard
            state.pending = nil
            out.append(.turn(seat: seat, drawn: drawn))
            out.append(.wallRemaining(state.wall.remaining))
            return out
        }
    }

    private mutating func finishDrawn() -> GameEvent {
        state.phase = .finished
        state.drawnGame = true
        state.winner = nil
        state.result = nil
        return .drawnGame
    }

    // MARK: - 分账

    /// 皮子倍乘：赢家每打出一张红中翻一倍，付钱一方自己也按打出的红中再翻一倍（两边相乘）
    public func amount(base: Int, winner: Seat, payer: Seat) -> Int {
        let winnerMul = 1 << min(state.players[winner.rawValue].redsPlayed, 8)
        let payerMul = 1 << min(state.players[payer.rawValue].redsPlayed, 8)
        return base * winnerMul * payerMul
    }

    private mutating func pay(base: Int, winner: Seat, payers: [Seat], reason: ScoreReason) -> [GameEvent] {
        var out: [GameEvent] = []
        for payer in payers where payer != winner {
            let value = amount(base: base, winner: winner, payer: payer)
            state.players[payer.rawValue].score -= value
            state.players[winner.rawValue].score += value
            out.append(.score(from: payer, to: winner, amount: value, reason: reason))
        }
        return out
    }

    // MARK: - 工具

    private mutating func removeTiles(_ tile: Tile, count: Int, from p: Int) throws {
        for _ in 0..<count {
            guard let idx = state.players[p].hand.firstIndex(of: tile) else {
                throw EngineError.illegalAction("手牌不足")
            }
            state.players[p].hand.remove(at: idx)
        }
    }

    private mutating func removeFromRiver(tile: Tile, seat: Seat) {
        if let idx = state.players[seat.rawValue].river.lastIndex(of: tile) {
            state.players[seat.rawValue].river.remove(at: idx)
        }
    }

    /// 轮到某人时，他能做的动作（给 UI 与 AI 用，不含弃牌候选）
    public func options(for seat: Seat) -> [Action] {
        guard state.phase == .awaitingDiscard, state.current == seat else { return [] }
        let p = seat.rawValue
        var out: [Action] = []
        if canHu(seat) { out.append(.hu) }
        for kind in Tile.allKinds where !kind.isRed {
            if state.players[p].hand.filter({ $0 == kind }).count == 4 {
                out.append(.gangConcealed(kind))
            }
            if state.players[p].melds.contains(where: { $0.kind == .peng && $0.tile == kind }),
               state.players[p].hand.contains(kind) {
                out.append(.gangAdded(kind))
            }
        }
        return out
    }

    public func canHu(_ seat: Seat) -> Bool {
        let p = seat.rawValue
        let hand = state.players[p].hand
        guard !hand.contains(where: { $0.isRed }) else { return false }
        return WinChecker.isWinning(hand: hand, melds: state.players[p].melds, allowSevenPairs: rule.allowSevenPairs)
    }
}
