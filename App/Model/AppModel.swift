import SwiftUI
import UIKit
import JianliCore

@MainActor
final class AppModel: ObservableObject {

    enum Route: Hashable { case home, room, table }
    enum RoomMode: Equatable { case host, client }

    @Published var route: Route = .home
    @Published var roomMode: RoomMode = .host
    @Published var snapshot: TableSnapshot?
    @Published var mySeat: Seat = .east
    @Published var roomInfo: RoomInfo?
    @Published var slots: [SlotInfo] = []
    @Published var discovered: [DiscoveredRoom] = []
    @Published var statusLine: String = ""
    @Published var isOnline: Bool = false
    @Published var toast: String? {
        didSet {
            toastTask?.cancel()
            guard toast != nil else { return }
            toastTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                if !Task.isCancelled { self.toast = nil }
            }
        }
    }

    private var engine: MahjongEngine?
    private var host: LanHost?
    private var client: LanClient?
    private var peerSeat: [UUID: Seat] = [:]
    private var seatPeer: [Seat: UUID] = [:]
    private var botTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?

    private var myName: String {
        UserDefaults.standard.string(forKey: "playerName") ?? "涛"
    }

    private lazy var token: String = {
        if let saved = UserDefaults.standard.string(forKey: "seatToken") { return saved }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: "seatToken")
        return fresh
    }()

    var hasFourSeats: Bool { slots.count >= 4 }
    var isMyTurnReady: Bool { isOnline }

    // MARK: - 大厅

    func createRoom() {
        roomMode = .host
        mySeat = .east
        peerSeat.removeAll()
        seatPeer.removeAll()

        let code = String(format: "%04d", Int.random(in: 1000...9999))
        roomInfo = RoomInfo(code: code, hostName: myName, ruleName: "监利红中", started: false)
        slots = [SlotInfo(seat: .east, name: myName, connected: true, isBot: false, isMine: true)]

        let host = LanHost()
        host.onIncoming = { [weak self] incoming in
            Task { @MainActor in self?.handle(incoming) }
        }
        host.onState = { [weak self] text in
            Task { @MainActor in self?.statusLine = text }
        }
        host.start(serviceName: "\(myName)的牌桌")
        self.host = host

        isOnline = true
        statusLine = "房间已广播，等牌友加入"
        route = .room
    }

    func beginJoining() {
        roomMode = .client
        slots = []
        roomInfo = nil
        snapshot = nil

        let client = LanClient()
        client.onRooms = { [weak self] rooms in
            Task { @MainActor in self?.discovered = rooms }
        }
        client.onMessage = { [weak self] message in
            Task { @MainActor in self?.handle(message) }
        }
        client.onState = { [weak self] text in
            Task { @MainActor in self?.statusLine = text }
        }
        client.startBrowsing()
        self.client = client

        statusLine = "正在扫描局域网…"
        route = .room
    }

    func join(room: DiscoveredRoom) {
        statusLine = "正在连接 \(room.name)…"
        client?.connect(to: room.id, hello: .hello(name: myName, token: token))
    }

    func startSolo() {
        leaveTable()
        roomMode = .host
        mySeat = .east
        isOnline = true

        var bots = Set<Seat>()
        for seat in Seat.allCases where seat != .east { bots.insert(seat) }
        var engine = MahjongEngine(seed: UInt64.random(in: 1...999_999),
                                   names: [myName, "阿强", "小美", "老李"],
                                   dealer: .east,
                                   roundIndex: 1,
                                   botSeats: bots)
        engine.startHand()
        self.engine = engine
        route = .table
        publish()
        startBotLoop()
    }

    func startMultiplayer(withBots: Bool) {
        let fallback = ["阿强", "小美", "老李", "老王"]
        let names = (0..<4).map { index -> String in
            if let slot = slots.first(where: { $0.seat.rawValue == index }) { return slot.name }
            return fallback[index]
        }
        var bots = Set<Seat>()
        for index in 0..<4 where !slots.contains(where: { $0.seat.rawValue == index }) {
            bots.insert(Seat(rawValue: index)!)
        }

        var engine = MahjongEngine(seed: UInt64.random(in: 1...999_999),
                                   names: names,
                                   dealer: .east,
                                   roundIndex: 1,
                                   botSeats: bots)
        engine.startHand()
        self.engine = engine
        roomInfo?.started = true

        route = .table
        publish()
        broadcastRoom()
        startBotLoop()
    }

    func leaveRoom() {
        leaveTable()
    }

    func leaveTable() {
        botTask?.cancel()
        botTask = nil
        host?.stop()
        host = nil
        client?.stop()
        client = nil
        peerSeat.removeAll()
        seatPeer.removeAll()
        engine = nil
        snapshot = nil
        slots = []
        roomInfo = nil
        discovered = []
        isOnline = false
        statusLine = ""
        route = .home
    }

    func showRules() {
        toast = "112 张 · 红中为皮子（手上有红中不能胡）· 只能自摸 · 可碰杠不可吃 · 自摸10/点杠10/暗杠15/蓄杠5"
    }

    // MARK: - 玩家动作

    func discard(_ tile: Tile) { act(.discard(tile)) }
    func declareHu() { act(.hu) }
    func declareConcealedGang(_ tile: Tile) { act(.gangConcealed(tile)) }
    func declareAddedGang(_ tile: Tile) { act(.gangAdded(tile)) }

    func declareClaim(_ option: ClaimOption) {
        switch option {
        case .pass: act(.pass)
        case .peng: act(.peng)
        case .gang: act(.gangExposed)
        }
    }

    func nextHand() {
        if roomMode == .client {
            client?.send(.nextHand)
            return
        }
        guard var engine, engine.state.phase == .finished else { return }
        let seed = UInt64.random(in: 1...999_999)
        _ = engine.startNextHand(seed: seed)
        self.engine = engine
        publish()
        startBotLoop()
    }

    private func act(_ action: Action) {
        if roomMode == .client {
            client?.send(.action(action))
            return
        }
        apply(action, by: mySeat)
    }

    // MARK: - 引擎推进

    private func apply(_ action: Action, by seat: Seat) {
        guard var engine else { return }
        do {
            _ = try engine.apply(action, by: seat)
        } catch {
            toast = "\(error)"
            return
        }
        self.engine = engine
        publish()
    }

    private func publish() {
        guard let engine else { return }
        snapshot = engine.snapshot(for: mySeat)
        if roomMode == .host {
            for (peer, seat) in peerSeat {
                host?.send(.snapshot(engine.snapshot(for: seat)), to: peer)
            }
        }
        if engine.state.phase == .finished {
            botTask?.cancel()
        }
    }

    private func startBotLoop() {
        botTask?.cancel()
        botTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 420_000_000)
                guard let self else { return }
                self.botStep()
            }
        }
    }

    private func botStep() {
        guard var engine, engine.state.phase != .finished else { return }
        var acted = false

        if engine.state.phase == .awaitingClaim, let pending = engine.state.pending {
            for raw in pending.outstanding {
                guard let seat = Seat(rawValue: raw), engine.state.players[raw].isBot else { continue }
                if let action = Bot.nextAction(engine: engine, seat: seat) {
                    _ = try? engine.apply(action, by: seat)
                    acted = true
                }
                break
            }
        } else if engine.state.phase == .awaitingDiscard {
            let seat = engine.state.current
            if engine.state.players[seat.rawValue].isBot, let action = Bot.nextAction(engine: engine, seat: seat) {
                _ = try? engine.apply(action, by: seat)
                acted = true
            }
        }

        if acted {
            self.engine = engine
            publish()
        }
    }

    // MARK: - 房主收包

    private func handle(_ incoming: LanHost.Incoming) {
        switch incoming {
        case .hello(let peer, let name, _):
            guard let seat = freeSeat() else {
                host?.send(.rejected("房间满了"), to: peer)
                return
            }
            peerSeat[peer] = seat
            seatPeer[seat] = peer
            isOnline = true
            slots.append(SlotInfo(seat: seat, name: name, connected: true, isBot: false, isMine: false))

            let room = roomInfo ?? RoomInfo(code: "0000", hostName: myName, ruleName: "监利红中", started: false)
            host?.send(.joined(seat: seat, room: room, slots: slots), to: peer)
            broadcastRoom()
            statusLine = "\(name) 入座 \(seat.label)家"

        case .action(let peer, let action):
            guard let seat = peerSeat[peer] else { return }
            apply(action, by: seat)

        case .nextHand(let peer):
            if peerSeat[peer] != nil { nextHand() }

        case .startWithBots(_):
            break

        case .leave(let peer), .dropped(let peer):
            guard let seat = peerSeat.removeValue(forKey: peer) else { return }
            seatPeer[seat] = nil
            slots.removeAll { $0.seat == seat }
            broadcastRoom()
            statusLine = "有人离座，\(seat.label)家空出"
        }
    }

    private func handle(_ message: HostMessage) {
        switch message {
        case .joined(let seat, let room, let slots):
            mySeat = seat
            roomInfo = room
            self.slots = slots.map { slot in
                var copy = slot
                copy.isMine = (slot.seat == seat)
                return copy
            }
            isOnline = true
            statusLine = "已入座 \(seat.label)家"

        case .room(let room, let slots):
            roomInfo = room
            self.slots = slots.map { slot in
                var copy = slot
                copy.isMine = (slot.seat == mySeat)
                return copy
            }

        case .snapshot(let table):
            snapshot = table
            if route != .table { route = .table }

        case .toast(let text):
            toast = text

        case .rejected(let reason):
            toast = reason

        case .pong:
            break
        }
    }

    private func broadcastRoom() {
        guard let roomInfo else { return }
        host?.broadcast(.room(roomInfo, slots))
    }

    private func freeSeat() -> Seat? {
        let taken = Set(slots.map { $0.seat }).union([mySeat])
        return Seat.allCases.first { !taken.contains($0) }
    }
}
