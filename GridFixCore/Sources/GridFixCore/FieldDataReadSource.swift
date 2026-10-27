import Foundation

/// Provenance for a worker read. Publication only stats the active index (or
/// legacy archive); it never decodes/hashes the finished library on the caller.
struct FieldDataReadSource: Equatable, Sendable {
    let indexURL: URL
    let index: Stamp?
    let legacy: Stamp?

    struct Stamp: Equatable, Sendable {
        let size: UInt64
        let inode: UInt64
        let volume: UInt64
        let modified: Date

        static func read(_ url: URL) throws -> Self? {
            let attributes: [FileAttributeKey: Any]
            do { attributes = try FileManager.default.attributesOfItem(atPath:url.path) }
            catch {
                let error = error as NSError
                if error.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError,NSFileReadNoSuchFileError].contains(error.code) { return nil }
                throw error
            }
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  let size = attributes[.size] as? NSNumber,
                  let modified = attributes[.modificationDate] as? Date else {
                throw BackupError.notABackup("Saved routes and tracks source is not a regular file; the original was kept")
            }
            return .init(size:size.uint64Value,inode:(attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0,
                         volume:(attributes[.systemNumber] as? NSNumber)?.uint64Value ?? 0,modified:modified)
        }
    }

    static func read(_ indexURL: URL) throws -> Self {
        let index = try Stamp.read(indexURL)
        // Once v2 exists, an unrelated retained v1 archive is not our source.
        let legacy = try index == nil ? Stamp.read(indexURL.deletingLastPathComponent().appendingPathComponent("field-data-v1.zip")) : nil
        return .init(indexURL:indexURL,index:index,legacy:legacy)
    }

    func validate() throws {
        guard (try? Self.read(indexURL)) == self else { throw FieldDataStore.LoadFailure.changed }
    }
}
