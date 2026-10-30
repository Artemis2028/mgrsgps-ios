import Foundation

extension LibraryListing {
    /// Immutable search/order keys. Metadata-only edits reuse coordinate grids
    /// and name keys; each new input order still establishes its own stable ties.
    public struct Index: Sendable {
        private struct Entry: Sendable {
            let order: OrderingEntry
            let name: String
            let folder: String
            let designation: String
            let grid: String?
        }
        private let entries: [Entry]
        public let ids: Set<String>

        public init(_ points: [Waypoint],reusing previous: Index? = nil) throws {
            let old = Dictionary((previous?.entries ?? []).map { ($0.order.point.id,$0) },uniquingKeysWith: { first,_ in first })
            var entries: [Entry] = []; entries.reserveCapacity(points.count)
            for (index,point) in points.enumerated() {
                if index%64 == 0 { try Task.checkCancellation() }
                let prior = old[point.id]
                // Swift equality folds canonical equivalents; Java ordering
                // compares code points, so cached keys require identical bytes.
                let unchangedName = prior.map { $0.order.point.name.utf8.elementsEqual(point.name.utf8) } ?? false
                let nameKey = unchangedName ? prior!.order.nameKey : LibraryListing.caseInsensitiveKey(point.name)
                let grid: String?
                if let prior,prior.order.point.lat == point.lat,prior.order.point.lon == point.lon { grid = prior.grid }
                else { grid = MGRS.string(lat: point.lat,lon: point.lon,digits: 10)?.lowercased().replacingOccurrences(of: " ",with: "") }
                entries.append(Entry(order: OrderingEntry(index: index,point: point,nameKey: nameKey),name: point.name.lowercased(),folder: point.folder.lowercased(),designation: point.designation.lowercased(),grid: grid))
            }
            try Task.checkCancellation()
            self.entries = entries; ids = Set(points.map(\.id))
        }

        public func listed(folder: String?,origin: GeoPoint?,query: String,sort: WaypointSort) throws -> [Waypoint] {
            try Task.checkCancellation()
            let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), compact = q.replacingOccurrences(of: " ",with: "")
            let matches = entries.filter { entry in
                guard folder == nil || entry.order.point.folder.caseInsensitiveCompare(folder!) == .orderedSame else { return false }
                return q.isEmpty || entry.name.contains(q) || entry.folder.contains(q) || entry.designation.contains(q)
                    || (compact.utf16.count >= 3 && (entry.grid?.contains(compact) ?? false))
            }
            let result = LibraryListing.ordered(matches.map(\.order),origin: origin,sort: sort)
            try Task.checkCancellation()
            return result
        }
    }

    public struct Snapshot: Sendable {
        public let waypoints: [Waypoint]
        public let graphics: [Backup.Graphic]
        public let tracks: [Backup.TrackMeta]
        public let folders: [FolderInfo]
        public let folderNames: Set<String>
        public let selection: LibrarySelection
        public let allIDs: LibrarySelection
        public let routeCount: Int
    }

    public struct Catalog: Sendable {
        public let index: Index
        private let graphics: [Backup.Graphic]
        private let tracks: [Backup.TrackMeta]
        private let folders: [FolderInfo]
        private let allIDs: LibrarySelection
        private let routeCount: Int

        public init(index: Index,folders: [FolderInfo],graphics: [Backup.Graphic],tracks: [Backup.TrackMeta],locale: Locale = .current) throws {
            self.index = index; self.graphics = graphics; self.tracks = tracks
            var merged = folders
            var names = Set(folders.map { $0.name.folding(options: .caseInsensitive,locale: nil) })
            for (i,name) in (graphics.map(\.folder)+tracks.map(\.folder)).enumerated() {
                if i%64 == 0 { try Task.checkCancellation() }
                if names.insert(name.folding(options: .caseInsensitive,locale: nil)).inserted { merged.append(.init(name: name)) }
            }
            self.folders = merged.sorted { a,b in
                if a.name == Folders.defaultFolder { return b.name != Folders.defaultFolder }
                if b.name == Folders.defaultFolder { return false }
                return a.name.compare(b.name,options: .caseInsensitive,locale: locale) == .orderedAscending
            }
            var ids = LibrarySelection(); ids.waypoints = index.ids; ids.graphics = Set(graphics.map(\.id)); ids.tracks = Set(tracks.map(\.id))
            allIDs = ids; routeCount = graphics.filter { $0.type == "route" }.count
        }

        public func snapshot(folder: String?,origin: GeoPoint?,query: String,sort: WaypointSort) throws -> Snapshot {
            let points = try index.listed(folder: folder,origin: origin,query: query,sort: sort)
            let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let graphics = graphics.filter { (folder == nil || $0.folder.caseInsensitiveCompare(folder!) == .orderedSame) && (q.isEmpty || $0.name.lowercased().contains(q)) }
            let tracks = tracks.filter { (folder == nil || $0.folder.caseInsensitiveCompare(folder!) == .orderedSame) && (q.isEmpty || $0.name.lowercased().contains(q)) }
            var selection = LibrarySelection(); selection.waypoints = Set(points.map(\.id)); selection.graphics = Set(graphics.map(\.id)); selection.tracks = Set(tracks.map(\.id))
            try Task.checkCancellation()
            return Snapshot(waypoints: points,graphics: graphics,tracks: tracks,folders: folders,folderNames: Set(folders.map(\.name)),selection: selection,allIDs: allIDs,routeCount: routeCount)
        }
    }
}
