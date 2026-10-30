import CoreLocation

struct NavigationHeading {
    let magnetic: Double
    let accuracy: Double
    let timestamp: Date
}
@MainActor
protocol NavigationLocationDriver: RecordingLocationDriver {
    var hasCompass: Bool { get }
    var onHeading: ((NavigationHeading) -> Void)? { get set }
}

/// The location portion is the same dedicated background driver used by the
/// recorder, with a separate top-edge/portrait compass for pocket navigation.
@MainActor
final class CoreLocationNavigationDriver: NSObject, NavigationLocationDriver, @preconcurrency CLLocationManagerDelegate {
    private let location = CoreLocationRecordingDriver()
    private let compass: CLLocationManager
    var hasCompass: Bool { CLLocationManager.headingAvailable() }
    var onHeading: ((NavigationHeading) -> Void)?
    var authorization: CLAuthorizationStatus { location.authorization }
    var precise: Bool { location.precise }
    var servicesEnabled: Bool { location.servicesEnabled }
    var onLocations: (([CLLocation]) -> Void)? { get { location.onLocations } set { location.onLocations = newValue } }
    var onAuthorization: (() -> Void)? { get { location.onAuthorization } set { location.onAuthorization = newValue } }
    var onFailure: ((Error) -> Void)? { get { location.onFailure } set { location.onFailure = newValue } }
    init(compass: CLLocationManager = CLLocationManager()) {
        self.compass = compass
        super.init(); compass.delegate = self; compass.headingFilter = kCLHeadingFilterNone; compass.headingOrientation = .portrait
    }
    func requestPermission() { location.requestPermission() }
    func start() { location.start(); if hasCompass { compass.startUpdatingHeading() } }
    func stop() { location.stop(); compass.stopUpdatingHeading() }
    func locationManager(_ manager: CLLocationManager,didUpdateHeading heading: CLHeading) {
        onHeading?(.init(magnetic: heading.magneticHeading,accuracy: heading.headingAccuracy,timestamp: heading.timestamp))
    }
    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool { true }
}
