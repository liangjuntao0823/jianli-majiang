import SwiftUI
import UIKit
import JianliCore

struct RoomView: View {
    @EnvironmentObject private var model: AppModel
    @State private var manualHost: String = ""

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                leftPanel(width: geo.size.width * 0.46)
                rightPanel
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 20)
        }
    }

    private func leftPanel(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.roomMode == .host ? "房号" : "房间")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dimText)
                    Text(model.roomInfo?.code ?? "----")
                        .font(.system(size: 34, weight: .black, design: .monospaced))
                        .foregroundStyle(Theme.gold)
                }
                if model.roomMode == .host {
                    Button {
                        UIPasteboard.general.string = model.roomInfo?.code
                        model.toast = "房号已复制"
                    } label: {
                        Text("复制")
                            .font(.system(size: 11))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(Theme.panel))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(model.isOnline ? Color.green.opacity(0.75) : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(model.statusLine)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dimText)
                }
            }

            if model.roomMode == .client && model.slots.allSatisfy({ !$0.isMine }) {
                discoveredList
            } else {
                seatGrid
            }
            connectionHelper

            Spacer(minLength: 0)

            Text(model.roomMode == .host
                 ? "让朋友连同一个 Wi-Fi，打开 App 点「加入房间」，会自动看到你这个房间。"
                 : "正在通过 Bonjour 发现局域网内的房间，连不上时可以让房主把房号念给你。")
                .font(.system(size: 11))
                .foregroundStyle(Theme.dimText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: width, alignment: .leading)
        .padding(.trailing, 24)
    }

    /// 房主给 IP，客人可手填；顺带解释「为什么搜不到」
    private var connectionHelper: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.roomMode == .host {
                HStack(spacing: 8) {
                    Text("直连地址")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.dimText)
                    Text(model.localIP.isEmpty ? "未获取到 Wi-Fi 地址" : "\(model.localIP):\(LanHost.port)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(model.localIP.isEmpty ? Theme.dimText : Theme.gold.opacity(0.9))
                    if !model.localIP.isEmpty {
                        Button {
                            UIPasteboard.general.string = "\(model.localIP):\(LanHost.port)"
                            model.toast = "地址已复制"
                        } label: {
                            Text("复制")
                                .font(.system(size: 10))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(Theme.panel))
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    TextField("房主屏幕上的 IP", text: $manualHost)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 160)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.07)))
                    Button {
                        model.manualJoin(hostIP: manualHost)
                    } label: {
                        Text("直连")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.feltDeep)
                            .padding(.horizontal, 14).padding(.vertical, 5)
                            .background(Capsule().fill(Theme.gold))
                    }
                    .buttonStyle(.plain)
                    Button {
                        model.beginJoining()
                    } label: {
                        Text("重新扫描")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.75))
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("搜不到房间：确认四台设备在同一 Wi-Fi；如果连的是咖啡店或酒店网络，多半开了「客户端隔离」，改成房主手机开热点即可。首次连接会弹「本地网络」权限，点允许。")
                .font(.system(size: 9))
                .foregroundStyle(Theme.dimText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var seatGrid: some View {
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(0..<4, id: \.self) { index in
                seatCard(index)
            }
        }
    }

    private func seatCard(_ index: Int) -> some View {
        let slot = model.slots.first(where: { $0.seat.rawValue == index })
        return HStack(spacing: 10) {
            ZStack {
                Circle().fill(slot == nil ? Theme.panel : Theme.gold.opacity(0.16))
                    .frame(width: 34, height: 34)
                Text(Seat(rawValue: index)?.label ?? "?")
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(slot == nil ? Theme.dimText : Theme.gold)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(slot?.name ?? "空位")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(slot == nil ? Theme.dimText : .white.opacity(0.9))
                Text(slotStatus(slot))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.dimText)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(slot == nil ? Color.white.opacity(0.03) : Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(index == model.mySeat.rawValue ? Theme.gold.opacity(0.45) : Color.white.opacity(0.08),
                                      lineWidth: 1)
                )
        )
    }

    private func slotStatus(_ slot: SlotInfo?) -> String {
        guard let slot else { return "等待加入" }
        if slot.isBot { return "电脑补位" }
        if slot.isMine { return "我 · \(slot.seat.label)家" }
        return slot.connected ? "已入座 · \(slot.seat.label)家" : "掉线中"
    }

    private var discoveredList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("发现的房间")
                .font(.system(size: 12))
                .foregroundStyle(Theme.dimText)
            if model.discovered.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.6)
                    Text("正在扫描局域网…").font(.system(size: 12)).foregroundStyle(Theme.dimText)
                }
                .padding(.vertical, 16)
            } else {
                ForEach(model.discovered) { room in
                    Button {
                        model.join(room: room)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(room.name).font(.system(size: 14, weight: .medium))
                                Text("房主 \(room.host) · 点一下入座").font(.system(size: 10)).foregroundStyle(Theme.dimText)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Theme.dimText)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("本桌规则")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.gold)

            VStack(spacing: 8) {
                ruleRow("用牌", "萬筒條 1-9 各 4 张，加 4 张红中，共 112 张")
                ruleRow("红中", "皮子。手上有红中不能胡，打出去即补摸")
                ruleRow("和牌", "只能自摸；不能点炮、不能抢杠")
                ruleRow("动作", "可碰、可杠，不能吃")
                ruleRow("分数", "自摸 10 · 点杠 10 · 暗杠 15 · 蓄杠 5")
                ruleRow("倍乘", "每打出一张红中翻一倍，两边皮子相乘")
            }

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                if model.roomMode == .host {
                    GoldButton(title: model.hasFourSeats ? "开始游戏" : "补机器人开始",
                               subtitle: model.hasFourSeats ? "4 人已就位" : "还差 \(4 - model.slots.count) 人") {
                        model.startMultiplayer(withBots: !model.hasFourSeats)
                    }
                } else {
                    Text(model.isMyTurnReady ? "已入座，等房主开局" : "等待房主分配座位…")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dimText)
                }
                GhostButton(title: "返回大厅") {
                    model.leaveRoom()
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.leading, 24)
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)
        }
    }

    private func ruleRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.gold.opacity(0.85))
                .frame(width: 34, alignment: .leading)
            Text(value)
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
