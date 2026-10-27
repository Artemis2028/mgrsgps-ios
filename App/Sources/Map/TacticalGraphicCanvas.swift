import GridFixCore
import UIKit

/// Android ControlMeasuresOverlay.kt (release/1.1.0), in UIKit points rather
/// than density-scaled pixels. Retains all vertices, including imported routes.
@MainActor
enum TacticalGraphicCanvas {
    static func draw(_ graphic: Backup.Graphic, points p: [CGPoint], in c: CGContext, night: Bool, lightLines: Bool, selected: Bool = false, draft: Bool = false, numberRouteLegs: Bool = true) {
        guard let first = p.first else { return }
        c.saveGState(); defer { c.restoreGState() }
        let type = graphic.type, n = p.count
        let color = color(graphic.affiliation, night: night, light: lightLines)
        let halo: UIColor = night || lightLines ? .black : .white
        let name = graphic.name + (night && graphic.affiliation == "hostile" ? " ENY" : "")
        let mid = p[n / 2]
        let centroid = CGPoint(x: p.reduce(0) { $0 + $1.x } / CGFloat(n), y: p.reduce(0) { $0 + $1.y } / CGFloat(n))
        func path(_ points: [CGPoint], closed: Bool = false) -> UIBezierPath {
            let path = UIBezierPath(); if let point = points.first { path.move(to: point); points.dropFirst().forEach { path.addLine(to: $0) }; if closed { path.close() } }; return path
        }
        func stroke(_ path: UIBezierPath, dashed: Bool = true) {
            c.setLineCap(.round); c.setLineJoin(.round)
            if selected { c.setLineWidth(6.5); c.setStrokeColor(halo.withAlphaComponent(120/255).cgColor); c.addPath(path.cgPath); c.strokePath() }
            c.setLineWidth(2.6); c.setStrokeColor(color.withAlphaComponent(235/255).cgColor)
            c.setLineDash(phase: 0, lengths: draft && dashed ? [9,6] : [])
            c.addPath(path.cgPath); c.strokePath(); c.setLineDash(phase: 0, lengths: [])
        }
        func line(_ a: CGPoint, _ b: CGPoint) { stroke(path([a,b]), dashed: false) }
        func fill(_ path: UIBezierPath, alpha: CGFloat = 235/255) { c.setFillColor(color.withAlphaComponent(alpha).cgColor); c.addPath(path.cgPath); c.fillPath() }
        func circle(_ center: CGPoint, _ radius: CGFloat, filled: Bool = false) {
            let shape = UIBezierPath(ovalIn: CGRect(x: center.x-radius, y: center.y-radius, width: 2*radius, height: 2*radius)); if filled { fill(shape) } else { stroke(shape, dashed: false) }
        }
        func label(_ text: String, _ point: CGPoint, above: Bool = true, centered: Bool = false, size: CGFloat = 11.5) {
            guard !text.isEmpty else { return }
            let font = UIFont.monospacedSystemFont(ofSize: size, weight: .bold)
            let text = text as NSString; let width = text.size(withAttributes: [.font:font]).width
            let x = centered ? point.x-width/2 : point.x+6
            let baseline = above ? point.y-7 : point.y+size/3
            let origin = CGPoint(x: x, y: baseline-font.ascender)
            text.draw(at: origin, withAttributes: [.font:font, .foregroundColor:halo, .strokeColor:halo.withAlphaComponent(200/255), .strokeWidth: 26])
            text.draw(at: origin, withAttributes: [.font:font, .foregroundColor:color.withAlphaComponent(245/255)])
        }
        func arrow(_ tip: CGPoint, from start: CGPoint, length: CGFloat = 10) {
            let a = atan2(tip.y-start.y, tip.x-start.x), spread = CGFloat.pi*150/180
            fill(path([tip, offset(tip, angle: a+spread, length: length), offset(tip, angle: a-spread, length: length)], closed: true))
        }
        func box(_ point: CGPoint, width: CGFloat, height: CGFloat) {
            c.setFillColor(halo.withAlphaComponent(230/255).cgColor); c.fill(CGRect(x: point.x-width/2, y: point.y-height/2, width: width, height: height))
        }
        if n < GraphicTypes.minPoints(type) {
            if n == 1 { circle(first,3,filled: true) } else { stroke(path(p)) }; return
        }
        switch type {
        case "axis": stroke(axis(p)); label(name, first)
        case "doa": stroke(path(p)); arrow(p[n-1], from: p[n-2], length: 11); label(name, first)
        case "ring":
            let radius = distance(first,p[1]); circle(first,radius)
            line(CGPoint(x: first.x-5,y: first.y),CGPoint(x: first.x+5,y: first.y)); line(CGPoint(x: first.x,y: first.y-5),CGPoint(x: first.x,y: first.y+5))
            let a = graphic.points[0], b = graphic.points[1]
            let meters = Geodesy.greatCircleMeters(a.lat,a.lon,b.lat,b.lon)
            let range = meters < 995 ? String(format: "%.0f m",meters) : String(format: "%.2f km",meters/1000)
            label(name + " · " + range, CGPoint(x: first.x,y: first.y-radius-3), centered: true)
        case "sector":
            let radius = max(distance(first,p[1]),distance(first,p[2]))
            let start = atan2(p[1].y-first.y,p[1].x-first.x), end = atan2(p[2].y-first.y,p[2].x-first.x)
            var sweep = end-start; while sweep <= 0 { sweep += 2 * .pi }
            let shape = UIBezierPath(); shape.move(to: first); shape.addArc(withCenter: first,radius: radius,startAngle: start,endAngle: start+sweep,clockwise: true); shape.close()
            fill(shape,alpha: 22/255); stroke(shape); label(name,offset(first,angle: start+sweep/2,length: radius*0.55),above: false,centered: true)
        case "trp":
            line(CGPoint(x: first.x-9,y: first.y),CGPoint(x: first.x+9,y: first.y)); line(CGPoint(x: first.x,y: first.y-9),CGPoint(x: first.x,y: first.y+9)); circle(first,2.2,filled: true)
            label("TRP " + name.uppercased(),CGPoint(x: first.x+9,y: first.y-4))
        case "checkpoint":
            let center = CGPoint(x: first.x,y: first.y-16.8), radius: CGFloat = 7
            let shape = UIBezierPath(); shape.move(to: first); shape.addLine(to: offset(center,angle: .pi*140/180,length: radius)); shape.addArc(withCenter: center,radius: radius,startAngle: .pi*140/180,endAngle: .pi*400/180,clockwise: true); shape.close(); stroke(shape); circle(first,2,filled: true)
            label("CP " + name.uppercased(),CGPoint(x: first.x+9.1,y: center.y))
        case "dp":
            let vertices = (0..<10).map { i in offset(first, angle: -.pi/2+CGFloat(i) * CGFloat.pi/5, length: i%2 == 0 ? 11 : 4.62) }
            stroke(path(vertices,closed: true)); label("DP " + name.uppercased(),CGPoint(x: first.x+11,y: first.y-6.6))
        case "text": label(name,first,above: false,centered: true,size: 13.5)
        case "roadblock":
            for i in 0..<3 { let angle = CGFloat(i) * .pi/3; line(offset(first,angle: angle,length: -8),offset(first,angle: angle,length: 8)) }
            label(name,CGPoint(x: first.x+8,y: first.y-4))
        case "flot":
            walk(p,spacing: 11,clip: c.boundingBoxOfClipPath) { point, angle in
                let shape = UIBezierPath(arcCenter: point,radius: 5.5,startAngle: angle + .pi,endAngle: angle + 2 * .pi,clockwise: true); stroke(shape,dashed: false)
            }
            label("FLOT " + name,first); label("FLOT " + name,p[n-1])
        case "obstacle_line", "wire", "strongpoint":
            let closed = type == "strongpoint" && n >= 3
            let shape = path(p,closed: closed); if closed { fill(shape,alpha: 26/255) }; stroke(shape)
            walk(p,spacing: type == "wire" ? 13 : (closed ? 14 : 12),closed: closed,clip: c.boundingBoxOfClipPath) { point, angle in
                if type == "wire" {
                    for delta in [-CGFloat.pi/4,CGFloat.pi/4] { line(offset(point,angle: angle+delta,length: -4.5),offset(point,angle: angle+delta,length: 4.5)) }
                } else {
                    var normal = CGPoint(x: sin(angle),y: -cos(angle))
                    if closed && (point.x-centroid.x)*normal.x+(point.y-centroid.y)*normal.y < 0 { normal.x = -normal.x; normal.y = -normal.y }
                    let tip = CGPoint(x: point.x+normal.x*6,y: point.y+normal.y*6)
                    fill(path([offset(point,angle: angle,length: -3.3),tip,offset(point,angle: angle,length: 3.3)],closed: true))
                }
            }
            label(closed ? name.uppercased() : name,closed ? centroid : first,above: !closed,centered: closed)
        case "lane":
            for side in [-CGFloat(1),1] { stroke(path(p.indices.map { i in let normal = normal(p,i); return CGPoint(x: p[i].x+normal.x*4.5*side,y: p[i].y+normal.y*4.5*side) })) }; label(name,mid)
        case "minefield":
            let shape = path(p,closed: n >= 3); fill(shape,alpha: 20/255); stroke(shape)
            circle(CGPoint(x: centroid.x-11,y: centroid.y),2.8); circle(centroid,4.2); circle(CGPoint(x: centroid.x+11,y: centroid.y),2.8)
            label(name.uppercased(),CGPoint(x: centroid.x,y: centroid.y+16),above: false,centered: true)
        case "boundary":
            stroke(path(p))
            if !graphic.echelon.isEmpty {
                box(mid,width: 49.5,height: 16.2)
                let dots = ["sqd":1,"sec":2,"plt":3], bars = ["co":1,"bn":2,"rgt":3], crosses = ["bde":1,"div":2,"corps":3,"army":4]
                if graphic.echelon == "tm" { circle(mid,3.6); line(CGPoint(x: mid.x-5.4,y: mid.y+5.4),CGPoint(x: mid.x+5.4,y: mid.y-5.4)) }
                else {
                    let count = dots[graphic.echelon] ?? bars[graphic.echelon] ?? crosses[graphic.echelon] ?? 0
                    let gap: CGFloat = dots[graphic.echelon] != nil ? 7.2 : (bars[graphic.echelon] != nil ? 6.3 : 11.7)
                    for i in 0..<count {
                        let x = mid.x + (CGFloat(i)-CGFloat(count-1)/2)*gap
                        if dots[graphic.echelon] != nil { circle(CGPoint(x: x,y: mid.y),2.475,filled: true) }
                        else if bars[graphic.echelon] != nil { line(CGPoint(x: x,y: mid.y-4.5),CGPoint(x: x,y: mid.y+4.5)) }
                        else { line(CGPoint(x: x-4.5,y: mid.y-4.5),CGPoint(x: x+4.5,y: mid.y+4.5)); line(CGPoint(x: x-4.5,y: mid.y+4.5),CGPoint(x: x+4.5,y: mid.y-4.5)) }
                    }
                }
            }; label(name.uppercased(),mid)
        case "screen_l", "guard_l", "cover_l":
            stroke(path(p)); arrow(first,from: p[1]); arrow(p[n-1],from: p[n-2]); box(mid,width: 16,height: 16)
            stroke(UIBezierPath(rect: CGRect(x: mid.x-8,y: mid.y-8,width: 16,height: 16)),dashed: false)
            label(["screen_l":"S","guard_l":"G","cover_l":"C"][type]!,mid,above: false,centered: true,size: 11); label(name,first)
        case "route":
            stroke(path(p)); p.forEach { circle($0,3,filled: true) }
            if numberRouteLegs { for i in 0..<(n-1) { label(String(i+1),CGPoint(x: (p[i].x+p[i+1].x)/2,y: (p[i].y+p[i+1].y)/2)) } }; label(name,first)
        default:
            let area = GraphicTypes.isArea(type); let shape = path(p,closed: area && n >= 3)
            if area && n >= 3 { fill(shape,alpha: 26/255) }; stroke(shape)
            let text = GraphicTypes.labelPrefix(type) + name.uppercased()
            if type == "phase_line" { label(text,first); label(text,p[n-1]) } else { label(text,area ? centroid : mid,above: !area,centered: area) }
        }
    }
    static func color(_ affiliation: String, night: Bool, light: Bool) -> UIColor {
        let rgb: (CGFloat,CGFloat,CGFloat)
        if night { rgb = affiliation == "hostile" ? (255,59,48) : (196,45,36) }
        else { switch affiliation { case "friendly": rgb = (45,120,200); case "hostile": rgb = (210,50,40); case "neutral": rgb = (60,150,60); case "unknown": rgb = (200,170,40); default: rgb = light ? (255,255,255) : (20,22,26) } }
        return UIColor(red: rgb.0/255,green: rgb.1/255,blue: rgb.2/255,alpha: 1)
    }
    private static func offset(_ p: CGPoint, angle: CGFloat, length: CGFloat) -> CGPoint { .init(x: p.x+cos(angle)*length,y: p.y+sin(angle)*length) }
    private static func distance(_ a: CGPoint,_ b: CGPoint) -> CGFloat { hypot(b.x-a.x,b.y-a.y) }
    private static func normal(_ points: [CGPoint],_ i: Int) -> CGPoint {
        let a = points[max(0,i-1)], b = points[min(points.count-1,i+1)], dx = b.x-a.x, dy = b.y-a.y, length = hypot(dx,dy)
        return length > 0 ? .init(x: -dy/length,y: dx/length) : .zero
    }
    private static func axis(_ p: [CGPoint]) -> UIBezierPath {
        let total = zip(p,p.dropFirst()).reduce(CGFloat(0)) { $0 + distance($1.0,$1.1) }
        let width = min(64,max(14,total*0.13)), half = width/2, head = min(width*1.25,total*0.45)
        var remaining = head, segment = p.count-2, neck = p[segment]
        for i in stride(from: p.count-2,through: 0,by: -1) {
            let length = distance(p[i],p[i+1])
            if length >= remaining || i == 0 {
                let t = length == 0 ? 0 : max(0,min(1,1-remaining/length)); neck = .init(x: p[i].x+(p[i+1].x-p[i].x)*t,y: p[i].y+(p[i+1].y-p[i].y)*t); segment = i; break
            }; remaining -= length
        }
        let shaft = Array(p.prefix(segment+1)) + [neck]
        let left = shaft.indices.map { i in let n = normal(shaft,i); return CGPoint(x: shaft[i].x+n.x*half,y: shaft[i].y+n.y*half) }
        let right = shaft.indices.map { i in let n = normal(shaft,i); return CGPoint(x: shaft[i].x-n.x*half,y: shaft[i].y-n.y*half) }
        let tip = p.last!, angle = atan2(tip.y-neck.y,tip.x-neck.x), headNormal = CGPoint(x: -sin(angle),y: cos(angle))
        let vertices = left + [CGPoint(x: neck.x+headNormal.x*width,y: neck.y+headNormal.y*width),tip,CGPoint(x: neck.x-headNormal.x*width,y: neck.y-headNormal.y*width)] + right.reversed()
        let path = UIBezierPath(); path.move(to: vertices[0]); vertices.dropFirst().forEach { path.addLine(to: $0) }; return path
    }
    /// Preserve continuous Android decoration spacing but skip off-screen work.
    private static func walk(_ points: [CGPoint], spacing: CGFloat, closed: Bool = false, clip: CGRect, emit: (CGPoint,CGFloat) -> Void) {
        var carry = spacing/2
        let p = closed ? points + [points[0]] : points
        for (a,b) in zip(p,p.dropFirst()) {
            let dx = b.x-a.x, dy = b.y-a.y, length = hypot(dx,dy); guard length > 0 else { continue }
            var low: CGFloat = 0, high: CGFloat = 1
            let rect = clip.insetBy(dx: -30,dy: -30)
            var visible = true
            for (direction,edge) in [(-dx,a.x-rect.minX),(dx,rect.maxX-a.x),(-dy,a.y-rect.minY),(dy,rect.maxY-a.y)] {
                if direction == 0 { if edge < 0 { visible = false }; continue }
                let t = edge/direction
                if direction < 0 { low = max(low,t) } else { high = min(high,t) }
                if low > high { visible = false }
            }
            if visible {
                var d = carry + max(0,ceil((low*length-carry)/spacing))*spacing
                while d <= min(length,high*length) { emit(.init(x: a.x+dx*d/length,y: a.y+dy*d/length),atan2(dy,dx)); d += spacing }
            }
            let steps = max(0,floor((length-carry)/spacing)+1); carry += steps*spacing-length
        }
    }
}
