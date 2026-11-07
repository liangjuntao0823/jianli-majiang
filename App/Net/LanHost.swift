import Foundation
import Network
import Darwin
import JianliCore

/// 房主端的 TCP 服务：监听 + Bonjour 广播 + 帧收发。只做搬运，不含任何规则。
final class LanHost {

    enum Incoming {
        case hello(peer: UUID, name: String, token: String)
        case action(peer: UUID, action: Action)
        case startWithBots(peer: UUID)
        case nextHand(peer: UUID)
        case leave(peer: UUID)
        case dropped(peer: UUID)
    }

    var onIncoming: ((Incoming) -> Void)?
    var onState: ((String) -> Void)?

    /// 固定端口：Bonjour 被网络策略挡住时，客户端可以按 IP 直连
    static let port: UInt16 = 45910

    private let queue = DispatchQueue(label: "jianli.lan.host")
    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]
    private var buffers: [UUID: [UInt8]] = [:]

    func start(serviceName: String) {
        stop()
        do {
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = true
            let listener: NWListener
            if let fixed = NWEndpoint.Port(rawValue: Self.port), let onFixed = try? NWListener(using: parameters, on: fixed) {
                listener = onFixed
            } else {
                listener = try NWListener(using: parameters)
            }
            listener.service = NWListener.Service(name: serviceName, type: "_jianli._tcp")
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.emitState("房间已广播，等牌友加入")
                case .failed(let error):
                    self?.emitState("广播失败：\(error.localizedDescription)")
                default:
                    break
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            emitState("监听启动失败：\(error.localizedDescription)")
        }
    }

    /// 先把句柄摘下来再异步关，避免紧接 start() 时把新 listener 一起关掉
    func stop() {
        let listener = self.listener
        let sockets = connections
        self.listener = nil
        self.connections.removeAll()
        self.buffers.removeAll()
        queue.async {
            listener?.cancel()
            for (_, connection) in sockets { connection.cancel() }
        }
    }

    func send(_ message: HostMessage, to peer: UUID) {
        guard let payload = Wire.encodeJSON(message) else { return }
        queue.async { [weak self] in
            guard let self, let connection = self.connections[peer] else { return }
            connection.send(content: Wire.encode(payload), completion: .contentProcessed { _ in })
        }
    }

    func broadcast(_ message: HostMessage) {
        guard let payload = Wire.encodeJSON(message) else { return }
        queue.async { [weak self] in
            guard let self else { return }
            let framed = Wire.encode(payload)
            for (_, connection) in self.connections {
                connection.send(content: framed, completion: .contentProcessed { _ in })
            }
        }
    }

    func disconnect(peer: UUID) {
        queue.async { [weak self] in
            self?.connections[peer]?.cancel()
            self?.connections[peer] = nil
            self?.buffers[peer] = nil
        }
    }

    /// 本机在 Wi-Fi / 蜂窝上的 IPv4，房主用来念给客人听
    static func localIPv4() -> String? {
        var result: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            guard let addr = ptr.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_INET),
                  (flags & (IFF_UP | IFF_RUNNING)) != 0,
                  (flags & IFF_LOOPBACK) == 0 else { continue }
            let name = String(cString: ptr.pointee.ifa_name)
            guard name.hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                result = String(cString: host)
                if name == "en0" { return result }
            }
        }
        return result
    }

    // MARK: - 内部

    private func accept(_ connection: NWConnection) {
        let peer = UUID()
        connections[peer] = connection
        buffers[peer] = []
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                break
            case .failed, .cancelled:
                self?.drop(peer)
            default:
                break
            }
        }
        connection.start(queue: queue)
        receive(on: connection, peer: peer)
    }

    private func receive(on connection: NWConnection, peer: UUID) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                var buffer = self.buffers[peer] ?? []
                buffer.append(contentsOf: data)
                while let frame = Wire.popFrame(from: &buffer) {
                    self.handle(frame: frame, peer: peer)
                }
                self.buffers[peer] = buffer
            }
            if isComplete || error != nil {
                self.drop(peer)
                return
            }
            self.receive(on: connection, peer: peer)
        }
    }

    private func handle(frame: Data, peer: UUID) {
        guard let message = Wire.decodeJSON(ClientMessage.self, from: frame) else { return }
        switch message {
        case .hello(let name, let token):
            emit(.hello(peer: peer, name: name, token: token))
        case .action(let action):
            emit(.action(peer: peer, action: action))
        case .startWithBots:
            emit(.startWithBots(peer: peer))
        case .nextHand:
            emit(.nextHand(peer: peer))
        case .leave:
            emit(.leave(peer: peer))
        case .ping:
            send(.pong, to: peer)
        }
    }

    private func drop(_ peer: UUID) {
        connections[peer]?.cancel()
        connections[peer] = nil
        buffers[peer] = nil
        emit(.dropped(peer: peer))
    }

    private func emit(_ incoming: Incoming) {
        DispatchQueue.main.async { [weak self] in
            self?.onIncoming?(incoming)
        }
    }

    private func emitState(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.onState?(text)
        }
    }
}
