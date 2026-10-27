import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// One native Files presenter for every field export. Separate fileExporter
/// modifiers on the same view can suppress one another on older SwiftUI.
struct FieldExportDocumentFile: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf,.data,.zip,.gridFixProtectedBackup,.gridFixGPX,.commaSeparatedText,.gridFixGeoJSON,.gridFixKML,.gridFixKMZ] }
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
    @State private var naming = true
    @State private var requestedName: String?
    @State private var approvedName: String?
    var body: some View {
        Group {
            if let file {
                NativeFileExportPicker(file: file,completion: finish)
                    .frame(maxWidth: .infinity,maxHeight: .infinity)
            } else {
                Color.clear
            }
        }
            // Give Files the real viewport for location/provider selection.
            .frame(maxWidth: .infinity,maxHeight: .infinity)
            .allowsHitTesting(false)
            .sheet(isPresented: $naming,onDismiss: {
                if let requestedName { approvedName = requestedName }
                else { finish(nil) }
            }) {
                ExportFilenameView(filename: document.filename,extension: document.contentType.preferredFilenameExtension ?? "data",cancel: { naming = false }) { name in
                    requestedName = name; naming = false
                }
            }
            .task(id: approvedName) {
                guard let name = approvedName,file == nil,!completed else { return }
                let bytes = document.data,ext = document.contentType.preferredFilenameExtension ?? "data"
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


/// The app owns the filename; Files owns location/provider selection. Some
/// system picker versions omit their optional filename accessory entirely.
enum ExportFilename {
    static func stem(_ input: String,extension ext: String) -> String? {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = "." + ext
        if value.lowercased().hasSuffix(suffix.lowercased()) { value.removeLast(suffix.count) }
        guard !value.isEmpty,value != ".",value != "..",value.utf8.count <= 200,
              !value.contains("/"),!value.contains("\\"),
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return value
    }
}

private struct ExportFilenameView: View {
    let filename: String
    let `extension`: String
    let cancel: () -> Void
    let choose: (String) -> Void
    @Environment(\.fieldNight) private var night
    @State private var name: String
    @FocusState private var focused: Bool
    init(filename: String,extension ext: String,cancel: @escaping () -> Void,choose: @escaping (String) -> Void) {
        self.filename = filename; self.extension = ext; self.cancel = cancel; self.choose = choose
        _name = State(initialValue: filename)
    }
    private var stem: String? { ExportFilename.stem(name,extension: self.extension) }
    var body: some View {
        let palette = FieldPalette(night: night)
        NavigationStack {
            Form {
                Section {
                    TextField("Filename",text: $name).foregroundStyle(palette.ink)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($focused).submitLabel(.done).onSubmit { focused = false }
                        .accessibilityIdentifier("export-filename")
                    Text("." + self.extension).font(.footnote).foregroundStyle(palette.inkDim)
                } header: { Text("Filename") } footer: {
                    Text(stem == nil ? "Use a shorter filename without slashes or line breaks." : "Choose where to save this file in Files. Its extension stays ." + self.extension + ".")
                        .foregroundStyle(stem == nil ? palette.warn : palette.inkDim)
                }
            }.scrollContentBackground(.hidden).background { FieldScreenBackground() }
                .foregroundStyle(palette.ink).tint(palette.accent)
                .navigationTitle("Export file").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) { Text("Export file").font(.headline).foregroundStyle(palette.ink) }
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel",action:cancel).accessibilityIdentifier("export-filename-cancel") }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Choose location") { if let stem { choose(stem) } }.disabled(stem == nil)
                            .accessibilityIdentifier("export-choose-location")
                    }
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = false }.accessibilityIdentifier("export-filename-keyboard-done") }
                }
        }.fieldSheetAppearance()
    }
}

private struct NativeFileExportPicker: UIViewControllerRepresentable {
    let file: PreparedNativeExport
    let completion: (Result<URL,Error>?) -> Void
    func makeUIViewController(context: Context) -> ExportHost { ExportHost(file: file,completion: completion) }
    func updateUIViewController(_ host: ExportHost,context: Context) {}
    static func dismantleUIViewController(_ host: ExportHost,coordinator: ()) { host.stop() }
    /// UIDocumentPicker owns its modal presentation and receives an already
    /// complete named file after the app's filename sheet has dismissed.
    final class ExportHost: UIViewController,UIDocumentPickerDelegate,UIAdaptivePresentationControllerDelegate {
        let file: PreparedNativeExport
        let completion: (Result<URL,Error>?) -> Void
        private var completed = false
        private var dismantled = false
        private var picker: UIDocumentPickerViewController?
        private var appeared = false
        private var presentationTask: Task<Void,Never>?
        init(file: PreparedNativeExport,completion: @escaping (Result<URL,Error>?) -> Void) {
            self.file = file; self.completion = completion
            super.init(nibName: nil,bundle: nil)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            appeared = true
            presentIfReady()
        }
        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            presentIfReady()
        }
        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            appeared = false
        }
        private func presentIfReady() {
            guard presentationTask == nil,picker == nil,!completed,!dismantled else { return }
            presentationTask = Task { @MainActor [weak self] in
                defer { self?.presentationTask = nil }
                let deadline = ProcessInfo.processInfo.systemUptime + 30
                while !Task.isCancelled {
                    guard let self,!self.completed,!self.dismantled else { return }
                    if let owner = self.readyPresenter() {
                        let picker = UIDocumentPickerViewController(forExporting: [self.file.url],asCopy: true)
                        // UIKit owns the Files location/provider viewport.
                        picker.modalPresentationStyle = .fullScreen
                        self.picker = picker; picker.delegate = self
                        owner.present(picker,animated: true)
                        picker.presentationController?.delegate = self
                        return
                    }
                    if ProcessInfo.processInfo.systemUptime >= deadline {
                        self.finish(.failure(PresentationError.busy)); return
                    }
                    do { try await Task.sleep(nanoseconds:100_000_000) } catch { return }
                }
            }
        }
        private func readyPresenter() -> UIViewController? {
            guard appeared,view.window != nil,view.bounds.width > 0,view.bounds.height > 0 else { return nil }
            var owner: UIViewController = self
            while let parent = owner.parent { owner = parent }
            guard owner.view.window === view.window,!owner.isBeingPresented,!owner.isBeingDismissed,
                  owner.presentedViewController == nil,owner.transitionCoordinator == nil else { return nil }
            return owner
        }
        private enum PresentationError: LocalizedError {
            case busy
            var errorDescription: String? { "Files could not open while another screen was closing. Try exporting again." }
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
        func stop() {
            dismantled = true; completed = true
            presentationTask?.cancel(); presentationTask = nil
            picker?.dismiss(animated:false); picker = nil
        }
    }
}
