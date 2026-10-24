import UIKit

/// Permission completion can precede UIKit's return to active, especially on
/// CI. Wait only through that inactive transition; never start from background.
@MainActor
func waitForPermissionForeground(_ isForeground: @MainActor () -> Bool) async {
    for _ in 0..<30 {
        guard !isForeground(), UIApplication.shared.applicationState == .inactive, !Task.isCancelled else { return }
        try? await Task.sleep(nanoseconds: 100_000_000)
    }
}
