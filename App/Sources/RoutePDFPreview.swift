import CoreTransferable
import GridFixCore
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct RoutePDFPreviewRequest: Identifiable {
    let id = UUID()
    let name: String
    let data: Data
}

struct RoutePDFPreview: View {
    let request: RoutePDFPreviewRequest
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fieldNight) private var night
    @State private var exporting = false
    @State private var exportError: String?
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PDFPages(data: request.data).accessibilityIdentifier("strip-map-pdf-preview")
                if let exportError { Text(exportError).font(.footnote).foregroundStyle(FieldPalette(night: night).ink).padding() }
            }
            .navigationTitle("Strip map PDF").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { Text("Strip map PDF").font(.headline).foregroundStyle(FieldPalette(night: night).ink) }
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItemGroup(placement: .confirmationAction) {
                    ShareLink(item: ShareableRoutePDF(data: request.data,filename: StripMapPDF.filename(request.name)),preview: SharePreview(request.name)) {
                        Label("Share PDF",systemImage: "square.and.arrow.up")
                    }.accessibilityIdentifier("share-strip-map-pdf")
                    Button("Save") { exporting = true }.accessibilityIdentifier("export-strip-map-pdf")
                }
            }
            .fileExporter(isPresented: $exporting,document: StripMapDocumentFile(data: request.data),contentType: .pdf,defaultFilename: StripMapPDF.filename(request.name)) { result in
                if case .failure(let error) = result { exportError = "Export failed: "+error.localizedDescription }
            }
        }.tint(FieldPalette(night: night).accent).fieldSheetAppearance()
    }
}
private struct PDFPages: UIViewRepresentable {
    let data: Data
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView(); view.autoScales = true; view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical; view.backgroundColor = .darkGray; view.document = PDFDocument(data: data)
        return view
    }
    func updateUIView(_ view: PDFView,context: Context) {}
}
struct StripMapDocumentFile: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct ShareableRoutePDF: Transferable,Sendable {
    let data: Data
    let filename: String
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { (item: Self) in
            SentTransferredFile(try item.exportFile())
        }
    }
    // A named file preserves the route-derived name in iOS 16 sharing extensions.
    // Each export owns a temporary directory, so repeated shares cannot overwrite
    // an earlier file that a provider is still reading.
    func exportFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("gridfix-route-share",isDirectory: true).appendingPathComponent(UUID().uuidString,isDirectory: true)
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(filename+".pdf")
        do { try data.write(to: file,options: .atomic); return file }
        catch { try? FileManager.default.removeItem(at: directory); throw error }
    }
}
