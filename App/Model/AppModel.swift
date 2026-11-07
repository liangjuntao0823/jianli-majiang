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
    @Published var localIP: String = ""
    @Published var secondsLeft: Int = 0
    @Published var toast: String? {
        didSet {
            toastTask?.cancel()
            guard toast != nil else { return }
            toastTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_400_000_000)
                if !Task.isCancelled { self.toast = nil }
            }
        }
    }

    private var engine: MahjongEngine?
    private var host: LanHost?
    private var client: LanClient?
    private var peerSeat: [UUID: Seat] = [:]
    private var seatPeer: [Seat: UUID] = [:]
    private var tokenSeat: [String: Seat] = [:]
    private var botTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?

    private var turnStartedAt = Date()
    private var lastRoomID: String?
    private var retryLeft = 0
    private var oldSnapshot: TableSnapshot?

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
        tokenSeat[token] = .east

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

        localIP = LanHost.localIPv4() ?? ""
        isOnline = true
        statusLine = "房间已广播，等牌友加入"
        startHeartbeat()
        route = .room
    }

    func beginJoining() {
        roomMode = .client
        slots = []
        roomInfo = nil
        snapshot = nil
        oldSnapshot = nil

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
        client.onDisconnect = { [weak self] in
            Task { @MainActor in self?.handleDisconnect() }
        }
        client.startBrowsing()
        self.client = client

        statusLine = "正在扫描局域网…"
        route = .room
    }

    func join(room: DiscoveredRoom) {
        lastRoomID = room.id
        retryLeft = 3
        statusLine = "正在连接 \(room.name)…"
        client?.connect(to: room.id, hello: .hello(name: myName, token: token))
    }

    /// Bonjour 被网络策略挡住时的兜底：直接填房主屏幕上那串 IP
    func manualJoin(hostIP: String) {
        let trimmed = hostIP.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        retryLeft = 3
        lastRoomID = nil
        statusLine = "正在直连 \(trimmed)…"
        client?.connectManually(host: trimmed, port: LanHost.port, hello: .hello(name: myName, token: token))
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
        startLoops()
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
        startLoops()
    }

    func leaveRoom() { leaveTable() }

    func leaveTable() {
        if roomMode == .host, host != nil {
            host?.broadcast(.ended("房主已离开牌桌"))
        }
        botTask?.cancel(); botTask = nil
        clockTask?.cancel(); clockTask = nil
        heartbeatTask?.cancel(); heartbeatTask = nil
        host?.onIncoming = nil
        host?.onState = nil
        host?.stop()
        host = nil
        client?.onMessage = nil
        client?.onRooms = nil
        client?.onState = nil
        client?.onDisconnect = nil
        client?.stop()
        client = nil
        peerSeat.removeAll()
        seatPeer.removeAll()
        tokenSeat.removeAll()
        engine = nil
        snapshot = nil
        oldSnapshot = nil
        slots = []
        roomInfo = nil
        discovered = []
        isOnline = false
        statusLine = ""
        localIP = ""
        secondsLeft = 0
        lastRoomID = nil
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
        startLoops()
    }

    private func act(_ action: Action) {
        if roomMode == .client {
            Sound.play(action.soundKind)
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
        if seat == mySeat { Sound.play(action.soundKind) }
        publish()
    }

    private func publish() {
        guard let engine else { return }
        let fresh = engine.snapshot(for: mySeat)
        if fresh.current != snapshot?.current || fresh.phase != snapshot?.phase {
            turnStartedAt = Date()
        }
        snapshot = fresh
        if roomMode == .host {
            for (peer, seat) in peerSeat {
                host?.send(.snapshot(engine.snapshot(for: seat)), to: peer)
            }
        }
        if engine.state.phase == .finished {
            botTask?.cancel()
            Sound.play(.win)
        }
    }

    private func startLoops() {
        startBotLoop()
        startClock()
    }

    private func startBotLoop() {
        botTask?.cancel()
        botTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard let self else { return }
                self.botStep()
            }
        }
    }

    /// 0.5 秒一跳：既刷新倒计时，也在超时后替发呆的人出牌
    private func startClock() {
        clockTask?.cancel()
        clockTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self else { return }
                self.tick()
            }
        }
    }

    private func tick() {
        guard let snap = snapshot, snap.phase != .finished else {
            secondsLeft = 0
            return
        }

        let limit: Int
        switch snap.phase {
        case .awaitingDiscard:
            limit = snap.playSeconds
        case .awaitingClaim:
            limit = snap.claimSeconds
        case .idle, .finished:
            limit = 0
        }
        guard limit > 0 else {
            secondsLeft = 0
            return
        }

        let elapsed = Int(Date().timeIntervalSince(turnStartedAt))
        secondsLeft = max(0, limit - elapsed)

        guard elapsed >= limit else { return }
        turnStartedAt = Date()
        enforceTimeout()
    }

    /// 只有房主真正执行托管，客户端只负责把倒计时钟画出来
    private func enforceTimeout() {
        guard roomMode == .host, var engine, engine.state.phase != .finished else { return }

        if engine.state.phase == .awaitingClaim, let pending = engine.state.pending {
            for raw in pending.outstanding {
                guard Seat(rawValue: raw) != nil else { continue }
                _ = try? engine.apply(.pass, by: Seat(rawValue: raw)!)
            }
            self.engine = engine
            toast = "声明超时，自动过"
            publish()
            return
        }

        if engine.state.phase == .awaitingDiscard {
            let seat = engine.state.current
            if let action = Bot.nextAction(engine: engine, seat: seat) {
                _ = try? engine.apply(action, by: seat)
            }
            self.engine = engine
            toast = "超时托管：\(engine.state.players[seat.rawValue].name)"
            publish()
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

    // MARK: - 心跳与重连

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self else { return }
                if self.roomMode == .client { self.client?.send(.ping) }
            }
        }
    }

    private func handleDisconnect() {
        guard roomMode == .client, route == .table || route == .room else { return }
        isOnline = false
        statusLine = "连接断开，正在重连…"
        toast = "连接断开，正在重试（座位保留 30 秒）"

        guard retryLeft > 0 else {
            toast = "重连失败，已退出牌桌"
            leaveTable()
            return
        }
        retryLeft -= 1

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard self.roomMode == .client else { return }
            let hello = ClientMessage.hello(name: self.myName, token: self.token)
            if let roomID = self.lastRoomID {
                self.client?.connect(to: roomID, hello: hello)
            } else {
                self.client?.connectManually(host: self.localIP, port: LanHost.port, hello: hello)
            }
        }
    }

    // MARK: - 房主收包

    private func handle(_ incoming: LanHost.Incoming) {
        switch incoming {
        case .hello(let peer, let name, let token):
            if let seat = tokenSeat[token] {
                peerSeat[peer] = seat
                seatPeer[seat] = peer
                if let index = slots.firstIndex(where: { $0.seat == seat }) {
                    slots[index].connected = true
                    slots[index].name = name
                } else {
                    slots.append(SlotInfo(seat: seat, name: name, connected: true, isBot: false, isMine: false))
                }
                sendJoined(to: peer, seat: seat)
                broadcastRoom()
                statusLine = "\(name) 重连 \(seat.label)家"
                if let engine { host?.send(.snapshot(engine.snapshot(for: seat)), to: peer) }
                return
            }

            guard let seat = freeSeat() else {
                host?.send(.rejected("房间满了"), to: peer)
                return
            }
            peerSeat[peer] = seat
            seatPeer[seat] = peer
            tokenSeat[token] = seat
            isOnline = true
            slots.append(SlotInfo(seat: seat, name: name, connected: true, isBot: false, isMine: false))
            sendJoined(to: peer, seat: seat)
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
            if let index = slots.firstIndex(where: { $0.seat == seat }) {
                slots[index].connected = false
            }
            broadcastRoom()
            statusLine = "\(seat.label)家掉线，座位保留"
        }
    }

    private func sendJoined(to peer: UUID, seat: Seat) {
        let room = roomInfo ?? RoomInfo(code: "0000", hostName: myName, ruleName: "监利红中", started: false)
        host?.send(.joined(seat: seat, room: room, slots: slots), to: peer)
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
            Sound.play(.join)

        case .room(let room, let slots):
            roomInfo = room
            self.slots = slots.map { slot in
                var copy = slot
                copy.isMine = (slot.seat == mySeat)
                return copy
            }

        case .snapshot(let table):
            if oldSnapshot == nil || table.phase != oldSnapshot?.phase || table.current != oldSnapshot?.current {
                turnStartedAt = Date()
            }
            let before = oldSnapshot
            oldSnapshot = table
            snapshot = table
            if route != .table {
                route = .table
                Sound.play(.join)
            }
            diffSound(before: before, after: table)

        case .toast(let text):
            toast = text

        case .rejected(let reason):
            toast = reason

        case .ended(let reason):
            toast = reason
            leaveTable()

        case .pong:
            isOnline = true
        }
    }

    private func diffSound(before: TableSnapshot?, after: TableSnapshot) {
        guard let before else { return }
        if after.phase == .finished, before.phase != .finished {
            Sound.play(.win)
            return
        }
        let meldsBefore = before.players.reduce(0) { $0 + $1.melds.count }
        let meldsAfter = after.players.reduce(0) { $0 + $1.melds.count }
        if meldsAfter > meldsBefore {
            let last = after.players.flatMap { $0.melds }.last
            Sound.play(last?.isGang == true ? .gang : .peng)
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

// MARK: - 动作 → 音效

extension Action {
    var soundKind: Sound.Kind {
        switch self {
        case .discard(let tile): return tile.isRed ? .redDiscard : .discard
        case .peng: return .peng
        case .gangExposed, .gangConcealed, .gangAdded: return .gang
        case .hu: return .win
        case .pass: return .none
        }
    }
}
