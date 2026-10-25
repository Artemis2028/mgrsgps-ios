import Combine
import GridFixCore

/// Owns a confirmed import through sheet disappearance. Preview cancellation is
/// separate; a second confirmation cannot start another commit while one runs.
@MainActor
final class InterchangeCommit: ObservableObject {
    typealias Apply = (Backup.Document) async throws -> InterchangeCoordinator.Result
    @Published private(set) var importing = false
    @Published private(set) var failure: String?
    private var presented = false
    private var work: Task<Void,Never>?

    func setPresented(_ value: Bool) { presented = value }

    func clearFailure() { if !importing { failure = nil } }

    @discardableResult
    func start(_ document: Backup.Document,apply: @escaping Apply,completion: @escaping (InterchangeCoordinator.Result) -> Void) -> Bool {
        guard !importing else { return false }
        failure = nil; importing = true
        work = Task {
            do {
                let result = try await apply(document)
                work = nil; importing = false
                // An older sheet must not dismiss a replacement file preview.
                // The apply closure already reports durable progress upstream.
                if presented { completion(result) }
            } catch is CancellationError {
                work = nil
                failure = "Import cancelled. Already saved records are kept. Retry this unchanged content to finish without duplicates."
                importing = false
            } catch {
                work = nil; failure = "Import failed: " + error.localizedDescription; importing = false
            }
        }
        return true
    }
}
