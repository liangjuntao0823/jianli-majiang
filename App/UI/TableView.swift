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
                    table(snap, m, geo.size)
                    if snap.phase == .finished {
                        SettlementView(snapshot: snap)
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    }
                } else {
                    ProgressView().tint(Theme.gold)
                }
            }
        }
        .onChange(of: model.snapshot?.current) { _, _ in selectedIndex = nil }
    }

    // MARK: - 主布局

    private func table(_ snap: TableSnapshot, _ m: Metrics, _ size: CGSize) -> some View {
        let w = size.width
        let h = size.height
        let handH = m.handTile.height
        let topRiverTop = m.outer + 42 + m.backTile.height + 8

        return ZStack {
            // 上家：名牌 + 牌背
            VStack(spacing: 5) {
                plate(snap.players[seat(.north).rawValue], snap: snap, m: m, align: .center)
                OpponentBacks(count: snap.players[seat(.north).rawValue].handCount, tile: m.backTile)
            }
            .position(x: w / 2, y: m.outer + 32)

            // 上家牌河
            riverBlock(snap.players[seat(.north).rawValue], m: m)
                .position(x: w / 2, y: topRiverTop + riverBlockHeight(m, rows: 2) / 2)

            // 左右两家
            sideSeat(snap.players[seat(.west).rawValue], snap: snap, m: m, trailing: false)
                .position(x: m.outer + m.backTile.height * 0.55, y: h / 2)
            sideSeat(snap.players[seat(.east).rawValue], snap: snap, m: m, trailing: true)
                .position(x: w - m.outer - m.backTile.height * 0.55, y: h / 2)

            // 中央牌墙
            hub(snap, m: m)
                .position(x: w / 2, y: h / 2)

            // 我的牌河
            riverBlock(snap.me, m: m)
                .position(x: w / 2,
                          y: h - m.outer - handH - 18 - riverBlockHeight(m, rows: 2) / 2)

            myArea(snap, m: m, size: size)
            actionPad(snap, m: m, size: size)

            if snap.phase != .finished {
                statusStrip(snap, m: m, size: size)
            }
        }
    }

    // MARK: - 背景

    private struct FeltBackground: View {
        var body: some View {
            ZStack {
                LinearGradient(colors: [Theme.feltTop, Theme.felt, Theme.feltDeep],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [Color.white.opacity(0.09), .clear],
                               center: .center, startRadius: 6, endRadius: 340)
                Rectangle()
                    .strokeBorder(Theme.gold.opacity(0.14), lineWidth: 1)
                    .padding(5)
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - 中央

    private func hub(_ snap: TableSnapshot, m: Metrics) -> some View {
        let side = m.hubSide
        return ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color.black.opacity(0.26), Color.black.opacity(0.10)],
                                     center: .center, startRadius: 2, endRadius: side))
            Circle().strokeBorder(Theme.gold.opacity(0.30), lineWidth: 1)
            Circle().strokeBorder(Theme.gold.opacity(0.10), lineWidth: 1).padding(7)

            Text("\(snap.wallRemaining)")
                .font(.system(size: side * 0.36, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.gold)
                .offset(y: -side * 0.10)

            Text("张")
                .font(.system(size: side * 0.14))
                .foregroundStyle(Theme.dimText)
                .offset(y: side * 0.14)

            Text("\(snap.dealer.label)庄 · \(snap.roundIndex)/\(snap.totalRounds)")
                .font(.system(size: side * 0.135))
                .foregroundStyle(Theme.dimText.opacity(0.9))
                .offset(y: side * 0.34)
        }
        .frame(width: side, height: side)
    }

    // MARK: - 左右两家

    private func sideSeat(_ view: SeatView, snap: TableSnapshot, m: Metrics, trailing: Bool) -> some View {
        VStack(spacing: 6) {
            plate(view, snap: snap, m: m, align: trailing ? .trailing : .leading)
            SideBacks(count: view.handCount, tile: m.backTile)
            Spacer(minLength: 0)
        }
        .frame(height: 300, alignment: .top)
    }

    private struct SideBacks: View {
        let count: Int
        let tile: CGSize
        var body: some View {
            let step = max(4, tile.width * 0.44)
            let span = step * CGFloat(max(0, count - 1)) + tile.width
            ZStack(alignment: .top) {
                ForEach(0..<max(0, count), id: \.self) { index in
                    TileBackView(size: CGSize(width: tile.width * 1.4, height: tile.width),
                                 rotation: 90)
                        .frame(width: tile.width, height: tile.width)
                        .offset(y: CGFloat(index) * step)
                }
            }
            .frame(width: tile.width, height: span + 6, alignment: .top)
        }
    }

    // MARK: - 牌河

    private func riverBlockHeight(_ m: Metrics, rows: Int) -> CGFloat {
        CGFloat(rows) * (m.riverTile.height + 2) + 4
    }

    private func riverBlock(_ view: SeatView, m: Metrics) -> some View {
        let columns = m.riverColumns
        let maxRows = 3
        let visible = Array(view.river.suffix(columns * maxRows))
        let rows = min(maxRows, max(1, (visible.count + columns - 1) / max(columns, 1)))
        return VStack(spacing: 2) {
            ForEach(0..<rows, id: \.self) { rowIndex in
                HStack(spacing: 2) {
                    ForEach(0..<columns, id: \.self) { col in
                        let index = rowIndex * columns + col
                        if index < visible.count {
                            MahjongTileView(tile: visible[index], size: m.riverTile)
                        } else {
                            Color.clear
                                .frame(width: m.riverTile.width, height: m.riverTile.height)
                        }
                    }
                }
            }
        }
        .frame(width: CGFloat(columns) * (m.riverTile.width + 2),
               height: riverBlockHeight(m, rows: max(rows, 1)),
               alignment: .bottom)
    }

    // MARK: - 自己

    private func myArea(_ snap: TableSnapshot, m: Metrics, size: CGSize) -> some View {
        let handH = m.handTile.height
        let bottom = size.height - m.outer
        return ZStack {
            handRow(snap, m: m)
                .position(x: size.width / 2, y: bottom - handH / 2)

            meldColumn(snap, m: m)
                .position(x: size.width - m.outer - m.meldTile.width * 2.6,
                          y: bottom - handH / 2)

            plate(snap.me, snap: snap, m: m, align: .leading)
                .position(x: m.outer + 56, y: bottom - handH - 30)
        }
    }

    private func handRow(_ snap: TableSnapshot, m: Metrics) -> some View {
        var display = snap.me.hand
        var drawn: Tile?
        if snap.canDiscard, let last = snap.lastDrawn, let idx = display.lastIndex(of: last) {
            display.remove(at: idx)
            drawn = last
        }

        return HStack(spacing: m.handSpacing) {
            ForEach(Array(display.enumerated()), id: \.offset) { index, tile in
                MahjongTileView(tile: tile,
                                size: m.handTile,
                                lifted: selectedIndex == index,
                                highlighted: selectedIndex == index)
                    .onTapGesture { tap(tile: tile, index: index, snap: snap) }
            }
            if let drawn {
                MahjongTileView(tile: drawn, size: m.handTile, highlighted: true)
                    .padding(.leading, 14)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .opacity))
                    .onTapGesture {
                        guard snap.canDiscard else { return }
                        model.discard(drawn)
                        selectedIndex = nil
                    }
            }
        }
        .animation(.spring(response: 0.26, dampingFraction: 0.86), value: display.count)
    }

    private func tap(tile: Tile, index: Int, snap: TableSnapshot) {
        guard snap.canDiscard else { return }
        if selectedIndex == index {
            model.discard(tile)
            selectedIndex = nil
        } else {
            selectedIndex = index
            Sound.play(.draw)
        }
    }

    private func meldColumn(_ snap: TableSnapshot, m: Metrics) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            if snap.me.redsPlayed > 0 {
                HStack(spacing: 2) {
                    ForEach(0..<snap.me.redsPlayed, id: \.self) { _ in
                        MahjongTileView(tile: Tile(.red, 0), size: m.meldTile)
                    }
                }
            }
            ForEach(snap.me.melds, id: \.self) { meld in
                HStack(spacing: 1) {
                    ForEach(0..<meld.tileCount, id: \.self) { _ in
                        MahjongTileView(tile: meld.tile, size: m.meldTile)
                    }
                }
            }
        }
        .frame(width: m.meldTile.width * 4.4, alignment: .trailing)
    }

    // MARK: - 名牌

    private func plate(_ view: SeatView, snap: TableSnapshot, m: Metrics, align: HorizontalAlignment) -> some View {
        let isTurn = snap.current == view.seat && snap.phase != .finished
        let total = max(1, Double(snap.playSeconds))
        let ratio = min(1, max(0, Double(model.secondsLeft) / total))
        return VStack(alignment: align, spacing: 3) {
            HStack(spacing: 5) {
                Text(view.seat.label)
                    .font(.system(size: 10, weight: .semibold, design: .serif))
                    .foregroundStyle(Theme.gold.opacity(0.85))
                    .frame(width: 14, height: 14)
                    .background(Circle().fill(Theme.gold.opacity(0.12)))
                Text(view.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.90))
                    .lineLimit(1)
                if view.isBot {
                    badge("机器人", color: Theme.dimText)
                } else if !view.connected {
                    badge("离线", color: Theme.danger)
                }
                if view.redsPlayed > 0 {
                    badge("皮\(view.redsPlayed)", color: Theme.gold.opacity(0.9))
                }
            }
            HStack(spacing: 5) {
                Text(view.score >= 0 ? "+\(view.score)" : "\(view.score)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(view.score >= 0 ? Theme.gold : Theme.danger)
                if isTurn {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.14))
                            Capsule()
                                .fill(model.secondsLeft <= 10 ? Theme.danger : Theme.gold)
                                .frame(width: g.size.width * ratio)
                        }
                    }
                    .frame(width: 44, height: 3)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.black.opacity(isTurn ? 0.32 : 0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(isTurn ? Theme.gold.opacity(0.50) : Color.white.opacity(0.07),
                                      lineWidth: 0.8)
                )
        )
        .fixedSize()
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 8.5, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.14)))
    }

    // MARK: - 底部状态条

    private func statusStrip(_ snap: TableSnapshot, m: Metrics, size: CGSize) -> some View {
        let text: String = {
            if selectedIndex != nil { return "再点一次打出" }
            if snap.canDiscard {
                if !snap.waitingTiles.isEmpty {
                    return "听 " + snap.waitingTiles.map { "\($0.label)(剩\(remaining($0, snap)))" }
                        .joined(separator: " · ")
                }
                return "点牌选中，再点打出"
            }
            if snap.phase == .awaitingClaim {
                return snap.claimOptions.isEmpty ? "等其他人表态…" : "请选择碰 / 杠 / 过"
            }
            return "\(snap.players[snap.current.rawValue].name) 出牌中"
        }()

        return HStack(spacing: 6) {
            if snap.lastDrawnFromTail, snap.lastDrawn != nil, snap.canDiscard {
                Text("尾补")
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Theme.gold.opacity(0.18)))
                    .foregroundStyle(Theme.gold)
            }
            Text(text)
                .font(.system(size: m.isCompact ? 9.5 : 10.5, weight: .medium))
                .foregroundStyle(snap.waitingTiles.isEmpty || !snap.canDiscard ? Theme.dimText : Theme.gold)
                .lineLimit(1)
            Spacer(minLength: 0)
            if model.secondsLeft > 0, snap.current == model.mySeat {
                Text("\(model.secondsLeft)s")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(model.secondsLeft <= 10 ? Theme.danger : Theme.gold)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(width: size.width * 0.42)
        .background(Capsule().fill(Color.black.opacity(0.26)))
        .position(x: size.width / 2, y: m.outer + 14)
    }

    private func remaining(_ tile: Tile, _ snap: TableSnapshot) -> Int {
        var seen = snap.me.hand.filter { $0 == tile }.count
        for player in snap.players {
            seen += player.river.filter { $0 == tile }.count
            seen += player.melds.filter { $0.tile == tile }.reduce(0) { $0 + $1.tileCount }
        }
        return max(0, 4 - seen)
    }

    // MARK: - 操作

    private struct ActionItem {
        let title: String
        let primary: Bool
        let action: () -> Void
    }

    private func actionPad(_ snap: TableSnapshot, m: Metrics, size: CGSize) -> some View {
        let items = actions(snap)
        return VStack(spacing: 8) {
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
                Button(action: item.action) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .bold, design: .serif))
                        .foregroundStyle(item.primary ? Theme.feltDeep : Color.white.opacity(0.92))
                        .frame(width: 54, height: 54)
                        .background(
                            Circle()
                                .fill(item.primary
                                      ? AnyShapeStyle(LinearGradient(colors: [Theme.gold, Theme.goldDeep],
                                                                     startPoint: .top, endPoint: .bottom))
                                      : AnyShapeStyle(Color.black.opacity(0.34)))
                                .overlay(Circle().strokeBorder(
                                    item.primary ? Color.white.opacity(0.22) : Color.white.opacity(0.16),
                                    lineWidth: 1))
                        )
                        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                }
                .buttonStyle(.plain)
            }
        }
        .position(x: size.width - 42, y: size.height - 120)
    }

    private func actions(_ snap: TableSnapshot) -> [ActionItem] {
        var items: [ActionItem] = []
        if snap.phase == .finished { return items }
        if snap.canDiscard, snap.canHu {
            items.append(ActionItem(title: "胡", primary: true) { model.declareHu() })
        }
        if snap.claimOptions.contains(.peng) {
            items.append(ActionItem(title: "碰", primary: true) { model.declareClaim(.peng) })
        }
        if snap.claimOptions.contains(.gang) {
            items.append(ActionItem(title: "杠", primary: true) { model.declareClaim(.gang) })
        }
        if !snap.gangConcealedOptions.isEmpty, snap.canDiscard {
            items.append(ActionItem(title: "暗杠", primary: false) {
                if let tile = snap.gangConcealedOptions.first { model.declareConcealedGang(tile) }
            })
        }
        if !snap.gangAddedOptions.isEmpty, snap.canDiscard {
            items.append(ActionItem(title: "补杠", primary: false) {
                if let tile = snap.gangAddedOptions.first { model.declareAddedGang(tile) }
            })
        }
        if snap.claimOptions.contains(.peng) || snap.claimOptions.contains(.gang) {
            items.append(ActionItem(title: "过", primary: false) { model.declareClaim(.pass) })
        }
        return items
    }

    // MARK: - 座位换算

    private enum ScreenSide { case south, east, north, west }

    /// 以“我”为基准把绝对座位换算成屏幕方位
    private func seat(_ side: ScreenSide) -> Seat {
        let base = model.mySeat.rawValue
        switch side {
        case .south: return Seat(rawValue: base)!
        case .east: return Seat(rawValue: (base + 1) % 4)!
        case .north: return Seat(rawValue: (base + 2) % 4)!
        case .west: return Seat(rawValue: (base + 3) % 4)!
        }
    }
}
