import Foundation
import Darwin
#if canImport(Tun2SocksKit)
import Tun2SocksKit
#endif

protocol XrayEngine {
    func start(xrayJSON: String) throws
    func stop()
}

enum XrayEngineFactory {
    static func make() -> XrayEngine {
        #if canImport(Tun2SocksKit)
            return LibXrayTun2SocksEngine()
        #else
            return StubXrayEngine(reason: .tun2SocksUnavailable)
        #endif
    }
}

enum XrayEngineError: LocalizedError {
    case notIntegrated
    case tun2SocksUnavailable
    case libXrayResponseDecodeFailed
    case libXrayCallFailed(String)

    var errorDescription: String? {
        switch self {
        case .notIntegrated:
            return "尚未接入真实 Xray Core。"
        case .tun2SocksUnavailable:
            return "未检测到 Tun2SocksKit。请在工程中添加 Tun2SocksKit 包依赖。"
        case .libXrayResponseDecodeFailed:
            return "libXray 返回结果解码失败"
        case let .libXrayCallFailed(message):
            return "libXray 调用失败: \(message)"
        }
    }
}

private struct LibXrayRunFromJSONRequest: Encodable {
    var datDir: String
    var mphCachePath: String
    var configJSON: String
}

private struct LibXrayCallResponse<T: Decodable>: Decodable {
    var success: Bool
    var data: T?
    var error: String?
}

#if canImport(Tun2SocksKit)
@_silgen_name("CGoRunXrayFromJSON")
private func CGoRunXrayFromJSON(_ requestBase64: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?

@_silgen_name("CGoStopXray")
private func CGoStopXray() -> UnsafeMutablePointer<CChar>?

@_silgen_name("CGoXrayVersion")
private func CGoXrayVersion() -> UnsafeMutablePointer<CChar>?
#endif

final class StubXrayEngine: XrayEngine {
    private let reason: XrayEngineError

    init(reason: XrayEngineError = .notIntegrated) {
        self.reason = reason
    }

    func start(xrayJSON: String) throws {
        guard !xrayJSON.isEmpty else {
            throw NSError(
                domain: "iosv2ray.xray",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Xray 配置为空"]
            )
        }
        throw reason
    }

    func stop() {
    }
}

#if canImport(Tun2SocksKit)
final class LibXrayTun2SocksEngine: XrayEngine {
    private let fileManager = FileManager.default
    private var tunTask: Task<Void, Never>?
    private var started = false
    private let lock = NSLock()

    private let socksAddress = "127.0.0.1"
    private let socksPort = 10808
    private let taskStackSize = 24576
    private let connectTimeoutMS = 5000
    private let readWriteTimeoutMS = 60000

    func start(xrayJSON: String) throws {
        guard !xrayJSON.isEmpty else {
            throw NSError(
                domain: "iosv2ray.xray",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Xray 配置为空"]
            )
        }

        lock.lock()
        defer { lock.unlock() }

        guard !started else {
            return
        }

        let runtime = try prepareRuntimeDirectory()
        let datDir = resolveDatDir(fallback: runtime)
        let requestBase64 = try makeRunXrayRequestBase64(
            datDir: datDir.path,
            mphCachePath: runtime.appendingPathComponent("xray.mph").path,
            configJSON: xrayJSON
        )

        let runResponse = try callRunXrayFromJSON(requestBase64: requestBase64)
        try decodeAndValidateResponse(runResponse)

        let tunConfig = makeTun2SocksConfig()
        tunTask = Task.detached(priority: .userInitiated) {
            let code = Socks5Tunnel.run(withConfig: .string(content: tunConfig))
            if code != 0 {
                NSLog("[XrayEngine] tun2socks exited with code: \(code)")
            }
        }

        started = true
        if let version = callXrayVersion() {
            NSLog("[XrayEngine] started with libXray version response: \(version)")
        }
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }

        guard started else {
            return
        }

        Socks5Tunnel.quit()
        tunTask?.cancel()
        tunTask = nil

        if let stopResponse = try? callStopXray() {
            _ = try? decodeAndValidateResponse(stopResponse)
        }

        started = false
    }

    private func prepareRuntimeDirectory() throws -> URL {
        let runtime = fileManager.temporaryDirectory.appendingPathComponent("xray-runtime", isDirectory: true)
        if fileManager.fileExists(atPath: runtime.path) {
            return runtime
        }
        try fileManager.createDirectory(at: runtime, withIntermediateDirectories: true)
        return runtime
    }

    private func resolveDatDir(fallback: URL) -> URL {
        if let groupDir = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: TunnelRuntimeDiagnostics.appGroupID
        ) {
            let geoDir = groupDir.appendingPathComponent("geo", isDirectory: true)
            if containsAnyGeoFile(in: geoDir) {
                return geoDir
            }
        }

        if let bundleDir = Bundle.main.resourceURL,
           containsAnyGeoFile(in: bundleDir) {
            return bundleDir
        }

        return fallback
    }

    private func containsAnyGeoFile(in dir: URL) -> Bool {
        let geoip = dir.appendingPathComponent("geoip.dat").path
        let geosite = dir.appendingPathComponent("geosite.dat").path
        return fileManager.fileExists(atPath: geoip) || fileManager.fileExists(atPath: geosite)
    }

    private func makeRunXrayRequestBase64(datDir: String, mphCachePath: String, configJSON: String) throws -> String {
        let request = LibXrayRunFromJSONRequest(
            datDir: datDir,
            mphCachePath: mphCachePath,
            configJSON: configJSON
        )
        let requestData = try JSONEncoder().encode(request)
        return requestData.base64EncodedString()
    }

    @discardableResult
    private func decodeAndValidateResponse(_ encoded: String) throws -> String? {
        guard let responseData = Data(base64Encoded: encoded) else {
            throw XrayEngineError.libXrayResponseDecodeFailed
        }

        let response = try JSONDecoder().decode(LibXrayCallResponse<String>.self, from: responseData)
        if !response.success {
            throw XrayEngineError.libXrayCallFailed(response.error ?? "unknown error")
        }

        return response.data
    }

    private func callRunXrayFromJSON(requestBase64: String) throws -> String {
        guard let ptr = requestBase64.withCString({ CGoRunXrayFromJSON($0) }) else {
            throw XrayEngineError.libXrayResponseDecodeFailed
        }
        defer { free(ptr) }
        return String(cString: ptr)
    }

    private func callStopXray() throws -> String {
        guard let ptr = CGoStopXray() else {
            throw XrayEngineError.libXrayResponseDecodeFailed
        }
        defer { free(ptr) }
        return String(cString: ptr)
    }

    private func callXrayVersion() -> String? {
        guard let ptr = CGoXrayVersion() else {
            return nil
        }
        defer { free(ptr) }
        return String(cString: ptr)
    }

    private func makeTun2SocksConfig() -> String {
        """
        tunnel:
          mtu: 1500

        socks5:
          address: \(socksAddress)
          port: \(socksPort)
          udp: 'udp'

        misc:
          task-stack-size: \(taskStackSize)
          connect-timeout: \(connectTimeoutMS)
          read-write-timeout: \(readWriteTimeoutMS)
          log-file: stderr
          log-level: error
        """
    }
}
#endif
