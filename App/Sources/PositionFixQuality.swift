import Foundation
import CoreLocation
import UIKit

/// Android faces/Faces.kt at release/1.1.0 (482b417). Core Location does not
/// expose satellite count or a reliable GNSS/network provider classification.
struct PositionFixQuality: Equatable {
    let ageSeconds: Int?
    let stale: Bool
    let bars: Int
    let word: String
    let trustDigits: Int

    init(fix: Fix, nowUptime: TimeInterval) {
        let elapsed = nowUptime - fix.timestampUptime
        ageSeconds = fix.timestampUptime.isFinite && fix.timestampUptime > 0 && elapsed.isFinite && elapsed >= 0
            ? Int(exactly: floor(elapsed)) : nil
        // Android compares whole seconds: 30 s is current, 31 s is stale.
        stale = ageSeconds.map { $0 > 30 } ?? true
        bars = fix.grade == 0 ? 0 : stale ? 1 : fix.grade
        word = bars == 0 ? "NO FIX" : stale ? "STALE" : fix.gradeWord
        trustDigits = stale ? 4 : fix.trustedDigits
    }

    var ageText: String {
        guard let ageSeconds else { return "Age unavailable" }
        if ageSeconds < 60 { return "\(ageSeconds) s" }
        if ageSeconds < 3600 { return "\(ageSeconds / 60) m \(ageSeconds % 60) s" }
        return ">1 h"
    }
}

enum DisplayHeadingPolicy {
    /// Core Location names the physical device side; UIKit names the interface
    /// side, so landscape names are opposite. Follow the scene, not UIDevice
    /// face-up/down or the user's requested (possibly rejected) rotation.
    static func deviceOrientation(_ interface: UIInterfaceOrientation) -> CLDeviceOrientation? {
        switch interface {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeRight: return .landscapeLeft
        case .landscapeLeft: return .landscapeRight
        default: return nil
        }
    }
    static func isFresh(timestampUptime: TimeInterval, nowUptime: TimeInterval) -> Bool {
        timestampUptime.isFinite && nowUptime.isFinite && timestampUptime > 0
            && nowUptime >= timestampUptime && nowUptime - timestampUptime <= 2
    }
}
