import SwiftUI
import JianliCore

struct FeltBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.feltTop, Theme.felt, Theme.feltDeep],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color.white.opacity(0.07), .clear],
                           center: .init(x: 0.5, y: 0.38), startRadius: 10, endRadius: 620)
            Canvas { context, size in
                var x = -size.height
                while x < size.width {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: size.height))
                    path.addLine(to: CGPoint(x: x + size.height, y: 0))
                    context.stroke(path, with: .color(.white.opacity(0.018)), lineWidth: 1)
                    x += 46
                }
            }
        }
        .ignoresSafeArea()
    }
}

struct GoldButton: View {
    let title: String
    var subtitle: String? = nil
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .opacity(0.75)
                }
            }
            .foregroundStyle(enabled ? Theme.feltDeep : Color.white.opacity(0.35))
            .frame(width: 240, height: subtitle == nil ? 54 : 64)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(enabled ? LinearGradient(colors: [Theme.gold, Theme.gold.opacity(0.82)],
                                                   startPoint: .top, endPoint: .bottom)
                                  : LinearGradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0.06)],
                                                   startPoint: .top, endPoint: .bottom))
            )
            .shadow(color: enabled ? Theme.gold.opacity(0.35) : .clear, radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

struct GhostButton: View {
    let title: String
    var width: CGFloat = 240
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(enabled ? Color.white.opacity(0.86) : Color.white.opacity(0.3))
                .frame(width: width, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.panel)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

struct RuleChip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.gold.opacity(0.92))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(Theme.gold.opacity(0.10))
                    .overlay(Capsule().strokeBorder(Theme.gold.opacity(0.28), lineWidth: 1))
            )
    }
}

struct HomeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        GeometryReader { geo in
            let m = Metrics(size: geo.size)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("监利红中")
                        .font(.system(size: min(66, geo.size.height * 0.17), weight: .black, design: .serif))
                        .foregroundStyle(Theme.ivoryTop)
                        .tracking(4)
                    Text("局域网四人麻将")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.gold)
                        .tracking(6)
                        .padding(.top, 6)

                    HStack(spacing: 8) {
                        RuleChip(text: "112 张")
                        RuleChip(text: "红中为皮子")
                        RuleChip(text: "只能自摸")
                        RuleChip(text: "四家同桌")
                    }
                    .padding(.top, 18)

                    Spacer(minLength: 8)

                    HStack(spacing: -14) {
                        ForEach(Array(fanTiles.enumerated()), id: \.offset) { index, tile in
                            MahjongTileView(tile: tile, size: m.handTile)
                                .rotationEffect(.degrees(Double(index) * 5 - 10))
                                .offset(y: CGFloat(abs(index - 2)) * 8)
                        }
                    }
                    .opacity(0.96)

                    Spacer(minLength: 4)

                    Text("同一 Wi-Fi 下开房，不用服务器、不用账号、不连公网")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dimText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 56)
                .padding(.vertical, 26)

                VStack(spacing: 12) {
                    GoldButton(title: "创建房间", subtitle: "我来当房主") {
                        model.createRoom()
                    }
                    GhostButton(title: "加入房间") {
                        model.beginJoining()
                    }
                    HStack(spacing: 10) {
                        GhostButton(title: "单机练习", width: 115) {
                            model.startSolo()
                        }
                        GhostButton(title: "规则说明", width: 115) {
                            model.showRules()
                        }
                    }
                    .frame(width: 240)
                }
                .padding(.trailing, 56)
            }
        }
    }

    private var fanTiles: [Tile] {
        [Tile(.wan, 1), Tile(.tong, 5), Tile(.tiao, 9), Tile(.wan, 3), Tile(.red, 0)]
    }
}
