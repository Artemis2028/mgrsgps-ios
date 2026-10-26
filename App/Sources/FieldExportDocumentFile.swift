import SwiftUI
import UIKit
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

/// A provider receives a complete on-disk file, never a document that SwiftUI
/// still needs to materialize after the native Save controller has appeared.
final class PreparedNativeExport: @unchecked Sendable {
    let directory: URL
    let url: URL
    private init(directory: URL,url: URL) { self.directory = directory; self.url = url }
    static func prepare(data: Data,filename: String,extension ext: String,root: URL = FileManager.default.temporaryDirectory) throws -> PreparedNativeExport {
        try Task.checkCancellation()
        let directory = root.appendingPathComponent("gridfix-export-"+UUID().uuidString,isDirectory: true)
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
        do {
            let name = filename.replacingOccurrences(of: "[/\\\\\\p{Cc}]",with: "_",options: .regularExpression)
            let safe = name.isEmpty || name == "." || name == ".." ? "gridfix" : name
            let url = directory.appendingPathComponent(safe).appendingPathExtension(ext)
            try data.write(to: url,options: [.atomic,.completeFileProtectionUntilFirstUserAuthentication])
            try Task.checkCancellation()
            return .init(directory: directory,url: url)
        } catch { try? FileManager.default.removeItem(at: directory); throw error }
    }
    func discard() { Self.remove(directory) }
    private static func remove(_ directory: URL) {
        Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: directory) }
    }
    deinit { Self.remove(directory) }
}

struct FieldFileExportPresentation: View {
    let document: FieldExportDocumentFile
    let onDismiss: () -> Void
    let onCompletion: (Result<URL,Error>) -> Void
    @State private var file: PreparedNativeExport?
    @State private var completed = false
    var body: some View {
        Group {
            if let file {
                NativeFileExportPicker(file: file,completion: finish).frame(width: 0,height: 0)
            } else {
                Color.clear.frame(width: 0,height: 0)
            }
        }
            .task {
                guard file == nil,!completed else { return }
                let bytes = document.data,name = document.filename,ext = document.contentType.preferredFilenameExtension ?? "data"
                let worker = Task.detached(priority: .userInitiated) { try PreparedNativeExport.prepare(data: bytes,filename: name,extension: ext) }
                do {
                    let prepared = try await withTaskCancellationHandler(operation: { try await worker.value },onCancel: { worker.cancel() })
                    guard !Task.isCancelled else { prepared.discard(); return }
                    file = prepared
                } catch is CancellationError { }
                catch { finish(.failure(error)) }
            }
    }
    private func finish(_ outcome: Result<URL,Error>?) {
        guard !completed else { return }
        completed = true; file?.discard(); file = nil
        if let outcome { onCompletion(outcome) }
        onDismiss()
    }
}

private struct NativeFileExportPicker: UIViewControllerRepresentable {
    let file: PreparedNativeExport
    let completion: (Result<URL,Error>?) -> Void
    func makeUIViewController(context: Context) -> ExportHost { ExportHost(file: file,completion: completion) }
    func updateUIViewController(_ host: ExportHost,context: Context) {}
    static func dismantleUIViewController(_ host: ExportHost,coordinator: ()) { host.stop() }
    /// UIDocumentPicker must own its modal presentation. Embedding it as a
    /// child of a SwiftUI sheet can omit its export filename accessory.
    final class ExportHost: UIViewController,UIDocumentPickerDelegate,UIAdaptivePresentationControllerDelegate {
        let file: PreparedNativeExport
        let completion: (Result<URL,Error>?) -> Void
        private var completed = false
        private var dismantled = false
        private var picker: UIDocumentPickerViewController?
        init(file: PreparedNativeExport,completion: @escaping (Result<URL,Error>?) -> Void) {
            self.file = file; self.completion = completion
            super.init(nibName: nil,bundle: nil)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard picker == nil,!completed else { return }
            let picker = UIDocumentPickerViewController(forExporting: [file.url],asCopy: true)
            self.picker = picker; picker.delegate = self
            present(picker,animated: true)
            picker.presentationController?.delegate = self
        }
        private func finish(_ result: Result<URL,Error>?) {
            guard !completed else { return }
            completed = true
            if let picker,picker.presentingViewController != nil {
                picker.dismiss(animated: true) { [weak self] in
                    guard let self,!self.dismantled else { return }
                    self.completion(result)
                }
            } else { completion(result) }
        }
        func documentPicker(_ controller: UIDocumentPickerViewController,didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { finish(.success(url)) }
            else { finish(.failure(CocoaError(.fileWriteUnknown))) }
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish(nil) }
        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { finish(nil) }
        func stop() { dismantled = true; completed = true; picker?.dismiss(animated: false); picker = nil }
    }
}
