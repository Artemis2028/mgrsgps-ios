import CoreLocation
import Foundation
import GridFixCore

/// The fix, graded the way the Android app grades it.
///
/// One deliberate difference: **iOS exposes no satellite count.** Core Location
/// gives `horizontalAccuracy` and nothing about GNSS status, so the grade and
/// the trusted precision come from accuracy alone and the satellite line is
/// simply absent. Faking a count would be worse than omitting it.
struct Fix: Equatable {
    let lat: Double
    let lon: Double
    let accuracyMeters: Double
    let altitudeMeters: Double?
    let timestamp: Date

    /// 0 to 5, from horizontal accuracy.
    var grade: Int {
        switch accuracyMeters {
        case ..<0: return 0
        case 0...5: return 5
        case 5...10: return 4
        case 10...20: return 3
        case 20...50: return 2
        default: return 1
        }
    }

    var gradeWord: String {
        switch grade {
        case 5: return "EXCELLENT"
        case 4: return "GOOD"
        case 3: return "FAIR"
        case 2: return "POOR"
        case 1: return "DEGRADED"
        default: return "NO FIX"
        }
    }

    /// The finest MGRS precision the error circle actually supports. Reading a
    /// 10-digit grid off a 30 m fix is false confidence, and the operator
    /// should be told which digits mean something.
    var trustedDigits: Int {
        switch accuracyMeters {
        case ..<0: return 4
        case 0...2: return 10
        case 2...15: return 8
        case 15...150: return 6
        default: return 4
        }
    }
}

@MainActor
final class LocationService: NSObject, ObservableObject {
    @Published private(set) var fix: Fix?
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    /// True when the user granted only coarse location: kilometre-scale error,
    /// which makes every grid on screen a lie. The UI must say so, not degrade
    /// quietly. This is the iOS twin of Android's approximate-location gate.
    @Published private(set) var reducedAccuracy = false

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .fitness
        authorization = manager.authorizationStatus
        refreshAccuracyAuthorization()
    }

    func start() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    private func refreshAccuracyAuthorization() {
        reducedAccuracy = manager.accuracyAuthorization == .reducedAccuracy
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last else { return }
        let f = Fix(
            lat: l.coordinate.latitude,
            lon: l.coordinate.longitude,
            accuracyMeters: l.horizontalAccuracy,
            altitudeMeters: l.verticalAccuracy >= 0 ? l.altitude : nil,
            timestamp: l.timestamp
        )
        Task { @MainActor [weak self] in self?.fix = f }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        let status = m.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.authorization = status
            self.refreshAccuracyAuthorization()
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                m.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        // A denied or momentarily unavailable fix is not an error state worth
        // shouting about; the readout already shows NO FIX.
    }
}
