#if DEBUG
import GridFixCore
import SwiftUI
import UIKit

/// A transport gate, not a fake download. The normal URLSession, raster
/// validation, SQLite writes and completion/reload paths remain in use.
/// Explicit UI-test opt-in only; no fixture traffic reaches a real provider.
final class OfflineDownloadValidation: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var released = false
    private static var png = Data()
    private var loading: Task<Void, Never>?
    static var enabled: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-uiTesting") && args.contains("-uiTestOfflineDownloadLifetime")
    }
    static var layer: RasterLayer {
        .init(key: "usgs", label: "Lifetime training area", attribution: "Synthetic offline validation",
              template: "https://offline-lifetime.invalid/{z}/{x}/{y}.png", maxZoom: 3, maxDownloadZoom: 3, bulkDownload: true)
    }
    @MainActor static func makeStore(directory: URL) -> MapLayerStore {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let data = UIGraphicsImageRenderer(size: .init(width: 256, height: 256), format: format).pngData { context in
            UIColor(red: 0.12, green: 0.42, blue: 0.30, alpha: 1).setFill()
            context.fill(.init(x: 0, y: 0, width: 256, height: 256))
            UIColor(red: 0.25, green: 0.65, blue: 0.45, alpha: 1).setFill()
            context.fill(.init(x: 60, y: 60, width: 130, height: 20))
        }
        lock.lock(); png = data; released = false; lock.unlock()
        let preferencesURL = directory.appendingPathComponent("map-prefs-v1.json")
        if !FileManager.default.fileExists(atPath: preferencesURL.path) {
            var preferences = MapLayerStore.Preferences()
            preferences.baseLayer = layer.key; preferences.hasCamera = true
            preferences.latitude = 38.9; preferences.longitude = -77.03; preferences.zoom = 5
            try? JSONEncoder().encode(preferences).write(to: preferencesURL, options: .atomic)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfflineDownloadValidation.self]
        return MapLayerStore(directory: directory, catalog: [layer], configuration: configuration)
    }
    static func releaseResponses() { lock.lock(); released = true; lock.unlock() }
    static func holdResponses() { lock.lock(); released = false; lock.unlock() }
    private static func response() -> Data? {
        lock.lock(); defer { lock.unlock() }
        return released ? png : nil
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard request.url?.host == "offline-lifetime.invalid" else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return
        }
        loading = Task {
            do {
                while Self.response() == nil { try await Task.sleep(nanoseconds: 20_000_000) }
                try Task.checkCancellation()
                guard let bytes = Self.response(), let url = request.url else { return }
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "image/png", "Cache-Control": "no-store"])!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: bytes); client?.urlProtocolDidFinishLoading(self)
            } catch { /* URLSession owns cancellation delivery. */ }
        }
    }
    override func stopLoading() { loading?.cancel(); loading = nil }
}

struct OfflineDownloadValidationControl: View {
    @ObservedObject var maps: MapLayerStore
    @Environment(\.fieldNight) private var night
    let awayFromMap: Bool
    var body: some View {
        if OfflineDownloadValidation.enabled && awayFromMap {
            VStack(spacing: 4) {
                Text(maps.message ?? (maps.activeDownload == nil ? "No active download" : "Download active"))
                    .font(.caption).accessibilityIdentifier("offline-lifetime-status")
                Button("Release synthetic tile responses") { OfflineDownloadValidation.releaseResponses() }
                    .frame(minHeight: 44).accessibilityIdentifier("offline-lifetime-release")
                Button("Hold synthetic tile responses") { OfflineDownloadValidation.holdResponses() }
                    .frame(minHeight: 44).accessibilityIdentifier("offline-lifetime-hold")
            }.padding(.horizontal, 16).foregroundStyle(FieldPalette(night: night).ink)
        }
    }
}
#endif
