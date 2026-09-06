import GridFixCore
import SwiftUI
import UniformTypeIdentifiers

/// Waypoint list + add/edit. First product slice toward Android 0.9.32 parity.
struct WaypointsView: View {
    @EnvironmentObject private var store: WaypointStore
    @EnvironmentObject private var location: LocationService
    @State private var editing: Waypoint?
    @State private var showingEditor = false
    @State private var draftName = ""
    @State private var draftFolder = Folders.defaultFolder
    @State private var status: String?
    @State private var exportDoc: BackupDocumentFile?
    @State private var exportGPX: GPXDocumentFile?
    @State private var showingImporter = false
    @State private var importKind: ImportKind = .backup

    private enum ImportKind { case backup, gpx }

    var body: some View {
        ZStack {
            Blackout.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                header
                if store.waypoints.isEmpty {
                    empty
                } else {
                    list
                }
            }
            .padding(.bottom, 12)
        }
        .foregroundStyle(Blackout.ink)
        .sheet(isPresented: $showingEditor) { editor }
        .fileExporter(isPresented: Binding(
            get: { exportDoc != nil },
            set: { if !$0 { exportDoc = nil } }
        ), document: exportDoc, contentType: .zip, defaultFilename: "gridfix-backup") { _ in
            exportDoc = nil
        }
        .fileExporter(isPresented: Binding(
            get: { exportGPX != nil },
            set: { if !$0 { exportGPX = nil } }
        ), document: exportGPX, contentType: .xml, defaultFilename: "waypoints") { _ in
            exportGPX = nil
        }
        .fileImporter(isPresented: $showingImporter,
                      allowedContentTypes: importKind == .backup ? [.zip] : [.xml, .data],
                      allowsMultipleSelection: false) { result in
            handleImport(result)
        }
    }

    private var header: some View {
        HStack {
            SectionLabel(text: "Waypoints")
            Spacer()
            Menu {
                Button("Add at fix") { beginAdd(atFix: true) }
                Button("Add blank") { beginAdd(atFix: false) }
                Divider()
                Button("Export backup") { exportBackup() }
                Button("Export GPX") { exportGpx() }
                Button("Import backup") { importKind = .backup; showingImporter = true }
                Button("Import GPX") { importKind = .gpx; showingImporter = true }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(Blackout.accent)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No waypoints yet")
                .font(Blackout.label(18, weight: .semibold))
            Text("Add one at your current fix, or import a GridFix backup / GPX.")
                .font(Blackout.label(14))
                .foregroundStyle(Blackout.inkDim)
            if let status {
                Text(status).font(Blackout.label(12)).foregroundStyle(Blackout.accent)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
    }

    private var list: some View {
        List {
            ForEach(store.folders) { folder in
                let items = store.waypoints.filter {
                    $0.folder.caseInsensitiveCompare(folder.name) == .orderedSame
                }
                if !items.isEmpty {
                    Section {
                        ForEach(items) { wp in
                            Button {
                                beginEdit(wp)
                            } label: {
                                row(wp)
                            }
                            .listRowBackground(Blackout.background)
                            .swipeActions(edge: .leading) {
                                Button {
                                    store.select(wp.id)
                                } label: { Label("Nav", systemImage: "safari") }
                                .tint(Color(red: 1.0, green: 0.698, blue: 0.0))
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    store.delete(ids: [wp.id])
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                    } header: {
                        Text(folder.name.uppercased())
                            .font(Blackout.label(11))
                            .tracking(1.4)
                            .foregroundStyle(Blackout.accent)
                    }
                }
            }
            if let status {
                Text(status)
                    .font(Blackout.label(12))
                    .foregroundStyle(Blackout.accent)
                    .listRowBackground(Blackout.background)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func row(_ wp: Waypoint) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(wp.name)
                    .font(Blackout.label(16, weight: .semibold))
                    .foregroundStyle(wp.visible ? Blackout.ink : Blackout.inkDim)
                Text(MGRS.string(lat: wp.lat, lon: wp.lon, digits: 8) ?? "—")
                    .font(Blackout.numerals(13))
                    .foregroundStyle(Blackout.inkDim)
            }
            Spacer(minLength: 8)
            if store.selectedId == wp.id {
                Text("NAV")
                    .font(Blackout.label(10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Blackout.accent)
            }
        }
        .padding(.vertical, 4)
    }

    private var editor: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $draftName)
                TextField("Folder", text: $draftFolder)
                if let hint = Folders.reservedHint(draftFolder) {
                    Text(hint).foregroundStyle(Blackout.warn).font(Blackout.label(12))
                }
            }
            .navigationTitle(editing == nil ? "New waypoint" : "Edit waypoint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveEditor() }
                        .disabled(draftName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func beginAdd(atFix: Bool) {
        draftFolder = Folders.defaultFolder
        if atFix {
            guard let f = location.fix else {
                status = "No fix yet — wait for a position"
                return
            }
            draftName = MGRS.string(lat: f.lat, lon: f.lon, digits: 8) ?? "Waypoint"
            // Empty id marks a new waypoint; coords come from the fix.
            editing = Waypoint(id: "", name: draftName, lat: f.lat, lon: f.lon)
        } else {
            draftName = ""
            editing = nil
        }
        showingEditor = true
    }

    private func beginEdit(_ wp: Waypoint) {
        editing = wp
        draftName = wp.name
        draftFolder = wp.folder
        showingEditor = true
    }

    private func saveEditor() {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if let existing = editing, !existing.id.isEmpty {
            store.update(id: existing.id, draft: WaypointDraft(
                name: name, lat: existing.lat, lon: existing.lon, folder: draftFolder,
                symbol: existing.symbol, affiliation: existing.affiliation,
                echelon: existing.echelon, designation: existing.designation,
                kind: existing.kind, rotation: existing.rotation,
                metadata: existing.metadata
            ))
        } else {
            let lat = editing?.lat ?? location.fix?.lat ?? 0
            let lon = editing?.lon ?? location.fix?.lon ?? 0
            store.add(WaypointDraft(name: name, lat: lat, lon: lon, folder: draftFolder))
        }
        showingEditor = false
        status = nil
    }

    private func exportBackup() {
        let doc = Backup.Document(
            waypoints: store.waypoints,
            folders: store.folders
        )
        do {
            let data = try Backup.exportZip(doc)
            exportDoc = BackupDocumentFile(data: data)
            status = "Backup ready"
        } catch {
            status = "Backup failed: \(error.localizedDescription)"
        }
    }

    private func exportGpx() {
        let xml = GPX.build(waypoints: store.waypoints)
        exportGPX = GPXDocumentFile(text: xml)
        status = "GPX ready"
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let unlocked = url.startAccessingSecurityScopedResource()
            defer { if unlocked { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            switch importKind {
            case .backup:
                let doc = try Backup.importZip(data)
                let r = Backup.restoreWaypoints(doc, into: store)
                status = r.waypoints == 0
                    ? "Nothing new to restore"
                    : "Restored \(r.waypoints) waypoints"
            case .gpx:
                let xml = String(data: data, encoding: .utf8) ?? ""
                let drafts = GPX.parseWaypoints(xml)
                for d in drafts { store.add(d) }
                status = drafts.isEmpty ? "No waypoints in GPX" : "Imported \(drafts.count) from GPX"
            }
        } catch {
            status = "Import failed: \(error.localizedDescription)"
        }
    }
}

struct BackupDocumentFile: FileDocument {
    static var readableContentTypes: [UTType] { [.zip] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct GPXDocumentFile: FileDocument {
    static var readableContentTypes: [UTType] { [.xml] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        let d = configuration.file.regularFileContents ?? Data()
        text = String(data: d, encoding: .utf8) ?? ""
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
