import SwiftUI
import JianliCore

private struct PaymentRow: Identifiable {
    let id: Int
    let name: String
    let amount: Int
}

struct SettlementView: View {
    let snapshot: TableSnapshot
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            card
                .frame(maxWidth: 760)
                .padding(18)
        }
    }

    private var card: some View {
        HStack(alignment: .top, spacing: 22) {
            resultColumn
            Rectangle().fill(Color.black.opacity(0.08)).frame(width: 1)
            handColumn
            scoreColumn
        }
        .padding(22)
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

    private var resultColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isDraw ? "流局" : "自摸")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.dimText)
            Text(result.map { snapshot.players[$0.winner.rawValue].name } ?? "—")
                .font(.system(size: 30, weight: .black, design: .serif))
                .foregroundStyle(Theme.gold)
            if let result {
                Text("底分 \(result.base) · 皮子 ×\(1 << result.winnerReds)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dimText)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(paymentRows(result)) { row in
                        HStack(spacing: 6) {
                            Text(row.name)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.7))
                            Text("−\(row.amount)")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color(red: 0.93, green: 0.58, blue: 0.50))
                        }
                    }
                }
                Text("赢家已打红中 \(result.winnerReds) 张；付钱方每张红中再翻一倍")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.dimText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            } else {
                Text("牌墙摸完，庄家不变，不收分")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dimText)
            }
        }
        .frame(width: 170, alignment: .leading)
    }

    private func paymentRows(_ result: HandResult) -> [PaymentRow] {
        result.payments.keys.sorted().map { key in
            PaymentRow(id: key,
                       name: snapshot.players[key].name,
                       amount: result.payments[key] ?? 0)
        }
    }

    private var handColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("和牌")
                .font(.system(size: 12))
                .foregroundStyle(Theme.dimText)
            if let result {
                HStack(spacing: 3) {
                    ForEach(Array(result.hand.enumerated()), id: \.offset) { _, tile in
                        MahjongTileView(tile: tile, size: CGSize(width: 40, height: 54))
                    }
                }
                if !result.melds.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(result.melds, id: \.self) { meld in
                            HStack(spacing: 1) {
                                ForEach(0..<meld.tileCount, id: \.self) { _ in
                                    MahjongTileView(tile: meld.tile, size: CGSize(width: 30, height: 40))
                                }
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
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
        .frame(width: 360, alignment: .leading)
    }

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
