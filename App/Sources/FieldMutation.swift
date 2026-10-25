import Combine
import Foundation

/// Own a confirmed edit through view disappearance. UI dismissal is permitted
/// only for the presentation that is still visible when the work finishes.
@MainActor
final class FieldMutation: ObservableObject {
    @Published private(set) var label: String?
    @Published private(set) var error: String?
    var working: Bool { label != nil }
    private var presented = false
    private var work: Task<Void,Never>?
    func setPresented(_ value: Bool) { presented = value }
    func clearError() { if !working { error = nil } }

    @discardableResult
    func run(_ label: String,action: @escaping () async throws -> Void,completion: @escaping (Bool) -> Void = { _ in }) -> Bool {
        guard !working else { return false }
        self.label = label; error = nil
        work = Task {
            do {
                try await action()
                work = nil; self.label = nil
                completion(presented)
            } catch {
                work = nil; self.error = error.localizedDescription; self.label = nil
            }
        }
        return true
    }
}
