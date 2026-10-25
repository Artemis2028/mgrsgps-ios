import SwiftUI
import UniformTypeIdentifiers

/// One native Files presenter for every field export. Separate fileExporter
/// modifiers on the same view can suppress one another on older SwiftUI.
struct FieldExportDocumentFile: FileDocument {
    static var readableContentTypes: [UTType] { [.data,.zip,.gridFixProtectedBackup,.gridFixGPX,.commaSeparatedText,.gridFixGeoJSON,.gridFixKML,.gridFixKMZ] }
    var data: Data
    var contentType: UTType
    var filename: String
    init(data: Data,contentType: UTType,filename: String = "gridfix") {
        self.data = data; self.contentType = contentType; self.filename = filename
    }
    init(_ prepared: PreparedFieldExport) {
        if prepared.protected {
            self.init(data: prepared.data,contentType: .gridFixProtectedBackup,filename: prepared.filename); return
        }
        let type: UTType
        switch prepared.format {
        case .gpx: type = .gridFixGPX
        case .csv: type = .commaSeparatedText
        case .geojson: type = .gridFixGeoJSON
        case .kml: type = .gridFixKML
        case .kmz: type = .gridFixKMZ
        case .atak: type = .zip
        }
        self.init(data: prepared.data,contentType: type,filename: prepared.filename)
    }
    init(configuration: ReadConfiguration) throws {
        guard let bytes = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        data = bytes; contentType = configuration.contentType; filename = configuration.file.preferredFilename ?? "gridfix"
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
