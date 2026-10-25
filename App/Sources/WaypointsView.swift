import GridFixCore
import SwiftUI
import UniformTypeIdentifiers

/// Local waypoints with coordinate editing, folder visibility, and navigation.
struct WaypointsView: View {
    @EnvironmentObject private var store: WaypointStore
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var fieldData: FieldDataStore
    @EnvironmentObject private var maps: MapLayerStore

    private var palette: FieldPalette { FieldPalette(night: settings.nightMode) }
    @State private var editorRequest: WaypointEditorRequest?
    var onNavigate: () -> Void = {}
    var onShowMap: () -> Void = {}
    var onOrientation: () -> Void = {}
    @State private var choosingPasteFormat = false
    @State private var choosingExportFormat = false
    @State private var folderFilter: String?
    @FocusState private var searchFocused: Bool
    @State private var searchQuery = ""
    @State private var waypointSort: WaypointSort = .distance
    @State private var status: String?
    @State private var showingLibrary = false
    @State private var textImport: TextImportRequest?
    @State private var exportFile: FieldExportDocumentFile?
    @State private var showingImporter = false
    @State private var importKind: ImportKind = .backup
    @State private var selecting = false
    @State private var selection = LibrarySelection()
    @State private var deleteSelection = false
    @State private var folderRequest: LibraryFolderRequest?
    @State private var folderToDelete: String?
    @State private var movingTrack: Backup.TrackMeta?
    @State private var routeDetail: Backup.Graphic?
    @State private var trackDetail: Backup.TrackMeta?
    @State private var backtrackingID: String?
    @State private var backtrackWork: Task<Void,Never>?

    private var libraryFolders: [FolderInfo] {
        var folders = store.folders
        for name in fieldData.document.graphics.map(\.folder)+fieldData.document.tracks.map(\.folder) {
            if !folders.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { folders.append(.init(name: name)) }
        }
        return folders.sorted { a,b in
            if a.name == Folders.defaultFolder { return b.name != Folders.defaultFolder }
            if b.name == Folders.defaultFolder { return false }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
    private var listedWaypoints: [Waypoint] {
        LibraryListing.waypoints(store.waypoints,folder: folderFilter,origin: location.usableFix.map { .init(lat: $0.lat,lon: $0.lon) },query: searchQuery,sort: waypointSort)
    }
    private var query: String { searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    private var listedGraphics: [Backup.Graphic] { fieldData.document.graphics.filter { (folderFilter == nil || $0.folder.caseInsensitiveCompare(folderFilter!) == .orderedSame) && (query.isEmpty || $0.name.lowercased().contains(query)) } }
    private var listedTracks: [Backup.TrackMeta] { fieldData.document.tracks.filter { (folderFilter == nil || $0.folder.caseInsensitiveCompare(folderFilter!) == .orderedSame) && (query.isEmpty || $0.name.lowercased().contains(query)) } }
    private var listedSelection: LibrarySelection {
        var ids = LibrarySelection(); ids.waypoints = Set(listedWaypoints.map(\.id)); ids.graphics = Set(listedGraphics.map(\.id)); ids.tracks = Set(listedTracks.map(\.id)); return ids
    }

    private enum ImportKind { case backup, text }

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
                searchControls
                libraryCaption
                if !query.isEmpty && listedSelection.count == 0 {
                    Text("No matching records").foregroundStyle(palette.inkDim).frame(maxWidth: .infinity,maxHeight: .infinity).accessibilityIdentifier("library-no-matches")
                } else if store.waypoints.isEmpty && fieldData.document.graphics.isEmpty && fieldData.document.tracks.isEmpty {
                    empty
                } else {
                    list
                }
            }
            .padding(.bottom, 12)
        }
        .foregroundStyle(palette.ink)
        .environment(\.fieldNight, settings.nightMode)
        .onDisappear { searchFocused = false; backtrackWork?.cancel(); backtrackWork = nil; backtrackingID = nil }
        .onChange(of: store.waypoints.map(\.id)) { _ in pruneSelection() }
        .onChange(of: fieldData.document.graphics.map(\.id)) { _ in pruneSelection() }
        .onChange(of: fieldData.document.tracks.map(\.id)) { _ in pruneSelection() }
        .confirmationDialog("Paste text",isPresented: $choosingPasteFormat,titleVisibility: .visible) {
            ForEach(TextInterchangeFormat.allCases.filter { $0.canPaste },id: \.self) { format in
                Button("Paste " + format.label) { textImport = TextImportRequest(format: format) }
            }
        }
        .confirmationDialog("Export",isPresented: $choosingExportFormat,titleVisibility: .visible) {
            Button("Export backup") { exportBackup() }
            Button("Export GPX") { exportGpx() }
            Button("Export CSV") { exportOther(.csv) }
            Button("Export GeoJSON") { exportOther(.geojson) }
            Button("Export KML") { exportOther(.kml) }
            Button("Export KMZ") { exportOther(.kmz) }
            Button("Export ATAK package") { exportOther(.atak) }
        }
        .sheet(item: $folderRequest) { request in
            LibraryFolderEditor(original: request.original,folders: libraryFolders) { name in try saveFolder(original: request.original,name: name) }
        }
        .sheet(item: $movingTrack) { track in
            LibraryTrackFolderPicker(track: track,folders: libraryFolders) { try fieldData.moveTrack(track.id,to: $0) }
        }
        .sheet(item: $routeDetail) { route in
            NavigationStack {
                RouteDetailView(routeID: route.id,onNavigate: { routeDetail = nil; onNavigate() })
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { routeDetail = nil } } }
            }.fieldSheetAppearance()
        }
        .sheet(item: $trackDetail) { track in
            NavigationStack {
                TrackDetailView(trackID: track.id,onShowMap: { trackDetail = nil; onShowMap() })
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { trackDetail = nil } } }
            }.fieldSheetAppearance()
        }
        .alert("Delete \(selection.count) selected items?",isPresented: $deleteSelection) {
            Button("Delete",role: .destructive) { applyBatch(.delete) }
            Button("Cancel",role: .cancel) { if !selecting { selection = LibrarySelection() } }
        } message: { Text("\(selection.waypoints.count) waypoints, \(selection.graphics.count) graphics and \(selection.tracks.count) finished tracks. Selected track point logs are deleted too.") }
        .confirmationDialog("Delete folder?",isPresented: Binding(get: { folderToDelete != nil },set: { if !$0 { folderToDelete = nil } }),titleVisibility: .visible,presenting: folderToDelete) { name in
            Button("Keep contents in Base") { removeFolder(name,deleteContents: false) }
            Button("Delete folder and contents",role: .destructive) { removeFolder(name,deleteContents: true) }
            Button("Cancel",role: .cancel) {}
        } message: { name in Text("Remove \(name) and move its waypoints, graphics and finished tracks to Base, or delete them with the folder. Active recording is kept.") }
        .sheet(item: $editorRequest) { request in
            WaypointEditor(waypoint: request.waypoint, lat: request.lat, lon: request.lon) { draft in
                if let editing = request.waypoint { store.update(id: editing.id, draft: draft) }
                else { store.add(draft) }
                status = nil
            }
        }
        .sheet(isPresented: $showingLibrary) {
            FieldLibraryView(onNavigate: { showingLibrary = false; onNavigate() },onShowMap: { showingLibrary = false; onShowMap() })
        }
        .sheet(item: $textImport) { request in
            InterchangeImportView(request: request,knownFolders: libraryFolders.map(\.name)) { document in
                let result = InterchangeCoordinator.apply(document,waypoints: store,field: fieldData)
                status = result.message
                return result
            }
        }
        .fileExporter(isPresented: Binding(
            get: { exportFile != nil },
            set: { if !$0 { exportFile = nil } }
        ), document: exportFile, contentType: exportFile?.contentType ?? .data, defaultFilename: exportFile?.filename ?? "gridfix") { result in
            if case .failure(let error) = result {
                let failure = error as NSError
                if failure.domain != NSCocoaErrorDomain || failure.code != NSUserCancelledError {
                    status = "Export failed: " + error.localizedDescription
                }
            }
            exportFile = nil
        }
        .fileImporter(isPresented: $showingImporter,
                      allowedContentTypes: importKind == .backup ? [.zip] : [.gridFixGPX, .gridFixGeoJSON, .gridFixKML, .gridFixKMZ, .gridFixDPK, .commaSeparatedText, .zip, .xml, .json, .data],
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
                Button("Select items") { selecting = true; selection = LibrarySelection() }.accessibilityIdentifier("library-select")
                Button("New folder") { folderRequest = LibraryFolderRequest() }
                Button("Orientation",action: onOrientation).accessibilityIdentifier("library-orientation-shortcut")
                Divider()
                Button("Export") { choosingExportFormat = true }
                Button("Import backup") { importKind = .backup; showingImporter = true }
                Button("Import field file") { importKind = .text; showingImporter = true }.accessibilityIdentifier("import-field-file")
                Button("Paste text") { choosingPasteFormat = true }
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
            Text("Add one at your current fix, or import a backup, GPX, KML/KMZ, CSV, GeoJSON or ATAK package.")
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
                ForEach(libraryFolders) { folder in
                    folderChip(folder.name, selected: folderFilter == folder.name) { folderFilter = folder.name }
                        .contextMenu {
                            Button(folder.visible ? "Hide folder on map" : "Show folder on map") { perform { try store.setLibraryFolderVisible(folder.name,visible: !folder.visible) } }
                            if folder.name != Folders.defaultFolder {
                                Button("Rename folder") { folderRequest = LibraryFolderRequest(original: folder.name) }
                                Button("Delete folder",role: .destructive) { folderToDelete = folder.name }
                            }
                        }
                }
                Button { folderRequest = LibraryFolderRequest() } label: { Label("Folder",systemImage: "folder.badge.plus").padding(10) }.accessibilityIdentifier("library-new-folder")
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

    private var searchControls: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(palette.inkDim)
            TextField("Search name, folder or grid",text: $searchQuery)
                .textInputAutocapitalization(.never).autocorrectionDisabled().focused($searchFocused).submitLabel(.search).onSubmit { searchFocused = false }
                .accessibilityIdentifier("library-search")
                .onChange(of: searchQuery) { value in if value.count > 60 { searchQuery = String(value.prefix(60)) } }
            if !searchQuery.isEmpty {
                Button { searchQuery = "" } label: { Image(systemName: "xmark.circle.fill").frame(minWidth: 44,minHeight: 44) }
                    .accessibilityLabel("Clear library search").accessibilityIdentifier("library-search-clear")
            }
            Menu {
                ForEach(WaypointSort.allCases,id: \.self) { order in
                    Button(order.label,systemImage: waypointSort == order ? "checkmark" : "arrow.up.arrow.down") { waypointSort = order; searchFocused = false }
                }
            } label: { Image(systemName: "arrow.up.arrow.down").frame(width: 44,height: 44) }
                .accessibilityLabel("Sort waypoints, \(waypointSort.label)").accessibilityIdentifier("library-sort")
        }.padding(.horizontal,12).frame(minHeight: 44)
            .fieldContentSurface(night: settings.nightMode).padding(.horizontal,20).padding(.vertical,4)
    }

    private var libraryCaption: some View {
        HStack(spacing: 10) {
            if selecting {
                Text("\(selection.count) selected").font(.caption.bold()).accessibilityIdentifier("library-selected-count")
                Spacer()
                Button {
                    selection = selection == listedSelection ? LibrarySelection() : listedSelection
                } label: { Image(systemName: selection == listedSelection ? "checkmark.circle.fill" : "checkmark.circle").frame(minWidth: 44,minHeight: 44) }
                    .accessibilityLabel(selection == listedSelection ? "Select none" : "Select all").accessibilityIdentifier("library-select-all")
                Menu {
                    Button("Swap map visibility") { applyBatch(.swapVisibility) }.accessibilityIdentifier("library-swap-visibility")
                    Button("Delete selected",role: .destructive) { deleteSelection = true }.accessibilityIdentifier("library-delete-selected")
                } label: { Image(systemName: "ellipsis.circle").frame(minWidth: 44,minHeight: 44) }
                    .disabled(selection.count == 0).accessibilityLabel("Selected item actions")
                Button("Done") { selecting = false; selection = LibrarySelection() }.accessibilityIdentifier("library-selection-done")
            } else {
                Text("\(waypointSort.label) · \(listedWaypoints.count) waypoints · \(listedGraphics.count) graphics · \(listedTracks.count) tracks")
                    .font(.caption).foregroundStyle(palette.inkDim).accessibilityIdentifier("library-listed-count")
                Spacer(minLength: 0)
                if let folder = libraryFolders.first(where: { $0.name == folderFilter }) ?? (libraryFolders.count == 1 ? libraryFolders.first : nil) {
                    Button { perform { try store.setLibraryFolderVisible(folder.name,visible: !folder.visible) } } label: {
                        Image(systemName: folder.visible ? "eye" : "eye.slash").frame(minWidth: 44,minHeight: 44)
                    }.accessibilityLabel(folder.visible ? "Hide folder" : "Show folder").accessibilityIdentifier("folder-visibility-\(folder.name)")
                    if folder.name != Folders.defaultFolder {
                        Menu {
                            Button("Rename folder") { folderRequest = LibraryFolderRequest(original: folder.name) }
                            Button("Delete folder",role: .destructive) { folderToDelete = folder.name }
                        } label: { Image(systemName: "folder.badge.gearshape").frame(minWidth: 44,minHeight: 44) }.accessibilityLabel("Folder options")
                    }
                }
                Button { selecting = true; selection = LibrarySelection() } label: { Image(systemName: "checkmark.circle").frame(minWidth: 44,minHeight: 44) }.accessibilityLabel("Select items").accessibilityIdentifier("library-select-button")
            }
        }.font(.caption).padding(.horizontal,20).frame(minHeight: 44)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading,spacing: 12) {
                if let folder = libraryFolders.first(where: { $0.name == folderFilter }), !folder.visible {
                    Text("\(folder.name) is hidden on the map. Its saved records remain listed here.").font(.footnote).foregroundStyle(palette.inkDim)
                }
                if !listedWaypoints.isEmpty {
                    SectionLabel(text: "Waypoints · \(listedWaypoints.count)")
                    ForEach(listedWaypoints) { point in
                        if selecting {
                            selectionRow(id: point.id,name: point.name,kind: "waypoint",ids: $selection.waypoints) {
                                HStack(spacing: 12) {
                                    MilitaryMarker(symbol: point.symbol,affiliation: point.affiliation,echelon: point.echelon,rotation: point.rotation,metadata: point.metadata).frame(width: 40,height: 44).accessibilityHidden(true)
                                    waypointSummary(point)
                                }.opacity(point.visible ? 1 : 0.5)
                            }
                        } else { row(point) }
                    }
                }
                if !listedGraphics.isEmpty {
                    SectionLabel(text: "Graphics · \(listedGraphics.count)")
                    ForEach(listedGraphics) { graphic in
                        if selecting {
                            selectionRow(id: graphic.id,name: graphic.name,kind: "graphic",ids: $selection.graphics) { graphicSummary(graphic).opacity(graphic.visible ? 1 : 0.5) }
                        } else { graphicRow(graphic) }
                    }
                    if let folderFilter, listedGraphics.count > 1 {
                        Button("Clear \(listedGraphics.count) graphics in \(folderFilter)",role: .destructive) {
                            selection = LibrarySelection(); selection.graphics = Set(listedGraphics.map(\.id)); deleteSelection = true
                        }.font(.caption).frame(minHeight: 44).accessibilityIdentifier("library-clear-graphics")
                    }
                }
                if !listedTracks.isEmpty {
                    SectionLabel(text: "Tracks · \(listedTracks.count)")
                    ForEach(listedTracks) { track in
                        if selecting {
                            selectionRow(id: track.id,name: track.name,kind: "track",ids: $selection.tracks) { trackSummary(track).opacity(track.visible ? 1 : 0.5) }
                        } else { trackRow(track) }
                    }
                }
                if listedSelection.count == 0 { Text("Nothing in \(folderFilter ?? "the library") yet.").font(.footnote).foregroundStyle(palette.inkDim) }
                if let status { Text(status).font(.footnote).foregroundStyle(palette.accent).padding(.vertical,8).accessibilityIdentifier("library-status") }
                if let failure = fieldData.loadError { Text(failure).font(.footnote).foregroundStyle(palette.warn) }
            }.padding(.horizontal,20).padding(.bottom,20)
        }.accessibilityIdentifier("library-list")
    }

    private func selectionRow<Content: View>(id: String,name: String,kind: String,ids: Binding<Set<String>>,@ViewBuilder content: () -> Content) -> some View {
        let selected = ids.wrappedValue.contains(id)
        return Button {
            if selected { ids.wrappedValue.remove(id) } else { ids.wrappedValue.insert(id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? palette.accent : palette.inkDim).frame(width: 28)
                content().frame(maxWidth: .infinity,alignment: .leading)
            }.padding(12).fieldContentSurface(night: settings.nightMode)
        }.buttonStyle(.plain).accessibilityLabel("\(selected ? "Deselect" : "Select") \(kind) \(name)")
            .accessibilityIdentifier("select-\(kind)-\(id)").accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func waypointSummary(_ point: Waypoint) -> some View {
        VStack(alignment: .leading,spacing: 5) {
            HStack { Text(point.name).font(.headline); if point.favorite { Image(systemName: "star.fill").foregroundStyle(palette.accent).accessibilityLabel("Favourite") } }
            Text(MGRS.parts(lat: point.lat,lon: point.lon,digits: settings.mgrsDigits)?.full ?? "Outside \(settings.gridName) coverage").font(.system(.caption,design: .monospaced))
            if folderFilter == nil { Text(point.folder).font(.caption).foregroundStyle(palette.inkDim) }
        }
    }
    private func graphicSummary(_ graphic: Backup.Graphic) -> some View {
        VStack(alignment: .leading,spacing: 5) {
            Text(graphic.name).font(.headline)
            Text("\(GraphicTypes.label(graphic.type)) · \(graphic.points.count) points\(folderFilter == nil ? " · "+graphic.folder : "")").font(.caption).foregroundStyle(palette.inkDim)
        }
    }
    private func trackSummary(_ track: Backup.TrackMeta) -> some View {
        VStack(alignment: .leading,spacing: 5) {
            Text(track.name).font(.headline)
            Text("\(track.pointCount) points · \(Format.distance(meters: track.distanceM,unit: settings.units))\(folderFilter == nil ? " · "+track.folder : "")").font(.caption).foregroundStyle(palette.inkDim)
        }
    }
    private func graphicRow(_ graphic: Backup.Graphic) -> some View {
        HStack {
            Button { showGraphic(graphic) } label: { graphicSummary(graphic).frame(maxWidth: .infinity,alignment: .leading).opacity(graphic.visible ? 1 : 0.5) }.buttonStyle(.plain).accessibilityIdentifier("library-graphic-\(graphic.name)")
            if !graphic.visible { Image(systemName: "eye.slash").accessibilityLabel("Hidden on map").accessibilityIdentifier("library-graphic-hidden-\(graphic.name)") }
            Menu {
                Button("Show on map") { showGraphic(graphic) }
                if graphic.type == "route" { Button("Route card") { routeDetail = graphic } }
                Button(graphic.visible ? "Hide on map" : "Make visible on map") { perform { try fieldData.applyLibraryBatch(graphicIDs: [graphic.id],trackIDs: [],action: .swapVisibility) } }
                Button("Delete",role: .destructive) { selection = LibrarySelection(); selection.graphics = [graphic.id]; deleteSelection = true }
            } label: { Image(systemName: "ellipsis").frame(width: 44,height: 44) }.accessibilityLabel("Actions for graphic \(graphic.name)")
        }.padding(12).fieldContentSurface(night: settings.nightMode)
    }
    private func trackRow(_ track: Backup.TrackMeta) -> some View {
        HStack {
            Button { showTrack(track) } label: { trackSummary(track).frame(maxWidth: .infinity,alignment: .leading).opacity(track.visible ? 1 : 0.5) }.buttonStyle(.plain).accessibilityIdentifier("library-track-\(track.name)")
            if !track.visible { Image(systemName: "eye.slash").accessibilityLabel("Hidden on map").accessibilityIdentifier("library-track-hidden-\(track.name)") }
            Menu {
                Button("Show on map") { showTrack(track) }
                Button("Details") { trackDetail = track }
                if maps.viewedTrackID == track.id { Button("Stop viewing") { maps.viewedTrackID = nil } }
                Button("Move to folder") { movingTrack = track }
                Button(backtrackingID == track.id ? "Building backtrack…" : "Create backtrack route") { backtrack(track) }
                    .disabled(backtrackingID != nil || track.pointCount < 2).accessibilityIdentifier("backtrack-track-\(track.name)")
                Button(track.visible ? "Hide on map" : "Make visible on map") { perform { try fieldData.setTrackVisible(track.id,visible: !track.visible) } }
                Button("Export GPX") {
                    perform {
                        let xml = GPX.build(waypoints: [],tracks: [.init(name: track.name,points: try fieldData.points(for: track.id))])
                        exportFile = FieldExportDocumentFile(data: Data(xml.utf8),contentType: .gridFixGPX)
                    }
                }
                Button("Delete",role: .destructive) { selection = LibrarySelection(); selection.tracks = [track.id]; deleteSelection = true }
            } label: { Image(systemName: "ellipsis").frame(width: 44,height: 44) }.accessibilityLabel("Actions for track \(track.name)")
        }.padding(12).fieldContentSurface(night: settings.nightMode)
    }

    private func row(_ wp: Waypoint) -> some View {
        HStack(alignment: .center, spacing: 12) {
            MilitaryMarker(symbol: wp.symbol,affiliation: wp.affiliation,echelon: wp.echelon,rotation: wp.rotation,metadata: wp.metadata)
                .frame(width: 44, height: 48)
                .background(palette.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            Button { beginEdit(wp) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Text(wp.name).font(.headline).foregroundStyle(wp.visible ? palette.ink : palette.inkDim); if wp.favorite { Image(systemName: "star.fill").foregroundStyle(palette.accent).accessibilityLabel("Favourite").accessibilityIdentifier("favorite-\(wp.name)") } }
                    Text(MGRS.parts(lat: wp.lat, lon: wp.lon, digits: settings.mgrsDigits)?.full ?? "Outside \(settings.gridName) coverage")
                        .font(.system(.caption, design: .monospaced)).foregroundStyle(palette.inkDim)
                    if folderFilter == nil { Text(wp.folder).font(.caption).foregroundStyle(palette.inkDim) }
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
                Button(wp.favorite ? "Remove favourite" : "Favourite",systemImage: wp.favorite ? "star.slash" : "star") { perform { try store.setFavorite(id: wp.id,favorite: !wp.favorite) } }.accessibilityIdentifier("toggle-favorite-\(wp.name)")
                Button(wp.visible ? "Hide on map" : "Make visible on map", systemImage: wp.visible ? "eye.slash" : "eye") {
                    perform { try store.applyLibraryBatch(ids: [wp.id],action: .swapVisibility) }
                }
                Button("Navigate", systemImage: "location.north") { navigate(to: wp) }
                Button("Show on map",systemImage: "map") { maps.focusRequest = MapCameraRequest(action: .locate(wp.lat,wp.lon)); onShowMap() }
                Button("Delete", systemImage: "trash", role: .destructive) { selection = LibrarySelection(); selection.waypoints = [wp.id]; deleteSelection = true }
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

    private func pruneSelection() {
        selection.retain(waypoints: Set(store.waypoints.map(\.id)),graphics: Set(fieldData.document.graphics.map(\.id)),tracks: Set(fieldData.document.tracks.map(\.id)))
        if let id = maps.viewedTrackID, !fieldData.document.tracks.contains(where: { $0.id == id }) { maps.viewedTrackID = nil }
        if let folderFilter, !libraryFolders.contains(where: { $0.name == folderFilter }) { self.folderFilter = nil }
    }

    /// Like Android, repositories commit independently. Completed IDs leave the
    /// selection immediately, so a retry cannot swap their visibility twice.
    private func applyBatch(_ action: LibraryBatchAction) {
        let result = LibraryBatches.apply(selection,action: action,waypoints: store,field: fieldData)
        selection = result.remaining
        if let failure = result.failure {
            selecting = selection.count > 0
            status = "\(result.completed) items updated; remaining items unchanged. \(failure)"
        } else {
            selecting = false
            status = "\(action == .delete ? "Deleted" : "Swapped visibility for") \(result.completed) items"
        }
    }

    private func saveFolder(original: String?,name: String) throws {
        if let original {
            let target = Folders.match(known: libraryFolders.map(\.name).filter { $0.caseInsensitiveCompare(original) != .orderedSame },raw: name)
            try fieldData.changeLibraryFolder(from: original,to: target)
            do { folderFilter = try store.renameLibraryFolder(from: original,to: target) }
            catch { throw LibraryActionError.partial("Graphics and tracks moved. Retry to finish updating waypoints and folder settings. \(error.localizedDescription)") }
        } else { folderFilter = try store.createLibraryFolder(name) }
        selecting = false; selection = LibrarySelection(); status = nil
    }
    private func removeFolder(_ name: String,deleteContents: Bool) {
        do {
            try fieldData.changeLibraryFolder(from: name,to: nil,deleteContents: deleteContents)
            do { try store.removeLibraryFolder(name,deleteContents: deleteContents) }
            catch { throw LibraryActionError.partial("Graphics and tracks updated. Retry to finish updating waypoints and folder settings. \(error.localizedDescription)") }
            folderFilter = nil; pruneSelection(); status = deleteContents ? "Folder and its contents deleted" : "Folder removed; contents kept in Base"
        } catch { status = error.localizedDescription }
    }
    private func showGraphic(_ graphic: Backup.Graphic) {
        maps.focusRequest = MapCameraRequest(action: .showBoundary(graphic.mapExtentPoints)); onShowMap()
    }
    private func showTrack(_ track: Backup.TrackMeta) {
        perform {
            let points = try fieldData.points(for: track.id).map { GeoPoint(lat: $0.lat,lon: $0.lon) }
            guard !points.isEmpty else { throw LibraryActionError.partial("This track has no saved points to show.") }
            if libraryFolders.first(where: { $0.name == track.folder })?.visible == false { try store.setLibraryFolderVisible(track.folder,visible: true) }
            maps.viewedTrackID = track.id; maps.focusRequest = MapCameraRequest(action: .showBoundary(points)); onShowMap()
        }
    }
    private func backtrack(_ track: Backup.TrackMeta) {
        guard backtrackingID == nil else { return }
        backtrackingID = track.id; status = "Building backtrack route…"
        backtrackWork = Task {
            do {
                let route = try await TrackBacktrackAction.create(track: track,field: fieldData,waypoints: store)
                backtrackingID = nil; backtrackWork = nil
                status = "Backtrack saved with \(route.points.count) vertices. Review the simplified route before following it."
                maps.focusRequest = MapCameraRequest(action: .showBoundary(route.mapExtentPoints)); onShowMap()
            } catch {
                backtrackingID = nil; backtrackWork = nil
                if !(error is CancellationError) { status = "Backtrack failed: \(error.localizedDescription)" }
            }
        }
    }
    private func perform(_ action: () throws -> Void) { do { try action(); status = nil } catch { status = error.localizedDescription } }

    private func exportBackup() {
        let doc = fieldData.backup(waypoints: store.waypoints, folders: store.folders, settings: settings.backupSettings)
        do {
            let data = try Backup.exportZip(doc)
            exportFile = FieldExportDocumentFile(data: data,contentType: .zip,filename: "gridfix-backup")
            status = "Backup ready"
        } catch {
            status = "Backup failed: \(error.localizedDescription)"
        }
    }

    private func exportGpx() {
        do {
            let tracks = try fieldData.document.tracks.map { GPX.Track(name: $0.name, points: try fieldData.points(for: $0.id)) }
            let xml = GPX.build(waypoints: store.waypoints, routes: fieldData.document.graphics, tracks: tracks)
            exportFile = FieldExportDocumentFile(data: Data(xml.utf8),contentType: .gridFixGPX)
            status = "GPX ready"
        } catch { status = "Export failed: \(error.localizedDescription)" }
    }

    private func exportOther(_ format: TextInterchangeFormat) {
        do {
            if format == .csv {
                exportFile = FieldExportDocumentFile(data: Data(CSV.build(store.waypoints).utf8),contentType: .commaSeparatedText)
            } else if format == .atak {
                let routes = fieldData.document.graphics.filter { $0.type == "route" }
                exportFile = FieldExportDocumentFile(data: try ATAKPackage.build(waypoints: store.waypoints,routes: routes),contentType: .zip,filename: "gridfix-datapackage")
            } else {
                let tracks = try fieldData.document.tracks.map { GPX.Track(name: $0.name,points: try fieldData.points(for: $0.id)) }
                if format == .kmz {
                    exportFile = FieldExportDocumentFile(data: try KMZ.build(waypoints: store.waypoints,graphics: fieldData.document.graphics,tracks: tracks),contentType: .gridFixKMZ)
                } else {
                    let text = try format == .kml ? KML.build(waypoints: store.waypoints,graphics: fieldData.document.graphics,tracks: tracks) : GeoJSON.build(waypoints: store.waypoints,graphics: fieldData.document.graphics,tracks: tracks)
                    exportFile = FieldExportDocumentFile(data: Data(text.utf8),contentType: format == .kml ? .gridFixKML : .gridFixGeoJSON)
                }
            }
            status = format.label + " ready"
        } catch { status = "Export failed: \(error.localizedDescription)" }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            if importKind == .text { textImport = TextImportRequest(url: url); return }
            let doc = try InterchangeFileReader.backup(url)
            status = BackupCoordinator.restore(doc,waypoints: store,fieldData: fieldData,settings: settings)
        } catch { status = "Import failed: \(error.localizedDescription)" }
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

private enum LibraryActionError: LocalizedError {
    case partial(String)
    var errorDescription: String? { if case let .partial(message) = self { return message }; return nil }
}

struct TextDocumentFile: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText,.gridFixGeoJSON,.json,.gridFixKML] }
    var text: String
    var contentType: UTType
    init(text: String,contentType: UTType) { self.text = text; self.contentType = contentType }
    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(),as: UTF8.self)
        contentType = configuration.contentType
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}

extension UTType {
    static let gridFixGeoJSON = UTType(exportedAs: "app.gridfix.geojson",conformingTo: .json)
}

struct BinaryInterchangeDocumentFile: FileDocument {
    static var readableContentTypes: [UTType] { [.zip,.gridFixKMZ,.gridFixDPK] }
    var data: Data
    var contentType: UTType
    init(data: Data,contentType: UTType) { self.data = data; self.contentType = contentType }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data(); contentType = configuration.contentType
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

extension UTType {
    static let gridFixKML = UTType(importedAs: "com.google.earth.kml",conformingTo: .xml)
    static let gridFixKMZ = UTType(importedAs: "com.google.earth.kmz",conformingTo: .zip)
    static let gridFixDPK = UTType(importedAs: "app.gridfix.dpk",conformingTo: .zip)
}
