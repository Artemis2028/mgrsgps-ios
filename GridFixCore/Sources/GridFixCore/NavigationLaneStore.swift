import Combine
import Foundation

/// Independent lane library. A serial worker owns disk state; UI publication
/// uses revisions so a delayed caller cannot replace a newer library snapshot.
@MainActor
public final class NavigationLaneStore: ObservableObject {
    @Published public private(set) var lanes: [NavLane] = []
    @Published public private(set) var ready = false
    @Published public private(set) var error: String?
    private let file: LaneLibraryFile
    private var revision: UInt64 = 0
    private var loading: Task<Void,Never>?
    public init(directory: URL? = nil) {
        let directory = directory ?? FileManager.default.urls(for: .documentDirectory,in: .userDomainMask).first!
        file = LaneLibraryFile(url: directory.appendingPathComponent("nav-lanes-v1.json"))
        loading = Task { [weak self] in try? await self?.reload() }
    }
    public func waitUntilLoaded() async { await loading?.value }
    public func reload() async throws {
        do { accept(try await file.read()) }
        catch { self.error = "Lane library could not be read: \(error.localizedDescription). Its file was kept."; throw error }
    }
    @discardableResult
    public func save(_ lane: NavLane,original: NavLane? = nil,graphics: [Backup.Graphic]) async throws -> NavLane {
        let result = try await change(.save(lane,original,graphics))
        guard let saved = result.lanes.first(where: { $0.id == lane.id }) else { throw LaneShapeError("This lane is no longer saved") }
        return saved
    }
    public func setVisible(_ id: String,_ visible: Bool) async throws { _ = try await change(.visible(id,visible)) }
    public func delete(_ id: String) async throws { _ = try await change(.delete(id)) }
    private func change(_ edit: LaneLibraryFile.Edit) async throws -> LaneLibraryFile.Snapshot {
        do { let result = try await file.change(edit); accept(result); return result }
        catch { self.error = error.localizedDescription; throw error }
    }
    private func accept(_ value: LaneLibraryFile.Snapshot) {
        guard value.revision >= revision else { return }
        revision = value.revision; lanes = value.lanes; ready = true; error = nil
    }
}

private actor LaneLibraryFile {
    struct Snapshot: Sendable { var lanes: [NavLane]; var revision: UInt64 }
    enum Edit: Sendable { case save(NavLane,NavLane?,[Backup.Graphic]),visible(String,Bool),delete(String) }
    let url: URL
    private var current: [NavLane]?
    private var revision: UInt64 = 0
    private let maxBytes = 32*1024*1024
    init(url: URL) { self.url = url }
    func read() throws -> Snapshot {
        if current == nil {
            if FileManager.default.fileExists(atPath: url.path) {
                let bytes = try Data(contentsOf: url,options: .mappedIfSafe)
                guard bytes.count <= maxBytes else { throw LaneShapeError("Lane library exceeds 32 MiB") }
                let values = try JSONDecoder().decode([NavLane].self,from: bytes)
                guard Set(values.map(\.id)).count == values.count else { throw LaneShapeError("Lane IDs must be unique") }
                current = values
            } else { current = [] }
        }
        return .init(lanes: current!,revision: revision)
    }
    func change(_ edit: Edit) throws -> Snapshot {
        var next = try read().lanes
        switch edit {
        case let .save(draft,original,graphics):
            let value: NavLane
            if let original {
                guard original.id == draft.id,let index = next.firstIndex(where: { $0.id == draft.id }) else { throw LaneShapeError("This lane was deleted. Your draft is kept") }
                var patched = next[index]
                if original.name != draft.name { patched.name = draft.name }
                if original.left != draft.left { patched.left = draft.left }
                if original.right != draft.right { patched.right = draft.right }
                if original.backstop != draft.backstop { patched.backstop = draft.backstop }
                if original.scope != draft.scope { patched.scope = draft.scope }
                if original.targetId != draft.targetId { patched.targetId = draft.targetId }
                if original.folder != draft.folder { patched.folder = draft.folder }
                if original.visible != draft.visible { patched.visible = draft.visible }
                value = patched
            } else {
                if next.contains(where: { $0.id == draft.id }) { return .init(lanes: next,revision: revision) }
                value = draft
            }
            // Round-trip validates programmatically constructed models too.
            let checked = try JSONDecoder().decode(NavLane.self,from: JSONEncoder().encode(value))
            let normalized = try NavLanes.normalized(checked,graphics: graphics).lane
            if let i = next.firstIndex(where: { $0.id == normalized.id }) { next[i] = normalized }
            else { next.append(normalized) }
        case let .visible(id,value):
            guard let i = next.firstIndex(where: { $0.id == id }) else { return .init(lanes: next,revision: revision) }
            next[i].visible = value
        case .delete(let id): next.removeAll { $0.id == id }
        }
        guard next != current else { return .init(lanes: next,revision: revision) }
        let bytes = try JSONEncoder().encode(next)
        guard bytes.count <= maxBytes else { throw LaneShapeError("Lane library exceeds 32 MiB") }
        let prepared = try PreparedAtomicFile(data: bytes,destination: url,lockCompatible: true)
        try prepared.publish()
        current = next; revision &+= 1
        return .init(lanes: next,revision: revision)
    }
}
