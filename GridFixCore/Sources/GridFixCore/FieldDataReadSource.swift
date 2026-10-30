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
    private var contentURL: URL? {
        if index != nil { return indexURL }
        if legacy != nil { return indexURL.deletingLastPathComponent().appendingPathComponent("field-data-v1.zip") }
        return nil
    }
    /// Worker-only receipt for byte-identical repairs that replace the inode.
    func contentDigest() throws -> String? {
        try Task.checkCancellation()
        guard let contentURL else { return nil }
        let result = FieldDataDisk.digest(try Data(contentsOf:contentURL,options:.mappedIfSafe))
        try Task.checkCancellation(); try validate()
        return result
    }
    func refreshedIfIdentical(digest: String?) throws -> Self {
        // Keep ordinary I/O faults on the publication path so a repaired
        // destination can retry; no unreadable source is accepted at commit.
        guard let current = try? Self.read(indexURL),current != self else { return self }
        guard (index != nil) == (current.index != nil),let digest,
              try current.contentDigest() == digest else { throw FieldDataStore.WriteFailure.changed }
        return current
    }
}
