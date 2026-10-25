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
    @EnvironmentObject private var lanes: NavigationLaneStore

    private var preparingOutput: Bool { fieldExport.format != nil || backupTransfer.phase == .exporting }
    private var exportUnavailable: Bool { fieldExport.format != nil || backupTransfer.phase != nil || exportFile != nil }
    private var palette: FieldPalette { FieldPalette(night: settings.nightMode) }
    @State private var editorRequest: WaypointEditorRequest?
    var onNavigate: () -> Void = {}
    var onShowMap: () -> Void = {}
    var onOrientation: () -> Void = {}
    @State private var choosingLibraryActions = false
    @State private var pendingLibraryAction: LibraryAction?
    @State private var trackActions: Backup.TrackMeta?
    @State private var pendingTrackAction: (id: String, action: String)?
    @State private var choosingSelectionAction = false
    @State private var pendingSelectionAction: String?
    @State private var choosingPasteFormat = false
    @State private var choosingExportFormat = false
    @StateObject private var listing = LibraryPresentation()
    @State private var prunedSourceRevision: UInt64?
    private var folderFilter: String? {
        get { listing.folder }
        nonmutating set { listing.setFolder(newValue) }
    }
    @ScaledMetric(relativeTo: .subheadline) private var folderPickerHeight: CGFloat = 60
    @FocusState private var searchFocused: Bool
    private var searchQuery: String { listing.query }
    private var waypointSort: WaypointSort {
        get { listing.sort }
        nonmutating set { listing.setSort(newValue) }
    }
    @State private var choosingSort = false
    @State private var status: String?
    @State private var showingLibrary = false
    @State private var showingLanes = false
    @State private var pendingLane: LaneMapAction?
    @State private var textImport: TextImportRequest?
    @State private var exportFile: FieldExportDocumentFile?
    @State private var showingImporter = false
    @State private var importKind: ImportKind = .backup
    @State private var backupPasswordRequest: BackupPasswordRequest?
    @State private var pendingProtectedBackup: (URL?,String)?
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
    @StateObject private var backupTransfer = BackupTransfer()
    @StateObject private var fieldExport = FieldExportTransfer()
    @StateObject private var fieldMutation = FieldMutation()

    private var libraryFolders: [FolderInfo] { listing.snapshot?.folders ?? [] }
    private var listedWaypoints: [Waypoint] { listing.snapshot?.waypoints ?? [] }
    private var query: String { searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    private var listedGraphics: [Backup.Graphic] { listing.snapshot?.graphics ?? [] }
    private var listedTracks: [Backup.TrackMeta] { listing.snapshot?.tracks ?? [] }
    private var listedSelection: LibrarySelection { listing.snapshot?.selection ?? LibrarySelection() }

    private enum ImportKind { case backup, text }

    var body: some View {
        ZStack {
            FieldScreenBackground()
            VStack(alignment: .leading, spacing: 0) {
                header.disabled(preparingOutput || fieldMutation.working)
                if let error = store.loadError {
                    Text(error).font(.footnote).foregroundStyle(palette.warn).padding(.horizontal,20).padding(.vertical,8)
                        .accessibilityIdentifier("waypoint-library-load-error")
                }
                Button { showingLibrary = true } label: {
                    HStack {
                        Label("Routes & tracks", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        Spacer()
                        Text("\(listing.snapshot?.routeCount ?? 0) routes · \(fieldData.document.tracks.count) tracks")
                            .font(.caption).foregroundStyle(palette.inkDim)
                        Image(systemName: "chevron.right").font(.caption)
                    }.padding(.horizontal, 20).frame(minHeight: 44)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(preparingOutput || fieldMutation.working).accessibilityIdentifier("open-field-library")
                folderPicker.disabled(preparingOutput || fieldMutation.working)
                if !lanes.lanes.isEmpty {
                    Button { showingLanes = true } label: {
                        HStack { Text("Navigation lanes · \(lanes.lanes.count)"); Spacer(); Image(systemName: "chevron.right") }
                            .padding(.horizontal,20).frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(preparingOutput || fieldMutation.working).accessibilityIdentifier("library-nav-lanes")
                }
                searchControls.disabled(preparingOutput || fieldMutation.working)
                libraryCaption.disabled(preparingOutput || fieldMutation.working)
                if let label = fieldMutation.label { ProgressView(label).tint(palette.accent).padding(.horizontal,20) }
                if let error = fieldMutation.error { Text(error).font(.footnote).foregroundStyle(palette.warn).padding(.horizontal,20) }
                if let format = fieldExport.format {
                    HStack {
                        ProgressView().tint(palette.accent)
                        Text("Preparing " + format.label + "…").font(.footnote)
                        Spacer()
                        Button("Cancel") { fieldExport.cancel(); status = "Export cancelled" }
                            .frame(minHeight: 44).accessibilityIdentifier("field-export-cancel")
                    }.padding(.horizontal,20).accessibilityIdentifier("field-export-progress")
                }
                if let phase = backupTransfer.phase {
                    HStack {
                        ProgressView().tint(palette.accent)
                        Text(phase.title).font(.footnote)
                        Spacer()
                        if phase != .restoring {
                            Button("Cancel") { backupTransfer.cancel(); status = "Backup cancelled" }
                                .frame(minHeight: 44).accessibilityIdentifier("backup-cancel")
                        }
                    }.padding(.horizontal,20).accessibilityIdentifier("backup-progress")
                }
                if listing.updating || listing.snapshot == nil && listing.error == nil {
                    ProgressView("Updating library…").tint(palette.accent)
                        .frame(maxWidth: .infinity,maxHeight: .infinity).accessibilityIdentifier("library-updating")
                } else if let error = listing.error {
                    VStack(spacing: 12) {
                        Text(error)
                        Button("Retry") { listing.retry() }
                    }.frame(maxWidth: .infinity,maxHeight: .infinity)
                } else if !query.isEmpty && listedSelection.count == 0 {
                    Text("No matching records").foregroundStyle(palette.inkDim).frame(maxWidth: .infinity,maxHeight: .infinity).accessibilityIdentifier("library-no-matches")
                } else if store.waypoints.isEmpty && fieldData.document.graphics.isEmpty && fieldData.document.tracks.isEmpty {
                    empty
                } else {
                    list.disabled(preparingOutput || fieldMutation.working)
                }
            }
            .padding(.bottom, 12)
        }
        .foregroundStyle(palette.ink)
        .environment(\.fieldNight, settings.nightMode)
        .onAppear { fieldMutation.setPresented(true); listing.activate() }
        .onDisappear { fieldMutation.setPresented(false); listing.deactivate(); searchFocused = false; backtrackWork?.cancel(); backtrackWork = nil; backtrackingID = nil; backupTransfer.cancel(); fieldExport.cancel() }
        .onReceive(store.$waypoints) { listing.setWaypoints($0) }
        .onReceive(store.$folders) { listing.setFolders($0) }
        .onReceive(fieldData.$document) { listing.setField(graphics: $0.graphics,tracks: $0.tracks) }
        .onReceive(location.$usableFix) { listing.setOrigin($0.map { .init(lat: $0.lat,lon: $0.lon) }) }
        .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in listing.refreshLocale(.current) }
        .onReceive(listing.$snapshot) { snapshot in
            guard let snapshot, prunedSourceRevision != listing.acceptedSourceRevision else { return }
            prunedSourceRevision = listing.acceptedSourceRevision
            selection.retain(waypoints: snapshot.allIDs.waypoints,graphics: snapshot.allIDs.graphics,tracks: snapshot.allIDs.tracks)
            if let id = maps.viewedTrackID, !snapshot.allIDs.tracks.contains(id) { maps.viewedTrackID = nil }
            if let folderFilter, !snapshot.folderNames.contains(folderFilter) { self.folderFilter = nil }
        }
        .sheet(isPresented: $choosingSort) {
            FieldChoiceSheet(title: "Sort waypoints",choices: WaypointSort.allCases.map { .init(id: $0.rawValue,title: $0.label) },selectedID: waypointSort.rawValue,night: settings.nightMode) { id in
                if let order = WaypointSort(rawValue: id) { waypointSort = order }
                choosingSort = false
            }
        }
        .sheet(isPresented: $choosingLibraryActions,onDismiss: runLibraryAction) {
            FieldChoiceSheet(title: "Waypoint actions",choices: LibraryAction.allCases.map { .init(id: $0.rawValue,title: $0.title,enabled: ($0 != .backup || backupTransfer.phase == nil) && ($0 != .export || !exportUnavailable)) },night: settings.nightMode) { id in
                pendingLibraryAction = LibraryAction(rawValue: id); choosingLibraryActions = false
            }
        }
        .sheet(item: $trackActions,onDismiss: runTrackAction) { track in
            FieldChoiceSheet(title: track.name,choices: trackChoices(track),night: settings.nightMode) { action in
                pendingTrackAction = (track.id,action); trackActions = nil
            }
        }
        .sheet(isPresented: $choosingSelectionAction,onDismiss: runSelectionAction) {
            FieldChoiceSheet(title: "Selected item actions",choices: [
                .init(id: "library-swap-visibility",title: "Swap map visibility"),
                .init(id: "library-delete-selected",title: "Delete selected",destructive: true)
            ],night: settings.nightMode) { action in
                pendingSelectionAction = action; choosingSelectionAction = false
            }
        }
        .confirmationDialog("Paste text",isPresented: $choosingPasteFormat,titleVisibility: .visible) {
            ForEach(TextInterchangeFormat.allCases.filter { $0.canPaste },id: \.self) { format in
                Button("Paste " + format.label) { textImport = TextImportRequest(format: format) }
            }
        }
        .confirmationDialog("Export",isPresented: $choosingExportFormat,titleVisibility: .visible) {
            Button("Export backup") { exportBackup() }.disabled(exportUnavailable)
            Button("Export protected backup") { backupPasswordRequest = .init(url: nil) }.disabled(exportUnavailable)
            Button("Export GPX") { exportOther(.gpx) }.disabled(exportUnavailable)
            Button("Export CSV") { exportOther(.csv) }.disabled(exportUnavailable)
            Button("Export GeoJSON") { exportOther(.geojson) }.disabled(exportUnavailable)
            Button("Export KML") { exportOther(.kml) }.disabled(exportUnavailable)
            Button("Export KMZ") { exportOther(.kmz) }.disabled(exportUnavailable)
            Button("Export ATAK package") { exportOther(.atak) }.disabled(exportUnavailable)
        }
        .sheet(item: $backupPasswordRequest,onDismiss: finishProtectedBackup) { request in
            BackupPasswordSheet(exporting: request.url == nil) { password in
                pendingProtectedBackup = (request.url,password); backupPasswordRequest = nil
            }
        }
        .sheet(item: $folderRequest) { request in
            LibraryFolderEditor(original: request.original,folders: libraryFolders) { name in try saveFolder(original: request.original,name: name) }
        }
        .sheet(isPresented: $showingLanes,onDismiss: {
            if let action = pendingLane { pendingLane = nil; maps.laneRequest = LaneMapRequest(action: action); onShowMap() }
        }) { NavigationLaneLibraryView { pendingLane = $0; showingLanes = false } }
        .sheet(item: $movingTrack) { track in
            LibraryTrackFolderPicker(track: track,folders: libraryFolders) { folder in try await FieldEditAction.apply(.moveTrack(track.id,folder),to: fieldData) }.id(track.id)
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
            WaypointEditor(waypoint: request.waypoint, lat: request.lat, lon: request.lon) { _ in
                status = nil
            }
        }
        .sheet(isPresented: $showingLibrary) {
            FieldLibraryView(onNavigate: { showingLibrary = false; onNavigate() },onShowMap: { showingLibrary = false; onShowMap() })
        }
        .sheet(item: $textImport) { request in
            InterchangeImportView(request: request,knownFolders: libraryFolders.map(\.name)) { document in
                let result = try await InterchangeCoordinator.apply(document,waypoints: store,field: fieldData)
                status = result.message
                return result
            }.id(request.id)
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
                      allowedContentTypes: importKind == .backup ? [.zip,.gridFixProtectedBackup,.data] : [.gridFixGPX, .gridFixGeoJSON, .gridFixKML, .gridFixKMZ, .gridFixDPK, .commaSeparatedText, .zip, .xml, .json, .data],
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
            Button { choosingLibraryActions = true } label: {
                Image(systemName: "ellipsis").frame(width: 44,height: 44).contentShape(Rectangle())
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
            LazyHStack(spacing: 8) {
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
        }.frame(height: folderPickerHeight)
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
            TextField("Search name, folder or grid",text: Binding(get: { listing.query },set: { listing.setQuery($0) }))
                .textInputAutocapitalization(.never).autocorrectionDisabled().focused($searchFocused).submitLabel(.search).onSubmit { searchFocused = false }
                .accessibilityIdentifier("library-search")
            if !searchQuery.isEmpty {
                Button { listing.setQuery("") } label: { Image(systemName: "xmark.circle.fill").frame(minWidth: 44,minHeight: 44) }
                    .accessibilityLabel("Clear library search").accessibilityIdentifier("library-search-clear")
            }
            Button { searchFocused = false; choosingSort = true } label: {
                Image(systemName: "arrow.up.arrow.down").frame(width: 44,height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain)
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
                    guard listing.isReady else { return }
                    selection = selection == listedSelection ? LibrarySelection() : listedSelection
                } label: { Image(systemName: selection == listedSelection ? "checkmark.circle.fill" : "checkmark.circle").frame(minWidth: 44,minHeight: 44) }
                    .accessibilityLabel(selection == listedSelection ? "Select none" : "Select all").accessibilityIdentifier("library-select-all").disabled(!listing.isReady)
                Button { choosingSelectionAction = true } label: {
                    Image(systemName: "ellipsis.circle").frame(minWidth: 44,minHeight: 44).contentShape(Rectangle())
                }
                    .disabled(selection.count == 0 || !listing.isReady).accessibilityLabel("Selected item actions")
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
                            selectionRow(id: point.id,name: point.name,kind: "waypoint",visible: point.visible,ids: $selection.waypoints) {
                                HStack(spacing: 12) {
                                    MilitaryMarker(symbol: point.symbol,affiliation: point.affiliation,echelon: point.echelon,rotation: point.rotation,metadata: point.metadata).frame(width: 40,height: 44).accessibilityHidden(true)
                                    waypointSummary(point)
                                }
                            }
                        } else { row(point) }
                    }
                }
                if !listedGraphics.isEmpty {
                    SectionLabel(text: "Graphics · \(listedGraphics.count)")
                    ForEach(listedGraphics) { graphic in
                        if selecting {
                            selectionRow(id: graphic.id,name: graphic.name,kind: "graphic",visible: graphic.visible,ids: $selection.graphics) { graphicSummary(graphic) }
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
                            selectionRow(id: track.id,name: track.name,kind: "track",visible: track.visible,ids: $selection.tracks) { trackSummary(track) }
                        } else { trackRow(track) }
                    }
                }
                if listedSelection.count == 0 { Text("Nothing in \(folderFilter ?? "the library") yet.").font(.footnote).foregroundStyle(palette.inkDim) }
                if let status { Text(status).font(.footnote).foregroundStyle(palette.accent).padding(.vertical,8).accessibilityIdentifier("library-status") }
                if let failure = fieldData.loadError { Text(failure).font(.footnote).foregroundStyle(palette.warn) }
            }.padding(.horizontal,20).padding(.bottom,20)
        }.accessibilityIdentifier("library-list")
    }

    private func selectionRow<Content: View>(id: String,name: String,kind: String,visible: Bool,ids: Binding<Set<String>>,@ViewBuilder content: () -> Content) -> some View {
        let selected = ids.wrappedValue.contains(id)
        return Button {
            guard listing.isReady else { return }
            if selected { ids.wrappedValue.remove(id) } else { ids.wrappedValue.insert(id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? palette.accent : palette.inkDim).frame(width: 28)
                content().frame(maxWidth: .infinity,alignment: .leading)
                if !visible { Image(systemName: "eye.slash").accessibilityLabel("Hidden on map") }
            }.padding(12).fieldContentSurface(night: settings.nightMode)
        }.buttonStyle(.plain).accessibilityLabel("\(selected ? "Deselect" : "Select") \(kind) \(name)")
            .accessibilityValue(visible ? "Map visibility on" : "Map visibility off")
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
            Button { showGraphic(graphic) } label: { graphicSummary(graphic).frame(maxWidth: .infinity,alignment: .leading).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityIdentifier("library-graphic-\(graphic.name)")
            if !graphic.visible { Image(systemName: "eye.slash").accessibilityLabel("Hidden on map").accessibilityIdentifier("library-graphic-hidden-\(graphic.name)") }
            Menu {
                Button("Show on map") { showGraphic(graphic) }
                if graphic.type == "route" { Button("Route card") { routeDetail = graphic } }
                Button(graphic.visible ? "Hide on map" : "Make visible on map") { fieldMutation.run("Saving visibility…",action: { try await FieldEditAction.apply(.setGraphicVisible(graphic.id,!graphic.visible),to: fieldData) }) }
                Button("Delete",role: .destructive) { selection = LibrarySelection(); selection.graphics = [graphic.id]; deleteSelection = true }
            } label: { Image(systemName: "ellipsis").frame(width: 44,height: 44) }.accessibilityLabel("Actions for graphic \(graphic.name)")
        }.padding(12).fieldContentSurface(night: settings.nightMode)
    }
    private func trackRow(_ track: Backup.TrackMeta) -> some View {
        HStack {
            Button { showTrack(track) } label: { trackSummary(track).frame(maxWidth: .infinity,alignment: .leading).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityIdentifier("library-track-\(track.name)")
            if !track.visible { Image(systemName: "eye.slash").accessibilityLabel("Hidden on map").accessibilityIdentifier("library-track-hidden-\(track.name)") }
            Button { trackActions = track } label: {
                Image(systemName: "ellipsis").frame(width: 44,height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Actions for track \(track.name)")
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
                    HStack {
                        Text(wp.name).font(.headline).foregroundStyle(palette.ink)
                        if wp.favorite { Image(systemName: "star.fill").foregroundStyle(palette.accent).accessibilityLabel("Favourite").accessibilityIdentifier("favorite-\(wp.name)") }
                        if !wp.visible { Image(systemName: "eye.slash").foregroundStyle(palette.ink).accessibilityLabel("Hidden on map").accessibilityIdentifier("library-waypoint-hidden-\(wp.name)") }
                    }
                    Text(MGRS.parts(lat: wp.lat, lon: wp.lon, digits: settings.mgrsDigits)?.full ?? "Outside \(settings.gridName) coverage")
                        .font(.system(.caption, design: .monospaced)).foregroundStyle(palette.inkDim)
                    if folderFilter == nil { Text(wp.folder).font(.caption).foregroundStyle(palette.inkDim) }
                    if let f = location.usableFix {
                        let nav = Geodesy.navInfo(fromLat: f.lat, fromLon: f.lon, toLat: wp.lat, toLon: wp.lon)
                        Text(Format.distance(meters: nav.distanceMeters, unit: settings.units))
                            .font(.system(.caption, design: .monospaced)).foregroundStyle(palette.inkDim)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8).contentShape(Rectangle())
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
        guard store.waypoints.contains(where: { $0.id == waypoint.id }) else { status = "This waypoint is no longer saved."; return }
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
        guard let current = store.waypoints.first(where: { $0.id == wp.id }) else { status = "This waypoint is no longer saved."; return }
        editorRequest = WaypointEditorRequest(waypoint: current)
    }

    private func pruneSelection() {
        selection.retain(waypoints: Set(store.waypoints.map(\.id)),graphics: Set(fieldData.document.graphics.map(\.id)),tracks: Set(fieldData.document.tracks.map(\.id)))
        if let id = maps.viewedTrackID, !fieldData.document.tracks.contains(where: { $0.id == id }) { maps.viewedTrackID = nil }
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
        guard let current = fieldData.document.graphics.first(where: { $0.id == graphic.id }) else { status = "This graphic is no longer saved."; return }
        maps.focusRequest = MapCameraRequest(action: .showBoundary(current.mapExtentPoints)); onShowMap()
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

    private func exportBackup(password: String? = nil) {
        guard backupTransfer.phase == nil, fieldExport.format == nil, exportFile == nil else { return }
        guard lanes.ready else { status = lanes.error ?? "Loading navigation lanes. Try again in a moment."; return }
        var doc = fieldData.backup(waypoints: store.waypoints, folders: store.folders, settings: settings.backupSettings)
        doc.navLanes = lanes.lanes
        status = nil
        backupTransfer.export(doc,password: password) { result in
            switch result {
            case .success(let data):
                exportFile = FieldExportDocumentFile(data: data,contentType: password == nil ? .zip : .gridFixProtectedBackup,filename: password == nil ? "gridfix-backup" : "gridfix-backup.mgrsgps")
                status = "Backup ready"
            case .failure(let error): status = "Backup failed: \(error.localizedDescription)"
            }
        }
    }

    private func restoreBackup(_ url: URL,password: String? = nil) {
        backupTransfer.restore(url,password: password,passwordRequired: { backupPasswordRequest = .init(url: url) },apply: { document in
            await BackupCoordinator.restore(document,waypoints: store,fieldData: fieldData,settings: settings,lanes: lanes)
        },completion: { status = $0 })
    }

    private func finishProtectedBackup() {
        guard let (url,password) = pendingProtectedBackup else { return }
        pendingProtectedBackup = nil
        if let url { restoreBackup(url,password: password) }
        else { exportBackup(password: password) }
    }

    private func exportOther(_ format: TextInterchangeFormat) {
        guard backupTransfer.phase == nil, fieldExport.format == nil, exportFile == nil else { return }
        searchFocused = false; status = nil
        prepareExport(.library(format,store.waypoints,fieldData.document))
    }
    private func prepareExport(_ request: FieldExportRequest) {
        fieldExport.start(request) { result in
            switch result {
            case .success(let prepared): exportFile = FieldExportDocumentFile(prepared); status = prepared.format.label + " ready"
            case .failure(let error): status = "Export failed: " + error.localizedDescription
            }
        }
    }

    private func runSelectionAction() {
        guard let action = pendingSelectionAction else { return }
        pendingSelectionAction = nil
        guard selection.count > 0 else { return }
        if action == "library-swap-visibility" { applyBatch(.swapVisibility) }
        else if action == "library-delete-selected" { deleteSelection = true }
    }

    private func runLibraryAction() {
        guard let action = pendingLibraryAction else { return }
        pendingLibraryAction = nil
        switch action {
        case .fix: beginAdd(atFix: true)
        case .coordinates: beginAdd(atFix: false)
        case .select: selecting = true; selection = LibrarySelection()
        case .folder: folderRequest = LibraryFolderRequest()
        case .orientation: onOrientation()
        case .export: choosingExportFormat = true
        case .backup: importKind = .backup; showingImporter = true
        case .file: importKind = .text; showingImporter = true
        case .paste: choosingPasteFormat = true
        }
    }
    private func trackChoices(_ track: Backup.TrackMeta) -> [FieldChoice] {
        var choices: [FieldChoice] = [.init(id: "show",title: "Show on map"),.init(id: "details",title: "Details")]
        if maps.viewedTrackID == track.id { choices.append(.init(id: "stop",title: "Stop viewing")) }
        choices += [.init(id: "move",title: "Move to folder"),
                    .init(id: "backtrack",title: backtrackingID == track.id ? "Building backtrack…" : "Create backtrack route",
                          accessibilityIdentifier: "backtrack-track-"+track.name,enabled: backtrackingID == nil && track.pointCount >= 2),
                    .init(id: "visibility",title: track.visible ? "Hide on map" : "Make visible on map"),
                    .init(id: "export",title: "Export GPX",enabled: !exportUnavailable),.init(id: "delete",title: "Delete",destructive: true)]
        return choices
    }
    private func runTrackAction() {
        guard let pending = pendingTrackAction else { return }
        pendingTrackAction = nil
        guard let track = fieldData.document.tracks.first(where: { $0.id == pending.id }) else { return }
        switch pending.action {
        case "show": showTrack(track)
        case "details": trackDetail = track
        case "stop": maps.viewedTrackID = nil
        case "move": movingTrack = track
        case "backtrack": if backtrackingID == nil && track.pointCount >= 2 { backtrack(track) }
        case "visibility": fieldMutation.run("Saving visibility…",action: { try await FieldEditAction.apply(.setTrackVisible(track.id,!track.visible),to: fieldData) })
        case "export":
            guard backupTransfer.phase == nil, fieldExport.format == nil, exportFile == nil else { return }
            searchFocused = false; status = nil
            prepareExport(.track(track,fieldData.document.trackFiles[track.id] ?? Data()))
        case "delete": selection = LibrarySelection(); selection.tracks = [track.id]; deleteSelection = true
        default: break
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            if importKind == .text { textImport = TextImportRequest(url: url); return }
            guard backupTransfer.phase == nil else { return }
            status = nil
            restoreBackup(url)
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
