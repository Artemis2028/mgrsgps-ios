import SwiftUI
import MapKit
import GridFixCore
import UIKit

/// Draw the same control measures as the phone, projected by the actual native map.
/// The transparent layer never takes map gestures or replaces visible-library filtering.
struct WatchTacticalGraphicLayer: View {
    var features: [WatchMapSnapshot.Feature]
    var proxy: MapProxy
    var mapRect: MKMapRect?
    var night: Bool
    var showsNames: Bool
    var ownLocation: CLLocationCoordinate2D?

    var body: some View {
        Canvas { context,size in
            guard let mapRect, mapRect.size.width.isFinite, mapRect.size.width > 0 else { return }
            let worldWidth = CGFloat(MKMapSize.world.width / mapRect.size.width) * size.width
            guard worldWidth.isFinite,worldWidth > 0 else { return }
            context.withCGContext { cg in
                UIGraphicsPushContext(cg)
                defer { UIGraphicsPopContext() }
                cg.saveGState()
                let viewport = CGRect(origin:.zero,size:size)
                // Protect the native Legal caption's text area. Touches already pass
                // through the entire canvas, so do not cut out a 44pt touch target.
                let clip = CGMutablePath(); clip.addRect(viewport)
                clip.addRect(CGRect(x:8,y:max(0,size.height-26),width:32,height:min(16,size.height)))
                cg.addPath(clip); cg.clip(using:.evenOdd)
                for feature in features where feature.kind == "graphic" {
                    let projected = feature.points.compactMap { proxy.convert(CLLocationCoordinate2D(latitude:$0.lat,longitude:$0.lon),to:.local) }
                    guard projected.count == feature.points.count else { continue }
                    let points = WatchGraphicProjection.continuous(projected,worldWidth:worldWidth,centerX:size.width/2)
                    guard points.count == projected.count else { continue }
                    let graphic = Backup.Graphic(id:feature.id,name:showsNames || feature.type == "text" ? feature.name : "",
                                                 type:feature.type,points:feature.points.map { .init(lat:$0.lat,lon:$0.lon) },
                                                 affiliation:feature.affiliation,echelon:feature.echelon)
                    TacticalGraphicCanvas.draw(graphic,points:points,in:cg,night:night,lightLines:true,numberRouteLegs:feature.routeLegLabels != nil,routeLegLabels:feature.routeLegLabels)
                }
                // Native annotations remain for accessibility. Repaint the fresh own
                // fix above tactical fills/text so they cannot hide the location dot.
                if let ownLocation,let point = proxy.convert(ownLocation,to:.local) {
                    let dot = CGRect(x:point.x-4.5,y:point.y-4.5,width:9,height:9)
                    cg.setFillColor(UIColor(night ? Color.red : Color.cyan).cgColor); cg.fillEllipse(in:dot)
                    cg.setStrokeColor(UIColor.black.cgColor); cg.setLineWidth(2); cg.strokeEllipse(in:dot)
                }
                cg.restoreGState()
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
