import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Heavy writes happen before publication, in a system replacement directory
/// on the destination volume. Only the final atomic rename needs the store lock.
public final class PreparedAtomicFile: Sendable {
    public let destination: URL
    private let directory: URL
    private let source: URL

    public init(data: Data,destination: URL,lockCompatible: Bool = false) throws {
        self.destination = destination
        directory = try FileManager.default.url(for: .itemReplacementDirectory,in: .userDomainMask,
                                                 appropriateFor: destination.deletingLastPathComponent(),create: true)
        source = directory.appendingPathComponent("snapshot")
        do {
            try Task.checkCancellation()
            var options: Data.WritingOptions = []
            #if os(iOS)
            if lockCompatible { options.insert(.completeFileProtectionUntilFirstUserAuthentication) }
            #endif
            try data.write(to: source,options: options)
            try Task.checkCancellation()
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    /// Caller must first verify that its source snapshot is still current.
    /// A rename failure leaves the existing destination untouched.
    public func publish() throws {
        defer { discard() }
        let result = source.withUnsafeFileSystemRepresentation { sourcePath in
            destination.withUnsafeFileSystemRepresentation { destinationPath in
                guard let sourcePath,let destinationPath else { return Int32(-1) }
                return rename(sourcePath,destinationPath)
            }
        }
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    public func discard() { try? FileManager.default.removeItem(at: directory) }
    deinit { discard() }
}
