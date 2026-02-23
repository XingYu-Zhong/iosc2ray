import Foundation
import Network

struct EndpointProbeResult {
    var reachable: Bool
    var latencyMS: Int?
    var message: String
}

actor EndpointProbeService {
    func probe(host: String, port: Int, timeout: TimeInterval = 4.0) async -> EndpointProbeResult {
        guard port > 0 && port <= 65535 else {
            return EndpointProbeResult(reachable: false, latencyMS: nil, message: "端口不合法")
        }

        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            return EndpointProbeResult(reachable: false, latencyMS: nil, message: "端口不合法")
        }

        let endpointHost = NWEndpoint.Host(host)
        let connection = NWConnection(host: endpointHost, port: nwPort, using: .tcp)
        let queue = DispatchQueue(label: "iosv2ray.probe")
        let start = Date()

        return await withCheckedContinuation { continuation in
            final class ProbeState: @unchecked Sendable {
                private let lock = NSLock()
                private var finished = false

                func markFinished() -> Bool {
                    lock.lock()
                    defer { lock.unlock() }
                    guard !finished else { return false }
                    finished = true
                    return true
                }
            }
            let state = ProbeState()

            @Sendable func finish(_ result: EndpointProbeResult) {
                guard state.markFinished() else { return }
                connection.cancel()
                continuation.resume(returning: result)
            }

            let timeoutItem = DispatchWorkItem {
                finish(EndpointProbeResult(reachable: false, latencyMS: nil, message: "连接超时"))
            }
            queue.asyncAfter(deadline: .now() + timeout, execute: timeoutItem)

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    timeoutItem.cancel()
                    let latency = Int(Date().timeIntervalSince(start) * 1000)
                    finish(EndpointProbeResult(reachable: true, latencyMS: latency, message: "可达"))
                case let .failed(error):
                    timeoutItem.cancel()
                    finish(EndpointProbeResult(reachable: false, latencyMS: nil, message: "连接失败: \(error.localizedDescription)"))
                case .cancelled:
                    break
                default:
                    break
                }
            }

            connection.start(queue: queue)
        }
    }
}
