import Foundation

/// 兜底 AI：不追求强，但要求「像人」——先打皮子、再拆孤张、不无脑碰杠。
/// 真人对局时它只用来补位与超时托管。
public enum Bot {

    public static func nextAction(engine: MahjongEngine, seat: Seat) -> Action? {
        let state = engine.state

        if state.phase == .awaitingClaim, let pending = state.pending,
           pending.outstanding.contains(seat.rawValue) {
            let options = pending.options[seat.rawValue] ?? [.pass]
            if options.contains(.gang) { return .gangExposed }
            if options.contains(.peng), shouldPeng(hand: state.players[seat.rawValue].hand, tile: pending.tile) {
                return .peng
            }
            return .pass
        }

        guard state.phase == .awaitingDiscard, state.current == seat else { return nil }

        if engine.canHu(seat) { return .hu }

        for option in engine.options(for: seat) {
            switch option {
            case .gangAdded(let tile):
                return .gangAdded(tile)
            case .gangConcealed(let tile):
                // 手里四张同牌，杠出去拿分；但如果这一杠会拆掉唯一的两对，先留着
                if state.players[seat.rawValue].melds.count >= 1 { return .gangConcealed(tile) }
            default:
                break
            }
        }

        guard let tile = discardCandidate(hand: state.players[seat.rawValue].hand) else { return nil }
        return .discard(tile)
    }

    public static func shouldPeng(hand: [Tile], tile: Tile) -> Bool {
        guard hand.filter({ $0 == tile }).count >= 2 else { return false }
        let pairs = Dictionary(grouping: hand.filter { !$0.isRed }, by: { $0.raw })
            .filter { $0.value.count >= 2 }.count
        if tile.rank == 1 || tile.rank == 9 { return true }
        return pairs >= 2
    }

    public static func discardCandidate(hand: [Tile]) -> Tile? {
        guard !hand.isEmpty else { return nil }
        // 皮子留不得：手上有红中必须先打
        if let red = hand.first(where: { $0.isRed }) { return red }

        var best: Tile?
        var bestScore = Int.max

        for tile in hand {
            var score = 0
            let same = hand.filter { $0 == tile }.count
            score += same * 4

            if !tile.isRed {
                for delta in [-2, -1, 1, 2] {
                    let target = tile.raw + delta
                    guard (0..<27).contains(target), target / 9 == tile.raw / 9 else { continue }
                    if hand.contains(where: { $0.raw == target }) {
                        score += abs(delta) == 1 ? 3 : 1
                    }
                }
                if tile.rank == 1 || tile.rank == 9 { score -= 2 }
                if tile.rank >= 3 && tile.rank <= 7 { score += 1 }
            }

            if score < bestScore {
                bestScore = score
                best = tile
            }
        }
        return best
    }
}
