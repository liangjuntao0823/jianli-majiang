import SwiftUI
import JianliCore

struct TableView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedIndex: Int?

    var body: some View {
        GeometryReader { geo in
            let m = Metrics(size: geo.size)
            ZStack {
                FeltBackground()

                if let snap = model.snapshot {
                    VStack(spacing: 0) {
                        topBar(snap, m)
                        middleArea(snap, m)
                        bottomArea(snap, m)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)

                    actionOverlay(snap, m)

                    if snap.phase == .finished {
                        SettlementView(snapshot: snap)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                } else {
                    ProgressView().tint(Theme.gold)
                }
            }
        }
        .onChange(of: model.snapshot?.current) { _, _ in selectedIndex = nil }
    }

    // MARK: - 顶部：对家

    private func topBar(_ snap: TableSnapshot, _ m: Metrics) -> some View {
        let seat = opposite
        let view = snap.players[seat.rawValue]
        return HStack(spacing: 10) {
            namePlate(view, snap: snap, compact: true)
            Spacer(minLength: 8)
            HStack(spacing: -m.topBackTile.width * 0.55) {
                ForEach(0..<view.handCount, id: \.self) { _ in
                    TileBackView(size: m.topBackTile)
                }
                ForEach(view.melds, id: \.self) { meld in
                    meldView(meld, size: m.riverTile, highlight: false)
                        .padding(.leading, 4)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text("第 \(snap.roundIndex)/\(snap.totalRounds) 局")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.dimText)
                wallBadge(snap, m)
            }
        }
        .frame(height: m.topAreaHeight)
    }

    // MARK: - 中部：左右家 + 牌河

    private func middleArea(_ snap: TableSnapshot, _ m: Metrics) -> some View {
        HStack(spacing: 6) {
            sideColumn(snap, seat: leftSeat, m: m)
            centerRivers(snap, m)
            sideColumn(snap, seat: rightSeat, m: m)
        }
        .frame(maxHeight: .infinity)
    }

    private func sideColumn(_ snap: TableSnapshot, seat: Seat, m: Metrics) -> some View {
        let view = snap.players[seat.rawValue]
        return VStack(spacing: 6) {
            namePlate(view, snap: snap, compact: false)
            SideHandView(count: view.handCount, tile: m.sideTile, vertical: true)
            Spacer(minLength: 0)
            VStack(spacing: 2) {
                ForEach(view.melds, id: \.self) { meld in
                    meldView(meld, size: CGSize(width: m.riverTile.width * 0.9, height: m.riverTile.height * 0.9), highlight: false)
                }
            }
        }
        .frame(width: m.handTile.width * 1.25)
    }

    private func centerRivers(_ snap: TableSnapshot, _ m: Metrics) -> some View {
        VStack(spacing: 4) {
            riverRow(tiles: snap.players[opposite.rawValue].river, columns: 9, m: m)
            Spacer(minLength: 2)
            riverRow(tiles: snap.players[model.mySeat.rawValue].river, columns: 9, m: m)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func riverRow(tiles: [Tile], columns: Int, m: Metrics) -> some View {
        let rows = stride(from: 0, to: tiles.count, by: columns).map { start in
            Array(tiles[start..<min(start + columns, tiles.count)])
        }
        return VStack(spacing: 2) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 2) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, tile in
                        MahjongTileView(tile: tile, size: m.riverTile)
                            .rotationEffect(.degrees(tile.isRed ? 0 : 0))
                            .opacity(0.96)
                    }
                }
            }
        }
    }

    // MARK: - 底部：我的手牌与操作

    private func bottomArea(_ snap: TableSnapshot, _ m: Metrics) -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 6) {
                namePlate(snap.me, snap: snap, compact: false)
                handRow(snap, m)
                meldStrip(snap, m)
            }
            hintRow(snap)
        }
        .frame(height: m.handAreaHeight + 16)
    }

    private func handRow(_ snap: TableSnapshot, _ m: Metrics) -> some View {
        HStack(spacing: m.handTile.width * 0.045) {
            ForEach(Array(snap.me.hand.enumerated()), id: \.offset) { index, tile in
                MahjongTileView(tile: tile,
                                size: m.handTile,
                                lifted: selectedIndex == index,
                                highlighted: snap.lastDrawn == tile && index == snap.me.hand.count - 1)
                    .opacity(selectedIndex == index ? 1 : 0.985)
                    .onTapGesture {
                        guard snap.canDiscard else { return }
                        if selectedIndex == index {
                            model.discard(tile)
                            selectedIndex = nil
                        } else {
                            selectedIndex = index
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func meldStrip(_ snap: TableSnapshot, _ m: Metrics) -> some View {
        HStack(spacing: 4) {
            ForEach(snap.me.melds, id: \.self) { meld in
                meldView(meld, size: CGSize(width: m.riverTile.width * 0.92,
                                            height: m.riverTile.height * 0.92),
                         highlight: false)
            }
        }
    }

    private func hintRow(_ snap: TableSnapshot) -> some View {
        HStack(spacing: 8) {
            if !snap.waitingTiles.isEmpty, snap.canDiscard {
                Text("听 " + snap.waitingTiles.map(\.label).joined(separator: " · "))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.gold)
            }
            if snap.me.redsPlayed > 0 {
                Text("已打红中 \(snap.me.redsPlayed) 张 · 本局 ×\(1 << snap.me.redsPlayed)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dimText)
            }
            Spacer()
            if snap.canDiscard {
                Text("点一下抬牌，再点一下打出")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.dimText)
            }
        }
        .frame(height: 14)
    }

    // MARK: - 浮层：操作按钮

    private func actionOverlay(_ snap: TableSnapshot, _ m: Metrics) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    if snap.canDiscard && snap.canHu {
                        actionButton("胡", emphasized: true) { model.declareHu() }
                    }
                    if snap.claimOptions.contains(.peng) {
                        actionButton("碰", emphasized: true) { model.declareClaim(.peng) }
                    }
                    if snap.claimOptions.contains(.gang) {
                        actionButton("杠", emphasized: true) { model.declareClaim(.gang) }
                    }
                    if !snap.gangConcealedOptions.isEmpty, snap.canDiscard {
                        actionButton("暗杠", emphasized: false) {
                            if let tile = snap.gangConcealedOptions.first { model.declareConcealedGang(tile) }
                        }
                    }
                    if !snap.gangAddedOptions.isEmpty, snap.canDiscard {
                        actionButton("补杠", emphasized: false) {
                            if let tile = snap.gangAddedOptions.first { model.declareAddedGang(tile) }
                        }
                    }
                    if snap.claimOptions.contains(.peng) || snap.claimOptions.contains(.gang) {
                        actionButton("过", emphasized: false) { model.declareClaim(.pass) }
                    }
                }
                .padding(.trailing, 6)
                .padding(.bottom, 6)
            }
        }
    }

    private func actionButton(_ title: String, emphasized: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .bold, design: .serif))
                .foregroundStyle(emphasized ? Theme.feltDeep : Color.white.opacity(0.9))
                .frame(width: 58, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(emphasized ? Theme.gold : Color.white.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(emphasized ? 0 : 0.18), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 常驻信息

    private func wallBadge(_ snap: TableSnapshot, _ m: Metrics) -> some View {
        VStack(spacing: 1) {
            Text("\(snap.wallRemaining)")
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.gold)
            Text("剩余")
                .font(.system(size: 9))
                .foregroundStyle(Theme.dimText)
        }
        .frame(width: 58, height: 42)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.panel)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.gold.opacity(0.22), lineWidth: 1))
        )
    }

    private func namePlate(_ view: SeatView, snap: TableSnapshot, compact: Bool) -> some View {
        let isTurn = snap.current == view.seat && snap.phase != .finished
        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(view.seat.label + "家")
                    .font(.system(size: compact ? 10 : 11, weight: .semibold))
                    .foregroundStyle(isTurn ? Theme.gold : Theme.dimText)
                Text(view.name)
                    .font(.system(size: compact ? 11 : 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.88))
            }
            HStack(spacing: 4) {
                Text(scoreText(view.score))
                    .font(.system(size: compact ? 11 : 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(view.score >= 0 ? Theme.gold.opacity(0.95) : Color(red: 0.93, green: 0.55, blue: 0.48))
                if view.redsPlayed > 0 {
                    Text("皮\(view.redsPlayed)")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.dimText)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isTurn ? Theme.gold.opacity(0.12) : Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isTurn ? Theme.gold.opacity(0.55) : Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private func meldView(_ meld: Meld, size: CGSize, highlight: Bool) -> some View {
        HStack(spacing: 1) {
            ForEach(0..<meld.tileCount, id: \.self) { index in
                MahjongTileView(tile: meld.tile, size: size,
                                lifted: meld.kind == .gangConcealed && index == 0,
                                highlighted: highlight)
            }
        }
    }

    private func scoreText(_ score: Int) -> String {
        score >= 0 ? "+\(score)" : "\(score)"
    }

    // MARK: - 方位

    private var opposite: Seat { Seat(rawValue: (model.mySeat.rawValue + 2) % 4)! }
    private var rightSeat: Seat { Seat(rawValue: (model.mySeat.rawValue + 1) % 4)! }
    private var leftSeat: Seat { Seat(rawValue: (model.mySeat.rawValue + 3) % 4)! }
}
