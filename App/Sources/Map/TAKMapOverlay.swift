import GridFixCore
import MapLibre

/// Remote traffic has its own noneditable overlay, never a saved-waypoint ID.
@MainActor
final class TAKMapOverlay: UIView {
    weak var map: MLNMapView?
    private var items: [TAKRemoteItem] = []
    private var night = false
    override init(frame: CGRect) {
        super.init(frame: frame); backgroundColor = .clear; isOpaque = false
        isUserInteractionEnabled = false; accessibilityElementsHidden = true; contentMode = .redraw
    }
    required init?(coder: NSCoder) { fatalError("Created by map") }
    func update(_ items: [TAKRemoteItem], night: Bool) {
        guard self.items != items || self.night != night else { return }
        self.items = items; self.night = night; setNeedsDisplay()
    }
    override func draw(_ rect: CGRect) {
        guard let map, let context = UIGraphicsGetCurrentContext() else { return }
        for item in items {
            var longitude = map.centerCoordinate.longitude
            let points = item.points.map { point -> CGPoint in
                longitude += TerrainGeometry.wrap(point.lon - longitude)
                return map.convert(CLLocationCoordinate2D(latitude: point.lat, longitude: longitude), toPointTo: self)
            }
            guard let first = points.first else { continue }
            let color: UIColor = night ? .systemRed : item.affiliation == "hostile" ? .systemRed : item.affiliation == "friendly" ? .cyan : item.affiliation == "neutral" ? .systemGreen : .systemYellow
            if points.count == 1 {
                guard bounds.insetBy(dx: -150, dy: -80).contains(first) else { continue }
                let code = MilitarySymbols.affiliationCode(item.affiliation)
                MilitaryMarkerRenderer.image(symbol: "nato_\(code)_unit", affiliation: item.affiliation, night: night)
                    .draw(in: CGRect(x: first.x - 22, y: first.y - 22, width: 44, height: 44))
            } else {
                context.beginPath(); context.move(to: first)
                points.dropFirst().forEach { context.addLine(to: $0) }
                if item.closed { context.closePath(); context.setFillColor(color.withAlphaComponent(0.15).cgColor); context.drawPath(using: .fill) }
                context.beginPath(); context.move(to: first); points.dropFirst().forEach { context.addLine(to: $0) }
                if item.closed { context.closePath() }
                context.setLineWidth(3); context.setStrokeColor(color.cgColor); context.strokePath()
            }
            let label = (item.isContact ? "TAK · " : "") + item.callsign
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedSystemFont(ofSize: 12, weight: .semibold), .foregroundColor: night ? UIColor.systemRed : UIColor.white]
            let size = (label as NSString).size(withAttributes: attributes)
            let box = CGRect(x: first.x - size.width / 2 - 4, y: first.y + 24, width: size.width + 8, height: size.height + 4)
            UIColor.black.withAlphaComponent(0.9).setFill(); UIBezierPath(roundedRect: box, cornerRadius: 3).fill()
            (label as NSString).draw(at: CGPoint(x: box.minX + 4, y: box.minY + 2), withAttributes: attributes)
        }
    }
}
