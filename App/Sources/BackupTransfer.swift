import Combine
import Foundation
import GridFixCore

/// Provider access, decompression and encoding never borrow the UI executor.
/// Publication remains ordered on the main actor and merges into current data.
enum BackupPreparation {
    static func read(_ url: URL, reader: @escaping @Sendable (URL) throws -> Backup.Document = { try InterchangeFileReader.backup($0) }) async throws -> Backup.Document {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let document = try reader(url)
            try Task.checkCancellation()
            return document
        }
        return try await withTaskCancellationHandler(operation: { try await worker.value },onCancel: { worker.cancel() })
    }

    static func encode(_ document: Backup.Document, writer: @escaping @Sendable (Backup.Document) throws -> Data = { try Backup.exportZip($0) }) async throws -> Data {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let data = try writer(document)
            try Task.checkCancellation()
            return data
        }
        return try await withTaskCancellationHandler(operation: { try await worker.value },onCancel: { worker.cancel() })
    }
}

@MainActor
final class BackupTransfer: ObservableObject {
    enum Phase: Equatable {
        case reading, exporting, restoring
        var title: String {
            switch self {
            case .reading: return "Reading backup…"
            case .exporting: return "Preparing backup…"
            case .restoring: return "Restoring backup…"
            }
        }
    }
    typealias Reader = @Sendable (URL) async throws -> Backup.Document
    typealias Writer = @Sendable (Backup.Document) async throws -> Data
    @Published private(set) var phase: Phase?
    private let reader: Reader
    private let writer: Writer
    private var generation = UUID()
    private var work: Task<Void,Never>?

    init(reader: @escaping Reader = { try await BackupPreparation.read($0) },
         writer: @escaping Writer = { try await BackupPreparation.encode($0) }) {
        self.reader = reader; self.writer = writer
    }

    @discardableResult
    func restore(_ url: URL, apply: @escaping (Backup.Document) async -> String, completion: @escaping (String) -> Void) -> Bool {
        let reader = reader
        return start(.reading,prepare: { try await reader(url) },commit: { document in
            self.phase = .restoring
            completion(await apply(document))
        },failure: { completion("Import failed: \($0.localizedDescription)") })
    }

    @discardableResult
    func export(_ snapshot: Backup.Document, completion: @escaping (Result<Data,Error>) -> Void) -> Bool {
        let writer = writer
        return start(.exporting,prepare: { try await writer(snapshot) },commit: { completion(.success($0)) },failure: { completion(.failure($0)) })
    }

    /// The returned handle lets an owner await canceled provider work if needed.
    /// A restore already committing must finish its ordered progress reporting.
    @discardableResult
    func cancel() -> Task<Void,Never>? {
        guard phase != .restoring else { return nil }
        generation = UUID()
        let previous = work; work = nil; phase = nil
        previous?.cancel()
        return previous
    }

    private func start<Value: Sendable>(_ phase: Phase,prepare: @escaping @Sendable () async throws -> Value,
                                        commit: @escaping (Value) async -> Void,failure: @escaping (Error) -> Void) -> Bool {
        guard self.phase == nil else { return false }
        let token = UUID(); generation = token; self.phase = phase
        work = Task {
            do {
                let result = try await prepare()
                try Task.checkCancellation()
                guard generation == token else { return }
                await commit(result)
            } catch {
                guard generation == token else { return }
                if !(error is CancellationError) { failure(error) }
            }
            guard generation == token else { return }
            self.phase = nil; work = nil
        }
        return true
    }
}
