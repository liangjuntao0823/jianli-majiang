import Foundation

public enum WinChecker {

    /// 判断是否和牌。红中是皮子，手牌里带红中一律不算和。
    public static func isWinning(hand: [Tile], melds: [Meld], allowSevenPairs: Bool = true) -> Bool {
        guard !hand.contains(where: { $0.isRed }) else { return false }

        var counts = [Int](repeating: 0, count: 27)
        for tile in hand {
            guard tile.raw < 27 else { return false }
            counts[tile.raw] += 1
        }

        let setsNeeded = 4 - melds.count
        guard setsNeeded >= 0 else { return false }
        guard hand.count == setsNeeded * 3 + 2 else { return false }

        if allowSevenPairs, melds.isEmpty, hand.count == 14 {
            let pairs = counts.reduce(0) { $0 + $1 / 2 }
            let allEven = counts.allSatisfy { $0 % 2 == 0 }
            if allEven, pairs == 7 { return true }
        }

        for pair in 0..<27 where counts[pair] >= 2 {
            var rest = counts
            rest[pair] -= 2
            if canFormSets(rest, sets: setsNeeded) { return true }
        }
        return false
    }

    static func canFormSets(_ counts: [Int], sets: Int) -> Bool {
        if sets == 0 { return counts.allSatisfy { $0 == 0 } }
        guard let first = counts.firstIndex(where: { $0 > 0 }) else { return false }

        var c = counts
        if c[first] >= 3 {
            c[first] -= 3
            if canFormSets(c, sets: sets - 1) { return true }
        }

        let rank = first % 9
        if rank <= 6, c[first + 1] > 0, c[first + 2] > 0 {
            c = counts
            c[first] -= 1
            c[first + 1] -= 1
            c[first + 2] -= 1
            if canFormSets(c, sets: sets - 1) { return true }
        }
        return false
    }

    /// 听牌提示：把手牌逐张替换为可能的牌，返回能和的牌（只用于 UI 提示，不参与裁决）
    public static func waitingTiles(hand: [Tile], melds: [Meld], allowSevenPairs: Bool = true) -> [Tile] {
        guard !hand.contains(where: { $0.isRed }) else { return [] }
        var result: [Tile] = []
        for kind in Tile.allKinds where !kind.isRed {
            var test = hand
            test.append(kind)
            if isWinning(hand: test, melds: melds, allowSevenPairs: allowSevenPairs) {
                result.append(kind)
            }
        }
        return result
    }
}
