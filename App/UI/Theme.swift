import SwiftUI
import UIKit
import JianliCore

enum Theme {
    static let feltTop = Color(red: 0.085, green: 0.205, blue: 0.170)
    static let felt = Color(red: 0.045, green: 0.128, blue: 0.108)
    static let feltDeep = Color(red: 0.018, green: 0.062, blue: 0.054)

    static let gold = Color(red: 0.870, green: 0.745, blue: 0.475)
    static let goldDeep = Color(red: 0.640, green: 0.500, blue: 0.255)
    static let goldSoft = Color(red: 0.870, green: 0.745, blue: 0.475).opacity(0.28)

    static let ivoryTop = Color(red: 1.000, green: 0.988, blue: 0.950)
    static let ivoryBottom = Color(red: 0.868, green: 0.845, blue: 0.780)

    static let ink = Color(red: 0.125, green: 0.140, blue: 0.130)
    static let dimText = Color.white.opacity(0.55)
    static let panel = Color.white.opacity(0.06)
    static let danger = Color(red: 0.870, green: 0.360, blue: 0.300)

    /// 红中皮子专用色
    static let redDragon = Color(red: 0.72, green: 0.20, blue: 0.16)

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

// MARK: - 牌面素材

/// 用真实牌面 PNG（开源 CC0 素材 Pack：FluffyStuff/riichi-mahjong-tiles）铺在自绘牌身上
enum TileArt {
    static func assetName(_ tile: Tile) -> String {
        if tile.isRed { return "Chun" }
        let prefix: String
        switch tile.suit {
        case .wan: prefix = "Man"
        case .tong: prefix = "Pin"
        case .tiao: prefix = "Sou"
        case .red: prefix = "Chun"
        }
        return "\(prefix)\(tile.rank)"
    }

    static func image(_ tile: Tile) -> UIImage? { UIImage(named: assetName(tile)) }
}

// MARK: - 尺寸

struct Metrics {
    let size: CGSize

    /// 667×375 这一档（SE / 13 mini）单独收紧
    var isCompact: Bool { size.width < 720 }

    /// 牌高：随屏高定，最大 84，比上一版整体小一档
    var handTileHeight: CGFloat {
        floor(min(size.height * (isCompact ? 0.185 : 0.195), isCompact ? 70 : 84))
    }

    var handTile: CGSize {
        let h = handTileHeight
        return CGSize(width: floor(h * 0.72), height: h)
    }

    /// 手牌之间略带重叠，14 张一行放得下
    var handSpacing: CGFloat { -handTile.width * 0.10 }

    var riverTile: CGSize {
        let h = floor(handTileHeight * (isCompact ? 0.38 : 0.40))
        return CGSize(width: floor(h * 0.72), height: h)
    }

    var meldTile: CGSize {
        let h = floor(handTileHeight * 0.48)
        return CGSize(width: floor(h * 0.72), height: h)
    }

    var backTile: CGSize {
        let h = floor(handTileHeight * 0.58)
        return CGSize(width: floor(h * 0.72), height: h)
    }

    var sideBackTile: CGSize { backTile }

    var riverColumns: Int { isCompact ? 9 : 10 }
    var sideRiverRows: Int { isCompact ? 5 : 6 }

    var hubSide: CGFloat { floor(min(size.height * (isCompact ? 0.150 : 0.160), 68)) }

    var outer: CGFloat { isCompact ? 8 : 12 }
}

// MARK: - 单张牌

struct MahjongTileView: View {
    let tile: Tile
    let size: CGSize
    var lifted: Bool = false
    var highlighted: Bool = false
    /// 侧家牌河 / 牌背用 90 或 -90 把牌横过来
    var rotation: Double = 0

    private var corner: CGFloat { max(3, size.width * 0.13) }
    private var edge: CGFloat { max(1.5, size.height * 0.045) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        ZStack(alignment: .top) {
            // 牌身（下半截露出的厚度，做出实体感）
            shape
                .fill(LinearGradient(colors: [Color(red: 0.760, green: 0.735, blue: 0.660),
                                              Color(red: 0.640, green: 0.615, blue: 0.545)],
                                     startPoint: .top, endPoint: .bottom))
                .offset(y: edge)

            // 牌面
            shape
                .fill(LinearGradient(colors: [Theme.ivoryTop, Theme.ivoryBottom],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(
                    Group {
                        if let img = UIImage(named: TileArt.assetName(tile)) {
                            Image(uiImage: img)
                                .resizable()
                                .interpolation(.high)
                                .scaledToFit()
                        } else {
                            // 兜底：图加载失败时直接画文字，不会出现空白牌
                            if tile.isRed {
                                Text("中")
                                    .font(.system(size: size.height * 0.42, weight: .heavy, design: .serif))
                                    .foregroundStyle(Color(red: 0.69, green: 0.16, blue: 0.13))
                            } else {
                                VStack(spacing: 0) {
                                    Text(tile.numeral)
                                        .font(.system(size: size.height * 0.32, weight: .heavy, design: .serif))
                                        .foregroundStyle(tile.suit == .tiao ? Color(red: 0.10, green: 0.41, blue: 0.24)
                                                         : (tile.suit == .tong ? Color(red: 0.11, green: 0.29, blue: 0.45)
                                                            : Color(red: 0.13, green: 0.21, blue: 0.17)))
                                    Text(tile.suit.symbol)
                                        .font(.system(size: size.height * 0.20, weight: .bold, design: .serif))
                                        .foregroundStyle(tile.suit == .tiao ? Color(red: 0.10, green: 0.41, blue: 0.24)
                                                         : (tile.suit == .tong ? Color(red: 0.11, green: 0.29, blue: 0.45)
                                                            : Color(red: 0.13, green: 0.21, blue: 0.17)))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, size.width * 0.085)
                    .padding(.vertical, size.height * 0.075)
                )
                .overlay(
                    shape.strokeBorder(
                        highlighted ? Theme.gold : Color.black.opacity(0.13),
                        lineWidth: highlighted ? max(1.6, size.width * 0.045) : 0.6
                    )
                )
        }
        .frame(width: size.width, height: size.height + edge)
        .rotationEffect(.degrees(rotation))
        .rotationEffect(.degrees(0))
        .shadow(color: .black.opacity(0.45), radius: max(1.5, size.width * 0.075),
                x: 0, y: max(1, size.height * 0.055))
        .offset(y: lifted ? -size.height * 0.14 : 0)
        .animation(.spring(response: 0.26, dampingFraction: 0.80), value: lifted)
    }
}

struct TileBackView: View {
    let size: CGSize
    var rotation: Double = 0

    var body: some View {
        let corner = max(3, size.width * 0.13)
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        ZStack(alignment: .top) {
            shape
                .fill(LinearGradient(colors: [Color(red: 0.760, green: 0.735, blue: 0.660),
                                              Color(red: 0.620, green: 0.595, blue: 0.525)],
                                     startPoint: .top, endPoint: .bottom))
                .offset(y: max(1.5, size.height * 0.045))

            shape
                .fill(LinearGradient(colors: [Color(red: 0.115, green: 0.310, blue: 0.255),
                                              Color(red: 0.055, green: 0.185, blue: 0.155)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(
                    Canvas { context, canvasSize in
                        let inset: CGFloat = 2
                        let rect = CGRect(x: inset, y: inset,
                                          width: canvasSize.width - inset * 2,
                                          height: canvasSize.height - inset * 2)
                        context.stroke(Path(roundedRect: rect, cornerRadius: corner * 0.7),
                                       with: .color(.white.opacity(0.10)), lineWidth: 0.7)
                        let step = max(3, canvasSize.height * 0.12)
                        var y = -canvasSize.width
                        while y < canvasSize.height {
                            var path = Path()
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: canvasSize.width, y: y + canvasSize.width))
                            context.stroke(path, with: .color(.white.opacity(0.055)), lineWidth: 0.8)
                            y += step
                        }
                    }
                    .clipShape(shape)
                )
                .overlay(shape.strokeBorder(Color.black.opacity(0.20), lineWidth: 0.5))
        }
        .frame(width: size.width, height: size.height)
        .rotationEffect(.degrees(rotation))
        .shadow(color: .black.opacity(0.40), radius: max(1.5, size.width * 0.07),
                x: 0, y: max(1, size.height * 0.05))
    }
}

/// 对手手里的牌背：一排叠着，只露一条边
struct OpponentBacks: View {
    let count: Int
    let tile: CGSize
    var horizontal: Bool = true

    var body: some View {
        let overlap = horizontal ? tile.width * 0.42 : tile.height * 0.42
        let span = CGFloat(max(0, count - 1)) * overlap + (horizontal ? tile.width : tile.height)
        ZStack(alignment: horizontal ? .leading : .top) {
            ForEach(0..<max(0, count), id: \.self) { index in
                if horizontal {
                    TileBackView(size: tile)
                        .offset(x: CGFloat(index) * overlap)
                } else {
                    TileBackView(size: tile, rotation: 90)
                        .offset(y: CGFloat(index) * overlap)
                }
            }
        }
        .frame(width: horizontal ? span : tile.height,
               height: horizontal ? tile.height : span,
               alignment: horizontal ? .leading : .top)
    }
}
