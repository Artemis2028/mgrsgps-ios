import Foundation

/// Android ProtectedFiles.kt: exactly one interchange file inside the ordinary
/// authenticated backup envelope. A manifest identifies a full backup instead.
public enum ProtectedFiles {
    public static let maximumFileBytes = 16 * 1024 * 1024
    public enum Opened: Equatable, Sendable {
        case backup(Data)
        case file(name: String,data: Data)
    }
    public static func seal(name: String,bytes: Data,password: String) throws -> Data {
        guard bytes.count <= maximumFileBytes else {
            throw BackupError.notABackup("Too large to protect (over 16 MB). Export fewer items, or without a password.")
        }
        let filename = name.replacingOccurrences(of: "\\",with: "/").split(separator: "/").last.map(String.init) ?? "export"
        guard filename != ".",filename != "..",filename.utf8.count <= 65535,
              !filename.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw BackupError.notABackup("Invalid protected export filename")
        }
        try Task.checkCancellation()
        return try BackupCrypto.seal(ZipArchive.write(entries: [.init(name: filename,data: bytes)]),password: password)
    }
    public static func open(_ sealed: Data,password: String) throws -> Opened {
        let plain = try BackupCrypto.open(sealed,password: password)
        var count = 0, first: (String,Data)?, isBackup = false
        // Validate every member/CRC/path, including unused members, before
        // identifying a backup. Directories count in a single-file export.
        try ZipArchive.visit(plain) { name,data in
            count += 1
            if count == 1 { first = (name,data) }
            if name == Backup.manifestName { isBackup = true }
        }
        try Task.checkCancellation()
        if isBackup { return .backup(plain) }
        guard count == 1,let (name,data) = first,!name.contains("/"),!name.contains("\\"),
              !name.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw BackupError.notABackup("Unexpected protected file layout; expected one export file")
        }
        return .file(name: name,data: data)
    }
}
