import Foundation
import Network
import JianliCore

/// 客户端：Bonjour 发现 + TCP 直连房主。它不懂规则，只转发动作、接收快照。
final class LanClient {

    var onRooms: (([DiscoveredRoom]) -> Void)?
    var onMessage: ((HostMessage) -> Void)?
    var onState: ((String) -> Void)?
    var onDisconnect: (() -> Void)?

    private let queue = DispatchQueue(label: "jianli.lan.client")
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var buffer: [UInt8] = []
    private var results: [String: NWBrowser.Result] = [:]
    private var isStopping = false

    func startBrowsing() {
        stop()
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: "_jianli._tcp", domain: nil), using: parameters)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            var rooms: [DiscoveredRoom] = []
            self.results.removeAll()
            for result in results {
                guard case let .service(name, _, _, _) = result.endpoint else { continue }
                self.results[name] = result
                rooms.append(DiscoveredRoom(id: name, name: name, host: "同 Wi-Fi"))
            }
            DispatchQueue.main.async {
                self.onRooms?(rooms)
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                DispatchQueue.main.async { self?.onState?("扫描失败：\(error.localizedDescription)") }
            }
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    func connect(to roomID: String, hello: ClientMessage) {
        guard let result = results[roomID] else {
            onState?("房间已消失，重新扫描一下")
            return
        }
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let connection = NWConnection(to: result.endpoint, using: parameters)
        self.connection = connection
        buffer = []

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.isStopping = false
                self.sendNow(hello)
                DispatchQueue.main.async { self.onState?("已连上房主") }
            case .failed(let error):
                DispatchQueue.main.async { self.onState?("连接失败：\(error.localizedDescription)") }
                if !self.isStopping { DispatchQueue.main.async { self.onDisconnect?() } }
            case .cancelled:
                if !self.isStopping { DispatchQueue.main.async { self.onDisconnect?() } }
            default:
                break
            }
        }
        connection.start(queue: queue)
        receive(on: connection)
    }

    func send(_ message: ClientMessage) {
        queue.async { [weak self] in
            self?.sendNow(message)
        }
    }

    func connectManually(host: String, port: UInt16, hello: ClientMessage) {
        stop()
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: parameters)
        self.connection = connection
        buffer = []
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.isStopping = false
                self.sendNow(hello)
                DispatchQueue.main.async { self.onState?("已直连房主 \(host)") }
            case .failed(let error):
                DispatchQueue.main.async { self.onState?("直连失败：\(error.localizedDescription)") }
                if !self.isStopping { DispatchQueue.main.async { self.onDisconnect?() } }
            default:
                break
            }
        }
        connection.start(queue: queue)
        receive(on: connection)
    }

    func stop() {
        isStopping = true
        browser?.cancel()
        browser = nil
        connection?.cancel()
        connection = nil
        buffer = []
    }

    private func sendNow(_ message: ClientMessage) {
        guard let connection, let payload = Wire.encodeJSON(message) else { return }
        connection.send(content: Wire.encode(payload), completion: .contentProcessed { _ in })
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffer.append(contentsOf: data)
                while let frame = Wire.popFrame(from: &self.buffer) {
                    if let message = Wire.decodeJSON(HostMessage.self, from: frame) {
                        DispatchQueue.main.async { self.onMessage?(message) }
                    }
                }
            }
            if isComplete || error != nil { return }
            self.receive(on: connection)
        }
    }
}
