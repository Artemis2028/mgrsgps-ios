import SwiftUI
import UniformTypeIdentifiers

/// One native Files presenter for every field export. Separate fileExporter
/// modifiers on the same view can suppress one another on older SwiftUI.
struct FieldExportDocumentFile: FileDocument {
    static var readableContentTypes: [UTType] { [.data,.zip,.gridFixGPX,.commaSeparatedText,.gridFixGeoJSON,.gridFixKML,.gridFixKMZ] }
    var data: Data
    var contentType: UTType
    var filename: String
    init(data: Data,contentType: UTType,filename: String = "gridfix") {
        self.data = data; self.contentType = contentType; self.filename = filename
    }
    init(configuration: ReadConfiguration) throws {
        guard let bytes = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        data = bytes; contentType = configuration.contentType; filename = configuration.file.preferredFilename ?? "gridfix"
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
