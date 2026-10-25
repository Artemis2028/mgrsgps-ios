import Foundation
import GridFixCore
import Network
import Security

/// One connection attempt. Reconnect policy and opt-in sharing belong to the
/// session, not this byte transport. All callbacks arrive on the private queue.
protocol TAKTransportDriving: AnyObject {
    func start(host: String, port: UInt16, tls: Bool, identity: SecIdentity?, anchors: [SecCertificate], pinnedSHA256: String?, onEvent: @escaping (TAKTransport.Event) -> Void)
    func send(_ xml: String)
    func send(_ xml: String, completion: @escaping (Bool) -> Void)
    func stop()
}
extension TAKTransportDriving {
    func send(_ xml: String, completion: @escaping (Bool) -> Void) { send(xml); completion(true) }
}
final class TAKTransport: TAKTransportDriving {
    enum Event {
        case ready
        case xml(String)
        case trustRequired(TAKServerTrust.Certificate)
        case failed(String)
        case refused(String)
    }
    private let queue = DispatchQueue(label: "app.gridfix.tak.transport")
    private var connection: NWConnection?
    private var generation = UUID()
    private var stream = TAKCoTStream()
    private var ready = false
    private var pendingBytes = 0
    private var receiveDeadline: DispatchSourceTimer?
    private var lastReceived: TimeInterval = 0
    private var callback: ((Event) -> Void)?

    func start(host: String, port: UInt16, tls: Bool, identity: SecIdentity?, anchors: [SecCertificate],
               pinnedSHA256: String?, onEvent: @escaping (Event) -> Void) {
        queue.async {
            self.reset()
            self.callback = onEvent
            let token = self.generation
            guard !host.isEmpty, port != 0, let endpointPort = NWEndpoint.Port(rawValue: port) else {
                self.fail("Invalid TAK address", token: token); return
            }
            let parameters: NWParameters
            if tls {
                let options = NWProtocolTLS.Options()
                sec_protocol_options_set_min_tls_protocol_version(options.securityProtocolOptions, .TLSv12)
                if let identity {
                    guard let value = sec_identity_create(identity) else {
                        self.fail("Unable to use the client identity", token: token); return
                    }
                    sec_protocol_options_set_local_identity(options.securityProtocolOptions, value)
                }
                sec_protocol_options_set_tls_server_name(options.securityProtocolOptions, host)
                sec_protocol_options_set_verify_block(options.securityProtocolOptions, { [weak self] _, trust, complete in
                    guard let self, self.generation == token else { complete(false); return }
                    let nativeTrust = sec_trust_copy_ref(trust).takeRetainedValue()
                    switch TAKServerTrust.evaluate(nativeTrust, host: host, anchors: anchors, pinnedSHA256: pinnedSHA256) {
                    case .trusted: complete(true)
                    case let .nameMismatch(certificate):
                        complete(false)
                        self.callback?(.trustRequired(certificate))
                        self.reset()
                    case .certificateChanged:
                        complete(false)
                        self.refuse("The pinned server certificate has changed. Connection refused.", token: token)
                    case let .refused(reason):
                        complete(false)
                        self.refuse(reason, token: token)
                    }
                }, self.queue)
                parameters = NWParameters(tls: options, tcp: NWProtocolTCP.Options())
            } else {
                parameters = NWParameters.tcp
            }
            let connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: parameters)
            self.connection = connection
            connection.stateUpdateHandler = { [weak self] state in
                guard let self, self.generation == token else { return }
                switch state {
                case .ready:
                    self.ready = true
                    self.lastReceived = ProcessInfo.processInfo.systemUptime
                    self.startReceiveDeadline(token: token)
                    self.callback?(.ready)
                    self.receive(token: token)
                case .failed: self.fail("TAK connection failed", token: token)
                case .waiting: self.fail("TAK server is unavailable", token: token)
                default: break
                }
            }
            connection.start(queue: self.queue)
            self.queue.asyncAfter(deadline: .now() + 20) { [weak self] in
                guard let self, self.generation == token, !self.ready else { return }
                self.fail("TAK connection timed out", token: token)
            }
        }
    }
    func send(_ xml: String) { send(xml, completion: { _ in }) }
    func send(_ xml: String, completion: @escaping (Bool) -> Void) {
        let bytes = Data(xml.utf8)
        queue.async {
            // Crucially, importing a package or encountering a name mismatch
            // never queues application data for transmission after approval.
            guard self.ready, let connection = self.connection else { completion(false); return }
            let token = self.generation
            guard bytes.count <= 256 * 1024, self.pendingBytes + bytes.count <= 1024 * 1024 else {
                self.fail("TAK send queue exceeded its limit", token: token); completion(false); return
            }
            self.pendingBytes += bytes.count
            connection.send(content: bytes, completion: .contentProcessed { [weak self] error in
                guard let self, self.generation == token else { completion(false); return }
                self.pendingBytes -= bytes.count
                completion(error == nil)
                if error != nil { self.fail("TAK send failed", token: token) }
            })
        }
    }
    func stop() { queue.async { self.reset() } }
    private func receive(token: UUID) {
        guard generation == token, ready, let connection else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 32768) { [weak self] data, _, complete, error in
            guard let self, self.generation == token else { return }
            if let data, !data.isEmpty {
                self.lastReceived = ProcessInfo.processInfo.systemUptime
                do {
                    for xml in try self.stream.feed(data) { self.callback?(.xml(xml)) }
                } catch {
                    self.fail("Invalid or oversized TAK stream", token: token); return
                }
            }
            if complete || error != nil { self.fail("TAK connection closed", token: token); return }
            self.receive(token: token)
        }
    }
    private func startReceiveDeadline(token: UUID) {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in
            guard let self, self.generation == token else { return }
            if ProcessInfo.processInfo.systemUptime - self.lastReceived >= 45 {
                self.fail("No TAK response for 45 seconds", token: token)
            }
        }
        receiveDeadline = timer; timer.resume()
    }
    private func refuse(_ reason: String, token: UUID) {
        guard generation == token else { return }
        let handler = callback; reset(); handler?(.refused(reason))
    }
    private func fail(_ reason: String, token: UUID) {
        guard generation == token else { return }
        let handler = callback
        reset()
        handler?(.failed(reason))
    }
    private func reset() {
        generation = UUID(); ready = false; pendingBytes = 0; stream = TAKCoTStream()
        receiveDeadline?.cancel(); receiveDeadline = nil
        let previous = connection; connection = nil
        previous?.stateUpdateHandler = nil; previous?.cancel()
        callback = nil
    }
}
