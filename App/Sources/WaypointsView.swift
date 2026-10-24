import GridFixCore
import SwiftUI
import UniformTypeIdentifiers

/// Local waypoints with coordinate editing, folder visibility, and navigation.
struct WaypointsView: View {
    @EnvironmentObject private var store: WaypointStore
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var fieldData: FieldDataStore

    private var palette: FieldPalette { FieldPalette(night: settings.nightMode) }
    @State private var editorRequest: WaypointEditorRequest?
    var onNavigate: () -> Void = {}
    @State private var folderFilter: String?
    @State private var status: String?
    @State private var showingLibrary = false
    @State private var showingPaste = false
    @State private var exportDoc: BackupDocumentFile?
    @State private var exportGPX: GPXDocumentFile?
    @State private var showingImporter = false
    @State private var importKind: ImportKind = .backup

    private enum ImportKind { case backup, gpx }

    var body: some View {
        ZStack {
            FieldScreenBackground()
            VStack(alignment: .leading, spacing: 0) {
                header
                Button { showingLibrary = true } label: {
                    HStack {
                        Label("Routes & tracks", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        Spacer()
                        Text("\(fieldData.document.graphics.filter { $0.type == "route" }.count) routes · \(fieldData.document.tracks.count) tracks")
                            .font(.caption).foregroundStyle(palette.inkDim)
                        Image(systemName: "chevron.right").font(.caption)
                    }.padding(.horizontal, 20).frame(minHeight: 44)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("open-field-library")
                folderPicker
                if store.waypoints.isEmpty && fieldData.document.graphics.isEmpty && fieldData.document.tracks.isEmpty {
                    empty
                } else {
                    list
                }
            }
            .padding(.bottom, 12)
        }
        .foregroundStyle(palette.ink)
        .environment(\.fieldNight, settings.nightMode)
        .sheet(item: $editorRequest) { request in
            WaypointEditor(waypoint: request.waypoint, lat: request.lat, lon: request.lon) { draft in
                if let editing = request.waypoint { store.update(id: editing.id, draft: draft) }
                else { store.add(draft) }
                status = nil
            }
        }
        .sheet(isPresented: $showingLibrary) {
            FieldLibraryView(onNavigate: { showingLibrary = false; onNavigate() })
        }
        .sheet(isPresented: $showingPaste) {
            GPXPasteImportView { document in
                status = BackupCoordinator.restore(document, waypoints: store, fieldData: fieldData, settings: settings)
            }
        }
        .fileExporter(isPresented: Binding(
            get: { exportDoc != nil },
            set: { if !$0 { exportDoc = nil } }
        ), document: exportDoc, contentType: .zip, defaultFilename: "gridfix-backup") { _ in
            exportDoc = nil
        }
        .fileExporter(isPresented: Binding(
            get: { exportGPX != nil },
            set: { if !$0 { exportGPX = nil } }
        ), document: exportGPX, contentType: .gridFixGPX, defaultFilename: "gridfix") { _ in
            exportGPX = nil
        }
        .fileImporter(isPresented: $showingImporter,
                      allowedContentTypes: importKind == .backup ? [.zip] : [.gridFixGPX, .xml, .data],
                      allowsMultipleSelection: false) { result in
            handleImport(result)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Waypoints").font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text("\(store.waypoints.count) saved · on this device")
                    .font(.subheadline).foregroundStyle(palette.inkDim)
            }
            Spacer()
            Menu {
                Button("Add at fix") { beginAdd(atFix: true) }
                Button("Enter coordinates") { beginAdd(atFix: false) }
                Divider()
                Button("Export backup") { exportBackup() }
                Button("Export GPX") { exportGpx() }
                Button("Import backup") { importKind = .backup; showingImporter = true }
                Button("Import GPX") { importKind = .gpx; showingImporter = true }
                Button("Paste GPX") { showingPaste = true }
            } label: {
                Image(systemName: "ellipsis").frame(width: 44, height: 44)
            }
            .fieldGlassButton()
            .accessibilityLabel("Waypoint actions")
            Button { beginAdd(atFix: false) } label: {
                Image(systemName: "plus").frame(width: 44, height: 44)
            }
            .fieldGlassButton()
            .accessibilityLabel("Add waypoint")
            .accessibilityIdentifier("add-waypoint")
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No waypoints yet")
                .font(Blackout.label(18, weight: .semibold))
            Text("Add one at your current fix, or import a GridFix backup / GPX.")
                .font(Blackout.label(14))
                .foregroundStyle(palette.inkDim)
            if let status {
                Text(status).font(Blackout.label(12)).foregroundStyle(palette.accent)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
    }

    private var folderPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                folderChip("All", selected: folderFilter == nil) { folderFilter = nil }
                ForEach(store.folders) { folder in
                    folderChip(folder.name, selected: folderFilter == folder.name) { folderFilter = folder.name }
                }
            }.padding(.horizontal, 20).padding(.vertical, 8)
        }
    }

    private func folderChip(_ name: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(name).font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16).padding(.vertical, 10)
                .foregroundStyle(selected ? palette.accent : palette.ink)
                .background(selected ? palette.accent.opacity(0.14) : Color.white.opacity(0.04), in: Capsule())
                .overlay(Capsule().stroke(selected ? palette.accent.opacity(0.4) : palette.hairline))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(store.folders.filter { folderFilter == nil || $0.name == folderFilter }) { folder in
                    let items = store.waypoints.filter {
                        $0.folder.caseInsensitiveCompare(folder.name) == .orderedSame
                    }
                    let graphicCount = fieldData.document.graphics.filter { $0.folder.caseInsensitiveCompare(folder.name) == .orderedSame }.count
                    let trackCount = fieldData.document.tracks.filter { $0.folder.caseInsensitiveCompare(folder.name) == .orderedSame }.count
                    if !items.isEmpty || graphicCount > 0 || trackCount > 0 {
                        HStack {
                            SectionLabel(text: "\(folder.name) · \(items.count) WP · \(graphicCount) GFX · \(trackCount) TRK")
                            Spacer()
                            Button {
                                store.setFolderVisible(folder.name, visible: !folder.visible)
                            } label: {
                                Label(folder.visible ? "Hide folder" : "Show folder",
                                      systemImage: folder.visible ? "eye" : "eye.slash")
                                    .font(.caption).frame(minHeight: 44)
                            }
                            .buttonStyle(.plain).foregroundStyle(palette.inkDim)
                            .accessibilityIdentifier("folder-visibility-\(folder.name)")
                        }
                        ForEach(items) { wp in row(wp) }
                    }
                }
                if let status {
                    Text(status).font(.footnote).foregroundStyle(palette.accent).padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 20)
        }
    }

    private func row(_ wp: Waypoint) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: store.selectedId == wp.id ? "location.north.fill" : "flag.fill")
                .font(.title3).foregroundStyle(palette.accent)
                .frame(width: 44, height: 48)
                .background(palette.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            Button { beginEdit(wp) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(wp.name).font(.headline).foregroundStyle(wp.visible ? palette.ink : palette.inkDim)
                    Text(MGRS.parts(lat: wp.lat, lon: wp.lon, digits: settings.mgrsDigits)?.full ?? "Outside MGRS coverage")
                        .font(.system(.caption, design: .monospaced)).foregroundStyle(palette.inkDim)
                    if let f = location.usableFix {
                        let nav = Geodesy.navInfo(fromLat: f.lat, fromLon: f.lon, toLat: wp.lat, toLon: wp.lon)
                        Text(Format.distance(meters: nav.distanceMeters, unit: settings.units))
                            .font(.system(.caption, design: .monospaced)).foregroundStyle(palette.inkDim)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("edit-waypoint-\(wp.name)")
            Menu {
                Button("Edit", systemImage: "pencil") { beginEdit(wp) }
                Button(wp.visible ? "Hide on map" : "Show on map", systemImage: wp.visible ? "eye.slash" : "eye") {
                    store.setVisible(id: wp.id, visible: !wp.visible)
                }
                Button("Navigate", systemImage: "location.north") { navigate(to: wp) }
                Button("Delete", systemImage: "trash", role: .destructive) { store.delete(ids: [wp.id]) }
            } label: {
                Image(systemName: "ellipsis").frame(width: 44, height: 44)
            }
            .foregroundStyle(palette.inkDim)
            .accessibilityLabel("Actions for \(wp.name)")
            Button { navigate(to: wp) } label: {
                Image(systemName: "arrow.up.right").frame(width: 44, height: 44)
            }
            .fieldGlassButton()
            .accessibilityLabel("Navigate to \(wp.name)")
        }
        .padding(12)
        .fieldContentSurface(night: settings.nightMode)
    }

    private func navigate(to waypoint: Waypoint) {
        store.select(waypoint.id)
        onNavigate()
    }

    private func beginAdd(atFix: Bool) {
        if atFix {
            guard let f = location.usableFix else {
                status = "A recent, precise position is needed. You can enter coordinates instead."
                return
            }
            editorRequest = WaypointEditorRequest(lat: f.lat, lon: f.lon)
        } else {
            editorRequest = WaypointEditorRequest()
        }
    }

    private func beginEdit(_ wp: Waypoint) {
        editorRequest = WaypointEditorRequest(waypoint: wp)
    }

    private func exportBackup() {
        let doc = fieldData.backup(waypoints: store.waypoints, folders: store.folders, settings: settings.backupSettings)
        do {
            let data = try Backup.exportZip(doc)
            exportDoc = BackupDocumentFile(data: data)
            status = "Backup ready"
        } catch {
            status = "Backup failed: \(error.localizedDescription)"
        }
    }

    private func exportGpx() {
        do {
            let tracks = try fieldData.document.tracks.map { GPX.Track(name: $0.name, points: try fieldData.points(for: $0.id)) }
            let xml = GPX.build(waypoints: store.waypoints, routes: fieldData.document.graphics, tracks: tracks)
            exportGPX = GPXDocumentFile(text: xml)
            status = "GPX ready"
        } catch { status = "Export failed: \(error.localizedDescription)" }
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
                status = BackupCoordinator.restore(doc, waypoints: store, fieldData: fieldData, settings: settings)
            case .gpx:
                let xml = String(data: data, encoding: .utf8) ?? ""
                let document = try GPX.parse(xml)
                status = BackupCoordinator.restore(document, waypoints: store, fieldData: fieldData, settings: settings)
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
    static var readableContentTypes: [UTType] { [.gridFixGPX, .xml] }
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

extension UTType {
    static let gridFixGPX = UTType(exportedAs: "app.gridfix.gpx", conformingTo: .xml)
}
