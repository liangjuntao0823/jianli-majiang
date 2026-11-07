import SwiftUI
import UIKit
import JianliCore

private struct PaymentRow: Identifiable {
    let id: Int
    let name: String
    let amount: Int
    let formula: String
}

struct SettlementView: View {
    let snapshot: TableSnapshot
    @EnvironmentObject private var model: AppModel

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.width < 760
            ZStack {
                Color.black.opacity(0.55).ignoresSafeArea()
                ScrollView(.vertical, showsIndicators: false) {
                    card(compact: compact)
                        .frame(maxWidth: compact ? .infinity : 760)
                        .padding(14)
                }
            }
        }
    }

    private func card(compact: Bool) -> some View {
        HStack(alignment: .top, spacing: compact ? 14 : 22) {
            resultColumn
            Rectangle().fill(Color.black.opacity(0.10)).frame(width: 1)
            handColumn(compact: compact)
            scoreColumn
        }
        .padding(compact ? 14 : 22)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.13, green: 0.16, blue: 0.15),
                                              Color(red: 0.08, green: 0.10, blue: 0.10)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Theme.gold.opacity(0.35), lineWidth: 1))
                .shadow(color: .black.opacity(0.6), radius: 24, y: 10)
        )
    }

    private var result: HandResult? { snapshot.result }
    private var isDraw: Bool { snapshot.drawnGame }

    // MARK: - 左：谁赢、怎么算

    private var resultColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isDraw ? "流局" : "自摸")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.dimText)
            Text(result.map { snapshot.players[$0.winner.rawValue].name } ?? "—")
                .font(.system(size: 28, weight: .black, design: .serif))
                .foregroundStyle(Theme.gold)

            if let result {
                Text("底分 \(result.base) · 赢家皮子 \(result.winnerReds) 张 → ×\(1 << result.winnerReds)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.dimText)

                VStack(alignment: .leading, spacing: 5) {
                    ForEach(paymentRows(result)) { row in
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(row.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.82))
                                Spacer(minLength: 4)
                                Text("−\(row.amount)")
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color(red: 0.93, green: 0.58, blue: 0.50))
                            }
                            Text(row.formula)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(Theme.dimText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 2)

                HStack(spacing: 6) {
                    Text(seedText(result.seed))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Theme.dimText)
                    Button {
                        UIPasteboard.general.string = seedText(result.seed)
                        model.toast = "种子已复制，可复盘这一局"
                    } label: {
                        Text("复制种子")
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Theme.panel))
                            .foregroundStyle(Theme.gold.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
            } else {
                Text("牌墙摸完，庄家不变，不收分")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dimText)
            }
        }
        .frame(width: 200, alignment: .leading)
    }

    /// 把倍乘算式写出来：底分 × 2^赢家皮子 × 2^付家皮子
    private func paymentRows(_ result: HandResult) -> [PaymentRow] {
        result.payments.keys.sorted().map { key in
            let payerReds = snapshot.players[key].redsPlayed
            let amount = result.payments[key] ?? 0
            var formula = "\(result.base) × \(1 << result.winnerReds)"
            if payerReds > 0 {
                formula += " × \(1 << payerReds)（他打了 \(payerReds) 张红中）"
            }
            formula += " = \(amount)"
            return PaymentRow(id: key,
                              name: snapshot.players[key].name,
                              amount: amount,
                              formula: formula)
        }
    }

    private func seedText(_ seed: UInt64) -> String {
        "种子 0x" + String(seed, radix: 16).uppercased()
    }

    // MARK: - 中：和牌手牌

    private func handColumn(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("和牌")
                .font(.system(size: 12))
                .foregroundStyle(Theme.dimText)

            if let result {
                let size = CGSize(width: compact ? 30 : 40, height: compact ? 41 : 54)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 3) {
                        ForEach(Array(result.hand.enumerated()), id: \.offset) { _, tile in
                            MahjongTileView(tile: tile, size: size)
                        }
                        if !result.melds.isEmpty {
                            Rectangle().fill(Color.white.opacity(0.2))
                                .frame(width: 1, height: size.height)
                                .padding(.horizontal, 2)
                            ForEach(result.melds, id: \.self) { meld in
                                HStack(spacing: 1) {
                                    ForEach(0..<meld.tileCount, id: \.self) { _ in
                                        MahjongTileView(tile: meld.tile,
                                                        size: CGSize(width: size.width * 0.8, height: size.height * 0.8))
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(height: size.height + 2)
            }

            Spacer(minLength: 4)
            HStack(spacing: 10) {
                Button { model.nextHand() } label: {
                    Text("下一局")
                        .font(.system(size: 14, weight: .semibold, design: .serif))
                        .foregroundStyle(Theme.feltDeep)
                        .frame(width: 110, height: 38)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.gold))
                }
                .buttonStyle(.plain)
                Button { model.leaveTable() } label: {
                    Text("返回大厅")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 110, height: 38)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.10)))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: compact ? 250 : 360, alignment: .leading)
    }

    // MARK: - 右：四家总分

    private var scoreColumn: some View {
        VStack(spacing: 6) {
            ForEach(snapshot.players) { player in
                HStack(spacing: 6) {
                    Text(player.seat.label)
                        .font(.system(size: 11, weight: .semibold, design: .serif))
                        .foregroundStyle(Theme.gold.opacity(0.8))
                        .frame(width: 14)
                    Text(player.name)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 52, alignment: .leading)
                    Text(player.score >= 0 ? "+\(player.score)" : "\(player.score)")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(player.score >= 0 ? Theme.gold : Color(red: 0.93, green: 0.58, blue: 0.50))
                        .frame(width: 54, alignment: .trailing)
                }
            }
        }
    }
}
