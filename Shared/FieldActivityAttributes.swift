import ActivityKit
import Foundation

struct FieldActivityState: Codable, Hashable, Sendable {
    var title: String
    var status: String
    var detail: String
    var grid: String?
    var fixDate: Date?
    var fixExpiresAt: Date?
    var startedAt: Date?
    var fixUptime: TimeInterval? = nil
    var night: Bool
    func hasFreshFix(at date: Date = Date(),uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        guard let fixUptime,let expires=fixExpiresAt,fixUptime.isFinite,uptime.isFinite,uptime>=fixUptime else { return false }
        let limit=startedAt == nil ? 10.0 : 15.0
        return uptime-fixUptime<=limit && expires>date
    }
}

@available(iOS 16.2, *)
struct FieldActivityAttributes: ActivityAttributes {
    typealias ContentState = FieldActivityState
    var sessionID: String
    /// recording or navigation. No raw track or waypoint coordinates are stored.
    var kind: String
}
