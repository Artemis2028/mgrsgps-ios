import GridFixCore
import MapLibre

@MainActor
final class TacticalMapOverlay: UIView {
    weak var map: MLNMapView?
    var graphics: [Backup.Graphic] = []
    var draft: Backup.Graphic?
    var night = false
    var lightLines = false
    override init(frame: CGRect) { super.init(frame: frame); backgroundColor = .clear; isOpaque = false; isUserInteractionEnabled = false; accessibilityElementsHidden = true; contentMode = .redraw }
    required init?(coder: NSCoder) { fatalError("Created by map") }
    func update(document: Backup.Document, folders: [FolderInfo], draft: Backup.Graphic?, night: Bool, light: Bool) {
        let hidden = Set(folders.filter { !$0.visible }.map { $0.name.lowercased() })
        graphics = document.graphics.filter { $0.visible && !hidden.contains($0.folder.lowercased()) && $0.id != draft?.id }
        self.draft = draft; self.night = night; lightLines = light; setNeedsDisplay()
    }
    private func projected(_ graphic: Backup.Graphic) -> [CGPoint] {
        guard let map else { return [] }
        // Use the copy of the world closest to the first vertex, then unwrap
        // sequentially so a dateline leg stays local as the camera moves.
        var longitude = map.centerCoordinate.longitude
        return graphic.points.map { point in
            longitude += ((point.lon-longitude+540).truncatingRemainder(dividingBy: 360))-180
            return map.convert(CLLocationCoordinate2D(latitude: point.lat,longitude: longitude),toPointTo: self)
        }
    }
    func graphic(at point: CGPoint, tolerance: CGFloat = 22) -> Backup.Graphic? {
        func distance(_ a: CGPoint,_ b: CGPoint) -> CGFloat { hypot(a.x-b.x,a.y-b.y) }
        func segment(_ a: CGPoint,_ b: CGPoint) -> CGFloat {
            let dx = b.x-a.x, dy = b.y-a.y, length = dx*dx+dy*dy
            let t = length == 0 ? 0 : max(0,min(1,((point.x-a.x)*dx+(point.y-a.y)*dy)/length))
            return distance(point,.init(x: a.x+t*dx,y: a.y+t*dy))
        }
        var best: (Backup.Graphic,CGFloat)?
        for graphic in graphics {
            let points = projected(graphic); guard let first = points.first else { continue }
            let value: CGFloat
            if points.count == 1 { value = distance(point,first) }
            else if graphic.type == "ring" { value = min(distance(point,first),abs(distance(point,first)-distance(first,points[1]))) }
            else if graphic.type == "sector", points.count >= 3 { value = min(segment(first,points[1]),segment(first,points[2])) }
            else {
                let p = GraphicTypes.isArea(graphic.type) ? points + [first] : points
                value = zip(p,p.dropFirst()).map { segment($0.0,$0.1) }.min() ?? .greatestFiniteMagnitude
            }
            if value <= tolerance && (best == nil || value < best!.1) { best = (graphic,value) }
        }
        return best?.0
    }
    override func draw(_ rect: CGRect) {
        guard let c = UIGraphicsGetCurrentContext() else { return }
        for graphic in graphics { TacticalGraphicCanvas.draw(graphic,points: projected(graphic),in: c,night: night,lightLines: lightLines) }
        if let draft { TacticalGraphicCanvas.draw(draft,points: projected(draft),in: c,night: night,lightLines: lightLines,selected: true,draft: true) }
    }
}
