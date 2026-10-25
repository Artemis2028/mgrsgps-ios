import SwiftUI
import UIKit

/// Android ui/Layout.kt integer contract, retained in settings and backups.
enum ScreenOrientation: Int, CaseIterable, Identifiable {
    case auto = 0, portrait = 1, landscape = 2, flipped = 3
    var id: Int { rawValue }
    var title: String {
        switch self { case .auto: return "Auto"; case .portrait: return "Portrait"; case .landscape: return "Landscape"; case .flipped: return "Flipped" }
    }
    func mask(pad: Bool) -> UIInterfaceOrientationMask {
        switch self {
        case .auto: return pad ? .all : .allButUpsideDown
        case .portrait: return .portrait
        // Interface orientation is opposite the physical device orientation.
        case .landscape: return .landscapeRight
        case .flipped: return .landscapeLeft
        }
    }
    var explanation: String {
        switch self {
        case .auto: return "Follows the device and the system rotation setting."
        case .portrait: return "Requests an upright screen for this app."
        case .landscape: return "Requests a sideways screen for a phone worn on armour. Flipped turns it the other way."
        case .flipped: return "Requests the opposite sideways screen. Landscape turns it back."
        }
    }
}

@MainActor
final class OrientationState: ObservableObject {
    static let shared = OrientationState()
    @Published private(set) var error: String?
    @Published private(set) var actual = "Not available"
    private weak var scene: UIWindowScene?
    private(set) var mode = ScreenOrientation.auto
    private var sceneID: ObjectIdentifier?
    private var generation = 0

    func prepare(_ value: Int) {
        if sceneID == nil { mode = ScreenOrientation(rawValue: value) ?? .auto }
    }

    func apply(_ mode: ScreenOrientation, to scene: UIWindowScene, force: Bool = false) {
        guard force || self.mode != mode || sceneID != ObjectIdentifier(scene) else { return }
        self.mode = mode; self.scene = scene; sceneID = ObjectIdentifier(scene)
        updateActual(scene)
        generation += 1; let request = generation
        error = nil
        for window in scene.windows {
            var controller = window.rootViewController
            while let current = controller {
                current.setNeedsUpdateOfSupportedInterfaceOrientations()
                controller = current.presentedViewController
            }
        }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mode.mask(pad: scene.traitCollection.userInterfaceIdiom == .pad))) { [weak self] error in
            Task { @MainActor in
                guard let self, self.generation == request else { return }
                self.error = "iOS could not rotate this window. Try using the app full screen, then retry."
            }
        }
    }
    func refresh() { if let scene { apply(mode,to: scene,force: true) } }
    func updateActual(_ scene: UIWindowScene) {
        let text: String
        switch scene.effectiveGeometry.interfaceOrientation {
        case .portrait: text = "Portrait"
        case .portraitUpsideDown: text = "Upside-down"
        case .landscapeRight: text = "Landscape"
        case .landscapeLeft: text = "Flipped"
        default: text = "Not available"
        }
        if actual != text { actual = text }
    }

}

/// The application mask and the scene geometry request must agree. The delegate
/// callback remains available on iOS 16+; no UIDevice KVC rotation is used.
@MainActor
final class FieldAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationState.shared.mode.mask(pad: (window?.traitCollection.userInterfaceIdiom ?? UIDevice.current.userInterfaceIdiom) == .pad)
    }
}

struct OrientationHost: UIViewControllerRepresentable {
    var value: Int
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.mode = ScreenOrientation(rawValue: value) ?? .auto
        controller.apply()
    }
    final class Controller: UIViewController {
        var mode = ScreenOrientation.auto
        override func loadView() { view = UIView(); view.isUserInteractionEnabled = false; view.backgroundColor = .clear }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); apply(force: true) }
        override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
            super.viewWillTransition(to: size, with: coordinator)
            coordinator.animate(alongsideTransition: nil) { [weak self] _ in self?.readActual() }
        }
        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            readActual()
        }
        private func readActual() {
            DispatchQueue.main.async { [weak self] in
                guard let scene = self?.viewIfLoaded?.window?.windowScene else { return }
                OrientationState.shared.updateActual(scene)
            }
        }
        func apply(force: Bool = false) {
            DispatchQueue.main.async { [weak self] in
                guard let self, let scene = self.viewIfLoaded?.window?.windowScene else { return }
                OrientationState.shared.apply(self.mode,to: scene,force: force)
            }
        }
    }
}
