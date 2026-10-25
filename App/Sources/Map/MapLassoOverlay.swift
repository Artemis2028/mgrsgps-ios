import GridFixCore
import MapLibre
import UIKit

/// Sits above the map while selecting; SwiftUI chrome remains above this view.
@MainActor
final class MapLassoOverlay: UIView {
    weak var map: MLNMapView?
    var waypoints: [Waypoint] = []
    var graphics: [Backup.Graphic] = []
    var folders: [FolderInfo] = []
    var onSelect: ((LibrarySelection) -> Void)?
    var onVertexCount: ((Int) -> Void)?
    private(set) var loop: [MapLasso.Point] = []
    private var selection: LibrarySelection?
    private var night = false
    private var active = false
    private var request: UUID?
    private var finishRequest: UUID?
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false; backgroundColor = .clear; isUserInteractionEnabled = false
        accessibilityIdentifier = "map-lasso-canvas"
        addGestureRecognizer(UIPanGestureRecognizer(target: self,action: #selector(pan(_:))))
        addGestureRecognizer(UITapGestureRecognizer(target: self,action: #selector(tap(_:))))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(active: Bool,selection: LibrarySelection?,night: Bool,selectVisibleRequest: UUID?,finishLoopRequest: UUID?) {
        if !active { request = nil; finishRequest = nil }
        if !active || self.selection != nil && selection == nil { loop = [] }
        self.active = active; self.selection = selection; self.night = night
        isHidden = !active; isUserInteractionEnabled = active
        if active,let selectVisibleRequest,request != selectVisibleRequest {
            request = selectVisibleRequest
            // Accessibility alternative to freehand dragging. Defer publication
            // because this request originates in updateUIView.
            DispatchQueue.main.async { [weak self] in
                guard let self,self.active,self.request == selectVisibleRequest else { return }
                self.finish([.init(x: 0,y: 0),.init(x: self.bounds.width,y: 0),
                             .init(x: self.bounds.width,y: self.bounds.height),.init(x: 0,y: self.bounds.height)])
            }
        }
        if active,let finishLoopRequest,finishRequest != finishLoopRequest {
            finishRequest = finishLoopRequest
            DispatchQueue.main.async { [weak self] in
                guard let self,self.active,self.finishRequest == finishLoopRequest else { return }
                self.finish(self.loop)
            }
        }
        setNeedsDisplay()
    }
    @objc private func tap(_ gesture: UITapGestureRecognizer) {
        guard active,selection == nil,gesture.state == .ended,loop.count < 4096 else { return }
        let p = gesture.location(in: self)
        loop.append(.init(x: p.x,y: p.y)); onVertexCount?(loop.count); setNeedsDisplay()
    }
    @objc private func pan(_ gesture: UIPanGestureRecognizer) {
        guard active,selection == nil else { return }
        let point = gesture.location(in: self), value = MapLasso.Point(x: point.x,y: point.y)
        switch gesture.state {
        case .began: loop = [value]
        case .changed:
            // Bound a single gesture's storage without skipping its later edge.
            if let last = loop.last,hypot(last.x-value.x,last.y-value.y) >= 2 {
                if loop.count >= 4096 { loop = loop.enumerated().compactMap { $0.offset.isMultiple(of: 2) ? $0.element : nil } }
                loop.append(value)
            }
        case .ended: loop.append(value); finish(loop)
        case .cancelled,.failed: loop = []
        default: break
        }
        onVertexCount?(loop.count)
        setNeedsDisplay()
    }
    func finish(_ points: [MapLasso.Point]) {
        guard active,points.count >= 3,let map else { loop = []; return }
        let selected = MapLasso.select(loop: points,waypoints: waypoints,graphics: graphics,folders: folders) { geo in
            let p = self.project(geo,in: map)
            return .init(x: p.x,y: p.y)
        }
        loop = []; selection = selected; onSelect?(selected); setNeedsDisplay()
    }
    private func project(_ geo: GeoPoint,in map: MLNMapView) -> CGPoint {
        let lon = map.centerCoordinate.longitude + TerrainGeometry.wrap(geo.lon-map.centerCoordinate.longitude)
        return map.convert(CLLocationCoordinate2D(latitude: geo.lat,longitude: lon),toPointTo: self)
    }
    override func draw(_ rect: CGRect) {
        guard active,let context = UIGraphicsGetCurrentContext(),let map else { return }
        let color = night ? UIColor.systemRed : UIColor(Blackout.accent)
        let hidden = Set(folders.filter { !$0.visible }.map { $0.name.lowercased() })
        context.setStrokeColor(color.cgColor); context.setFillColor(color.cgColor); context.setLineWidth(3)
        if let first = loop.first,loop.count > 1 {
            context.move(to: .init(x: first.x,y: first.y))
            for p in loop.dropFirst() { context.addLine(to: .init(x: p.x,y: p.y)) }
            context.strokePath()
        }
        guard let selection else { return }
        for wp in waypoints where selection.waypoints.contains(wp.id) && wp.visible && !hidden.contains(wp.folder.lowercased()) {
            let p = project(.init(lat: wp.lat,lon: wp.lon),in: map)
            guard p.x.isFinite,p.y.isFinite else { continue }
            context.strokeEllipse(in: CGRect(x: p.x-22,y: p.y-22,width: 44,height: 44))
        }
        for graphic in graphics where selection.graphics.contains(graphic.id) && graphic.visible && !hidden.contains(graphic.folder.lowercased()) {
            for vertex in graphic.points {
                let p = project(.init(lat: vertex.lat,lon: vertex.lon),in: map)
                guard p.x.isFinite,p.y.isFinite else { continue }
                context.fillEllipse(in: CGRect(x: p.x-6,y: p.y-6,width: 12,height: 12))
            }
        }
    }
}
