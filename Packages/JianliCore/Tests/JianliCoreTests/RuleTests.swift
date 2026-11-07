import XCTest
@testable import JianliCore

final class RuleTests: XCTestCase {

    // MARK: - 牌与牌墙

    func testTileSetIs112() {
        XCTAssertEqual(Tile.fullSet.count, 112)
        XCTAssertEqual(Tile.fullSet.filter { $0.isRed }.count, 4)
        XCTAssertEqual(Tile.fullSet.filter { $0.suit == .wan }.count, 36)
        XCTAssertEqual(Tile.fullSet.filter { $0.suit == .tong }.count, 36)
        XCTAssertEqual(Tile.fullSet.filter { $0.suit == .tiao }.count, 36)
    }

    func testWallIsDeterministic() {
        var a = Wall(seed: 42)
        var b = Wall(seed: 42)
        var c = Wall(seed: 43)
        var seqA: [Int] = []
        var seqB: [Int] = []
        var seqC: [Int] = []
        while let t = a.drawFront() { seqA.append(t.raw) }
        while let t = b.drawFront() { seqB.append(t.raw) }
        while let t = c.drawFront() { seqC.append(t.raw) }
        XCTAssertEqual(seqA, seqB)
        XCTAssertNotEqual(seqA, seqC)
        XCTAssertEqual(seqA.count, 112)
        // 四张同牌
        XCTAssertEqual(seqA.filter { $0 == 27 }.count, 4)
    }

    func testWallDrawsFromBothEnds() {
        var wall = Wall(seed: 7)
        let front = wall.drawFront()
        let back = wall.drawBack()
        XCTAssertNotNil(front)
        XCTAssertNotNil(back)
        XCTAssertEqual(wall.remaining, 110)
        XCTAssertNotEqual(front, back)
    }

    // MARK: - 和牌判定

    func testStandardWin() {
        let hand = [t(.wan, 1), t(.wan, 1), t(.wan, 1),
                    t(.wan, 2), t(.wan, 3), t(.wan, 4),
                    t(.tong, 5), t(.tong, 6), t(.tong, 7),
                    t(.tiao, 7), t(.tiao, 8), t(.tiao, 9),
                    t(.tiao, 9), t(.tiao, 9)]
        XCTAssertTrue(WinChecker.isWinning(hand: hand, melds: []))
        XCTAssertEqual(WinChecker.waitingTiles(hand: Array(hand.dropLast()), melds: []).count, 1)
    }

    func testSevenPairs() {
        let hand = [t(.wan, 1), t(.wan, 1), t(.wan, 3), t(.wan, 3),
                    t(.tong, 2), t(.tong, 2), t(.tong, 6), t(.tong, 6),
                    t(.tiao, 4), t(.tiao, 4), t(.tiao, 8), t(.tiao, 8),
                    t(.tong, 9), t(.tong, 9)]
        XCTAssertTrue(WinChecker.isWinning(hand: hand, melds: []))
    }

    func testHandWithRedDragonNeverWins() {
        var hand = [t(.wan, 1), t(.wan, 1), t(.wan, 1),
                    t(.wan, 2), t(.wan, 3), t(.wan, 4),
                    t(.tong, 5), t(.tong, 6), t(.tong, 7),
                    t(.tiao, 7), t(.tiao, 8), t(.tiao, 9),
                    t(.wan, 9), t(.wan, 9)]
        XCTAssertTrue(WinChecker.isWinning(hand: hand, melds: []))
        hand[12] = Tile(.red, 0)
        XCTAssertFalse(WinChecker.isWinning(hand: hand, melds: []))
        XCTAssertTrue(WinChecker.waitingTiles(hand: hand, melds: []).isEmpty)
    }

    func testWinWithMelds() {
        // 已有两副碰，手牌 8 张（2 面子 + 将）
        let hand = [t(.wan, 2), t(.wan, 3), t(.wan, 4),
                    t(.tong, 5), t(.tong, 6), t(.tong, 7),
                    t(.tiao, 9), t(.tiao, 9)]
        let melds = [Meld(kind: .peng, tile: t(.wan, 1)), Meld(kind: .peng, tile: t(.tong, 1))]
        XCTAssertTrue(WinChecker.isWinning(hand: hand, melds: melds))
    }

    // MARK: - 分数

    func testSelfDrawBaseWithNoPizi() {
        let engine = makeEngine(hands: [[t(.wan, 1), t(.wan, 2)], [], [], []])
        XCTAssertEqual(engine.amount(base: 10, winner: .east, payer: .south), 10)
    }

    func testPiziMultiplier() {
        var state = baseState(hands: [[t(.wan, 1)], [], [], []])
        state.players[0].redsPlayed = 1
        let engine = MahjongEngine(state: state)
        XCTAssertEqual(engine.amount(base: 10, winner: .east, payer: .south), 20)

        var twoRed = state
        twoRed.players[0].redsPlayed = 2
        XCTAssertEqual(MahjongEngine(state: twoRed).amount(base: 10, winner: .east, payer: .south), 40)

        // 付钱方自己也打过一张，两边相乘
        var both = state
        both.players[1].redsPlayed = 1
        XCTAssertEqual(MahjongEngine(state: both).amount(base: 10, winner: .east, payer: .south), 40)
        XCTAssertEqual(MahjongEngine(state: both).amount(base: 10, winner: .east, payer: .west), 20)
    }

    // MARK: - 打红中

    func testDiscardingRedDragonDrawsFromBackAndCounts() throws {
        var state = baseState(hands: [[Tile(.red, 0), t(.wan, 1), t(.wan, 2), t(.wan, 3), t(.wan, 4), t(.wan, 5), t(.wan, 6), t(.wan, 7), t(.wan, 8), t(.wan, 9), t(.tong, 1), t(.tong, 2), t(.tong, 3), t(.tong, 4)], [], [], []])
        state.phase = .awaitingDiscard
        state.current = .east
        let engine = MahjongEngine(state: state)
        var mut = engine
        let events = try mut.apply(.discard(Tile(.red, 0)), by: .east)

        XCTAssertEqual(mut.state.players[0].redsPlayed, 1)
        XCTAssertEqual(mut.state.players[0].hand.count, 14)
        XCTAssertTrue(events.contains { if case .redDiscarded = $0 { return true }; return false })
        XCTAssertEqual(mut.state.wall.remaining, state.wall.remaining - 1)
    }

    func testFourRedDragonsIsConcealedGang() throws {
        var state = baseState(hands: [[Tile(.red, 0), Tile(.red, 0), Tile(.red, 0), Tile(.red, 0),
                                       t(.wan, 1), t(.wan, 2), t(.wan, 3), t(.wan, 4), t(.wan, 5),
                                       t(.wan, 6), t(.wan, 7), t(.wan, 8), t(.wan, 9), t(.tong, 1)], [], [], []])
        state.phase = .awaitingDiscard
        state.current = .east
        var mut = MahjongEngine(state: state)

        for _ in 0..<4 {
            _ = try mut.apply(.discard(Tile(.red, 0)), by: .east)
        }
        XCTAssertEqual(mut.state.players[0].redsPlayed, 4)
        // 15 × 2^4 × 2^0 = 240，三家共 720
        XCTAssertEqual(mut.state.players[0].score, 720)
        XCTAssertEqual(mut.state.players[1].score, -240)
    }

    // MARK: - 碰杠与分数

    func testPointGangPaidByDiscarderOnly() throws {
        var state = baseState(hands: [
            [t(.wan, 2), t(.wan, 3), t(.wan, 4), t(.wan, 5), t(.wan, 6), t(.wan, 7), t(.wan, 8), t(.wan, 9), t(.tong, 1), t(.tong, 2), t(.tong, 3), t(.tong, 4), t(.tong, 5)],
            [t(.wan, 1), t(.wan, 1), t(.wan, 1), t(.tong, 5), t(.tong, 6), t(.tong, 7), t(.tiao, 2), t(.tiao, 3), t(.tiao, 4), t(.tiao, 6), t(.tiao, 7), t(.tiao, 8), t(.tiao, 9)],
            [], []
        ])
        state.phase = .awaitingDiscard
        state.current = .east
        var mut = MahjongEngine(state: state)
        _ = try mut.apply(.discard(t(.wan, 1)), by: .east)

        XCTAssertEqual(mut.state.phase, .awaitingClaim)
        _ = try mut.apply(.pass, by: .west)
        _ = try mut.apply(.gangExposed, by: .south)

        XCTAssertEqual(mut.state.players[1].score, 10)
        XCTAssertEqual(mut.state.players[0].score, -10)
        XCTAssertEqual(mut.state.players[2].score, 0)
        XCTAssertEqual(mut.state.players[1].melds.first?.kind, .gangExposed)
    }

    // MARK: - 整局跑通

    func testFullGameWithBotsFinishesAndKeepsTiles() throws {
        let final = try runBots(seed: 20261107)
        XCTAssertEqual(final.state.phase, .finished)
        XCTAssertEqual(conserve(final.state), 112)
    }

    func testReplayIsDeterministic() throws {
        let a = try runBots(seed: 99)
        let b = try runBots(seed: 99)
        XCTAssertEqual(conserve(a.state), 112)
        XCTAssertEqual(a.state.players.map { $0.score }, b.state.players.map { $0.score })
        XCTAssertEqual(a.state.winner, b.state.winner)
        XCTAssertEqual(a.state.wall.head, b.state.wall.head)
    }

    // MARK: - 工具

    private func t(_ suit: TileSuit, _ rank: Int) -> Tile { Tile(suit, rank) }

    private func baseState(hands: [[Tile]]) -> GameState {
        var players: [PlayerState] = []
        for i in 0..<4 {
            let seat = Seat(rawValue: i)!
            var p = PlayerState(seat: seat, name: "P\(i)")
            p.hand = hands[i]
            players.append(p)
        }
        var state = GameState(players: players, dealer: .east, seed: 1, roundIndex: 1)
        state.wall = Wall(tiles: Array(Tile.fullSet.prefix(60)), head: 0, tail: 59)
        return state
    }

    private func makeEngine(hands: [[Tile]]) -> MahjongEngine {
        MahjongEngine(state: baseState(hands: hands))
    }

    private func conserve(_ state: GameState) -> Int {
        var total = state.wall.remaining
        for p in state.players {
            total += p.hand.count + p.river.count
            total += p.melds.reduce(0) { $0 + $1.tileCount }
        }
        return total
    }

    private func runBots(seed: UInt64) throws -> MahjongEngine {
        var engine = MahjongEngine(seed: seed, names: ["A", "B", "C", "D"], botSeats: Set(Seat.allCases), dealer: .east)
        engine.startHand()

        var steps = 0
        while engine.state.phase != .finished && steps < 4000 {
            steps += 1
            if engine.state.phase == .awaitingClaim, let pending = engine.state.pending {
                for seatRaw in pending.outstanding {
                    guard let seat = Seat(rawValue: seatRaw) else { continue }
                    if let action = Bot.nextAction(engine: engine, seat: seat) {
                        _ = try engine.apply(action, by: seat)
                    }
                }
                continue
            }
            let seat = engine.state.current
            guard let action = Bot.nextAction(engine: engine, seat: seat) else {
                XCTFail("机器人无动作可做，阶段 \(engine.state.phase)")
                break
            }
            _ = try engine.apply(action, by: seat)
        }
        XCTAssertLessThan(steps, 4000, "对局没有正常结束")
        return engine
    }
}
