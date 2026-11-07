import SwiftUI
import Foundation
import JianliCore

enum Theme {
    static let feltTop = Color(red: 0.075, green: 0.185, blue: 0.155)
    static let felt = Color(red: 0.048, green: 0.135, blue: 0.115)
    static let feltDeep = Color(red: 0.022, green: 0.075, blue: 0.065)

    static let gold = Color(red: 0.855, green: 0.715, blue: 0.435)
    static let goldSoft = Color(red: 0.855, green: 0.715, blue: 0.435).opacity(0.30)

    static let ivoryTop = Color(red: 0.995, green: 0.975, blue: 0.925)
    static let ivoryBottom = Color(red: 0.895, green: 0.865, blue: 0.780)

    static let ink = Color(red: 0.125, green: 0.140, blue: 0.130)
    static let dimText = Color.white.opacity(0.52)
    static let panel = Color.white.opacity(0.055)
    static let danger = Color(red: 0.80, green: 0.27, blue: 0.22)

    static func suit(_ suit: TileSuit) -> Color { Color(hex: suit.hexColor) }
}

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// 横屏尺寸适配：以 iPhone 16 Pro Max 横屏（932×430pt）为设计基准，
/// 小屏（874×402、852×393）按比例收缩，最小可到 667×375 也不挤爆。
struct Metrics {
    let size: CGSize

    var scale: CGFloat { min(size.width / 932, size.height / 430) }

    /// iPhone SE / 13 mini 这一档：667×375 横屏，单独一版压缩规则
    var isCompact: Bool { size.width < 700 }

    /// 底部自己手牌：优先保证 14 张不换行、不再缩
    var handTile: CGSize {
        let widthLimit = (size.width - (isCompact ? 40 : 56)) / 14
        let width = min(widthLimit, size.height * (isCompact ? 0.215 : 0.205))
        return CGSize(width: floor(width), height: floor(width * 4 / 3))
    }

    var riverTile: CGSize {
        let w = floor(handTile.width * 0.60)
        return CGSize(width: w, height: floor(w * 4 / 3))
    }

    var sideTile: CGSize {
        let w = floor(handTile.width * 0.38)
        return CGSize(width: w, height: floor(w * 4 / 3))
    }

    var topBackTile: CGSize {
        let w = floor(handTile.width * (isCompact ? 0.46 : 0.52))
        return CGSize(width: w, height: floor(w * 4 / 3))
    }

    var handAreaHeight: CGFloat { handTile.height + (isCompact ? 28 : 34) }
    var topAreaHeight: CGFloat { topBackTile.height + (isCompact ? 24 : 30) }
}

// MARK: - 牌

struct MahjongTileView: View {
    let tile: Tile
    let size: CGSize
    var lifted: Bool = false
    var highlighted: Bool = false

    private var corner: CGFloat { max(4, size.width * 0.15) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(LinearGradient(colors: [Theme.ivoryTop, Theme.ivoryBottom],
                                     startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(highlighted ? Theme.gold : Color.black.opacity(0.16),
                              lineWidth: highlighted ? max(1.5, size.width * 0.035) : 0.7)
            face
        }
        .frame(width: size.width, height: size.height)
        .shadow(color: .black.opacity(0.42), radius: size.width * 0.09, x: 0, y: size.height * 0.05)
        .offset(y: lifted ? -size.height * 0.13 : 0)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: lifted)
    }

    @ViewBuilder
    private var face: some View {
        if tile.isRed {
            Text("中")
                .font(.system(size: size.width * 0.72, weight: .black, design: .serif))
                .foregroundStyle(Theme.suit(.red))
                .minimumScaleFactor(0.4)
                .padding(.bottom, size.height * 0.02)
        } else {
            VStack(spacing: -size.height * 0.035) {
                Text(tile.numeral)
                    .font(.system(size: size.width * 0.44, weight: .bold, design: .serif))
                    .foregroundStyle(Theme.suit(tile.suit))
                Text(tile.symbol)
                    .font(.system(size: size.width * 0.40, weight: .semibold, design: .serif))
                    .foregroundStyle(Theme.suit(tile.suit).opacity(0.92))
            }
            .minimumScaleFactor(0.4)
            .lineLimit(1)
        }
    }
}

struct TileBackView: View {
    let size: CGSize
    var body: some View {
        RoundedRectangle(cornerRadius: max(3, size.width * 0.13), style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.10, green: 0.28, blue: 0.24),
                                          Color(red: 0.06, green: 0.19, blue: 0.16)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
                Canvas { context, canvasSize in
                    let step = canvasSize.width * 0.30
                    var offset = -canvasSize.height
                    while offset < canvasSize.width + canvasSize.height {
                        var path = Path()
                        path.move(to: CGPoint(x: offset, y: canvasSize.height))
                        path.addLine(to: CGPoint(x: offset + canvasSize.height, y: 0))
                        context.stroke(path, with: .color(.white.opacity(0.07)), lineWidth: 1)
                        offset += step
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: max(3, size.width * 0.13), style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: max(3, size.width * 0.13), style: .continuous)
                    .strokeBorder(Theme.gold.opacity(0.28), lineWidth: 0.8)
            )
            .frame(width: size.width, height: size.height)
            .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
    }
}

/// 侧家牌背：竖着叠起来，只露一条边，省高度
struct SideHandView: View {
    let count: Int
    let tile: CGSize
    let vertical: Bool
    var body: some View {
        let overlap = tile.height * 0.30
        let total = vertical ? CGFloat(count) * overlap + (tile.height - overlap)
                            : CGFloat(count) * (tile.width * 0.34)
        ZStack(alignment: vertical ? .top : .leading) {
            ForEach(0..<max(0, count), id: \.self) { index in
                if vertical {
                    TileBackView(size: tile)
                        .offset(y: CGFloat(index) * overlap)
                } else {
                    TileBackView(size: tile)
                        .offset(x: CGFloat(index) * tile.width * 0.34)
                }
            }
        }
        .frame(width: vertical ? tile.width : total,
               height: vertical ? total : tile.height)
    }
}
