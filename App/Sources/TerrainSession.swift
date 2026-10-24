import GridFixCore
import SwiftUI

@MainActor
final class TerrainSession: ObservableObject {
    @Published private(set) var readout: TerrainSampler.Readout?
    @Published private(set) var sight: TerrainAnalysis.Sight?
    @Published private(set) var profile: TerrainAnalysis.Profile?
    @Published private(set) var profileName = ""
    @Published private(set) var viewshed: TerrainAnalysis.Viewshed?
    @Published private(set) var busy = false
    @Published private(set) var progress = 0.0
    @Published private(set) var error: String?
    let sampler: TerrainSampler
    private var work: Task<Void,Never>?
    private var readoutWork: Task<Void,Never>?
    private var request = UUID()
    private var lastCentre: GeoPoint?
    init(sampler: TerrainSampler) { self.sampler = sampler }
    func updateCentre(_ point: GeoPoint) {
        if let lastCentre, TerrainGeometry.distance(lastCentre,point) < 2 { return }
        lastCentre = point; readout = nil
        readoutWork?.cancel()
        readoutWork = Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            let value = await sampler.readout(point)
            guard !Task.isCancelled else { return }; readout = value
        }
    }
    func refreshCentre(_ point: GeoPoint) { lastCentre = nil; updateCentre(point) }
    func clearSight() { cancel(); sight = nil; profile = nil; error = nil }
    func cancel() { request = UUID(); work?.cancel(); work = nil; busy = false; progress = 0 }
    func backgrounded() { cancel(); readoutWork?.cancel(); lastCentre = nil }
    func clearViewshed() { viewshed = nil }
    func check(observer: GeoPoint,target: GeoPoint,observerHeight: Float,targetHeight: Float) {
        cancel(); sight = nil; profile = nil; error = nil; busy = true
        let token = request, sampler = sampler
        work = Task {
            do {
                let value = try await TerrainAnalysis.lineOfSight(observer: observer,target: target,observerHeight: observerHeight,targetHeight: targetHeight,elevation: { await sampler.elevation($0) })
                guard !Task.isCancelled, request == token else { return }
                sight = value; busy = false
                if value == nil { error = "No usable elevation at the endpoints, or the points coincide. View or download elevation for this area and try again." }
            } catch { if request == token { busy = false; self.error = error.localizedDescription } }
        }
    }
    func shade(observer: GeoPoint,height: Double,radius: Double,onComplete: @escaping () -> Void) {
        cancel(); error = nil; busy = true
        let token = request, sampler = sampler
        work = Task {
            do {
                let value = try await TerrainAnalysis.viewshed(observer: observer,height: height,radius: radius,elevation: { await sampler.elevation($0) },progress: { [weak self] amount in
                    await self?.report(amount,token: token)
                })
                guard !Task.isCancelled, request == token else { return }
                viewshed = value; busy = false
                if value == nil { error = "No usable elevation at the observer (coverage extends to 85° latitude). Download elevation and try again." }
                else { onComplete() }
            } catch { if request == token { busy = false; self.error = error.localizedDescription } }
        }
    }
    func routeProfile(_ route: Backup.Graphic) {
        cancel(); sight = nil; profile = nil; error = nil; busy = true
        let token = request, sampler = sampler
        work = Task {
            do {
                let value = try await TerrainAnalysis.profile(points: route.points.map { .init(lat: $0.lat,lon: $0.lon) },elevation: { await sampler.elevation($0) })
                guard !Task.isCancelled, request == token else { return }
                profile = value; profileName = route.name; busy = false
                if value == nil { error = "The route needs at least two distinct points within terrain coverage." }
            } catch { if request == token { busy = false; self.error = error.localizedDescription } }
        }
    }
    private func report(_ value: Double,token: UUID) { if request == token { progress = value } }
}
