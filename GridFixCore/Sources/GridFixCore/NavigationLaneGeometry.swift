import Foundation

/// Android nav-lane geometry, separate from the user's closed quiet perimeter.
/// Local equirectangular metres match LaneGeometry.kt at Android eacf084.
struct LaneXY: Equatable, Sendable {
    var x: Double, y: Double
    static func - (a: Self,b: Self) -> Self { .init(x: a.x-b.x,y: a.y-b.y) }
    static func + (a: Self,b: Self) -> Self { .init(x: a.x+b.x,y: a.y+b.y) }
    static func * (a: Self,b: Double) -> Self { .init(x: a.x*b,y: a.y*b) }
    func dot(_ b: Self) -> Double { x*b.x+y*b.y }
    func cross(_ b: Self) -> Double { x*b.y-y*b.x }
    var length: Double { hypot(x,y) }
}

struct LaneLocalPlane: Sendable {
    let origin: GeoPoint
    private var latitudeScale: Double { .pi/180 * 6_371_008.8 }
    private var longitudeScale: Double { latitudeScale * cos(origin.lat * .pi/180) }
    func project(_ p: GeoPoint) -> LaneXY {
        var longitude = p.lon-origin.lon
        if longitude > 180 { longitude -= 360 }
        if longitude < -180 { longitude += 360 }
        return .init(x: longitude*longitudeScale,y: (p.lat-origin.lat)*latitudeScale)
    }
    func unproject(_ p: LaneXY) -> GeoPoint {
        var longitude = origin.lon+p.x/longitudeScale
        if longitude > 180 { longitude -= 360 }
        if longitude < -180 { longitude += 360 }
        return .init(lat: origin.lat+p.y/latitudeScale,lon: longitude)
    }
}

struct LaneLineOffset: Sendable { var distance: Double; var inDomain: Bool }

struct LanePlanePolyline: Sendable {
    let points: [LaneXY]
    let extendStart: Bool, extendEnd: Bool
    init(_ points: [LaneXY],extendStart: Bool,extendEnd: Bool) {
        self.points = points.reduce(into: []) { values,point in
            if values.last.map({ (point-$0).length > 0.01 }) ?? true { values.append(point) }
        }
        self.extendStart = extendStart; self.extendEnd = extendEnd
    }
    var valid: Bool { points.count >= 2 }
    private func sign(_ value: Double) -> Double { value < 0 ? -1 : 1 }
    private func normal(_ value: LaneXY) -> LaneXY { .init(x: -value.y/value.length,y: value.x/value.length) }
    private func vertexSide(_ index: Int,_ q: LaneXY) -> Double {
        let outgoing = normal(points[index+1]-points[index])
        let bisector = normal(points[index]-points[index-1])+outgoing
        return sign((bisector.length < 1e-9 ? outgoing : bisector).dot(q-points[index]))
    }
    func offset(_ q: LaneXY) -> LaneLineOffset {
        precondition(valid)
        let last = points.count-2
        var distanceSquared = Double.infinity, bestT = 0.0
        var segment = 0, behindStart = false
        for i in 0...last {
            let a = points[i], d = points[i+1]-a
            var t = (q-a).dot(d)/d.dot(d)
            let behind = i == 0 && t < -1e-9
            if !(i == 0 && extendStart) && t < 0 { t = 0 }
            if !(i == last && extendEnd) && t > 1 { t = 1 }
            let delta = q-(a+d*t), squared = delta.dot(delta)
            if squared < distanceSquared {
                distanceSquared = squared; segment = i; bestT = t; behindStart = behind
            }
        }
        let distance = sqrt(distanceSquared), a = points[segment], d = points[segment+1]-a
        if segment == 0 && behindStart && !extendStart {
            return .init(distance: sign(d.cross(q-a))*distance,inDomain: false)
        }
        if segment == last && bestT >= 1 && !extendEnd {
            return .init(distance: sign(d.cross(q-points[last+1]))*distance,inDomain: false)
        }
        if bestT <= 0 && segment > 0 { return .init(distance: vertexSide(segment,q)*distance,inDomain: true) }
        if bestT >= 1 && segment < last { return .init(distance: vertexSide(segment+1,q)*distance,inDomain: true) }
        return .init(distance: sign(d.cross(q-a))*distance,inDomain: true)
    }
    func crosses(_ other: Self) -> Bool {
        for i in 0..<(points.count-1) {
            let a = points[i], b = points[i+1], ab = b-a
            for j in 0..<(other.points.count-1) {
                let c = other.points[j], d = other.points[j+1], cd = d-c
                if ab.cross(c-a)*ab.cross(d-a) < 0 && cd.cross(a-c)*cd.cross(b-c) < 0 { return true }
            }
        }
        return false
    }
}

public enum LaneLimit: String, Codable, CaseIterable, Sendable { case left, right, backstop }
public struct LaneReading: Equatable, Sendable {
    public let left: Double?, right: Double?, backstop: Double?
    public subscript(_ limit: LaneLimit) -> Double? {
        switch limit { case .left: return left; case .right: return right; case .backstop: return backstop }
    }
}
public struct LaneShapeError: LocalizedError, Equatable, Sendable {
    public let message: String
    public var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

public struct LaneShape: Sendable {
    private let plane: LaneLocalPlane
    private let left: LanePlanePolyline, right: LanePlanePolyline, backstop: LanePlanePolyline
    private let leftOutside: Double, rightOutside: Double, backstopOutside: Double
    public let leftWasDrawnAsRight: Bool

    public init(leftDrawn: [GeoPoint],rightDrawn: [GeoPoint],backstopDrawn: [GeoPoint],objective: GeoPoint? = nil) throws {
        let all = leftDrawn+rightDrawn+backstopDrawn+(objective.map {[$0]} ?? [])
        guard all.allSatisfy({ $0.lat.isFinite && $0.lon.isFinite && abs($0.lat) <= 90 && abs($0.lon) <= 180 }) else {
            throw LaneShapeError("A lane point is not a valid position")
        }
        guard let origin = all.first else { throw LaneShapeError("The lane is empty") }
        let plane = LaneLocalPlane(origin: origin)
        let b = LanePlanePolyline(backstopDrawn.map(plane.project),extendStart: true,extendEnd: true)
        guard b.valid else { throw LaneShapeError("The backstop needs two points") }
        let l0 = LanePlanePolyline(leftDrawn.map(plane.project),extendStart: false,extendEnd: true)
        let r0 = LanePlanePolyline(rightDrawn.map(plane.project),extendStart: false,extendEnd: true)
        guard l0.valid else { throw LaneShapeError("The left limit needs two points") }
        guard r0.valid else { throw LaneShapeError("The right limit needs two points") }
        let nearSign: Double
        if let objective {
            let distance = b.offset(plane.project(objective)).distance
            guard abs(distance) >= 1 else { throw LaneShapeError("The point is on the backstop; the backstop goes past the point") }
            nearSign = distance > 0 ? 1 : -1
        } else {
            // Length-weighted samples prevent a densely drawn far end from
            // deciding which side of the backstop is the approach side.
            var weight = 0.0
            for points in [l0.points,r0.points] {
                for (p,q) in zip(points,points.dropFirst()) {
                    let delta = q-p
                    for i in 0..<8 {
                        let distance = b.offset(p+delta*((Double(i)+0.5)/8)).distance
                        if abs(distance)>0.5 { weight += delta.length/8*(distance>0 ? 1 : -1) }
                    }
                }
            }
            nearSign = weight>=0 ? 1 : -1
        }
        let backstopOutside = -nearSign
        func beyond(_ point: LaneXY)->Double { b.offset(point).distance*backstopOutside }
        let bLength = zip(b.points,b.points.dropFirst()).reduce(0) {$0+($1.1-$1.0).length}
        let margin = max(100,bLength*0.5)
        let drawnBackstop = LanePlanePolyline(b.points,extendStart:false,extendEnd:false)
        for point in l0.points+r0.points where beyond(point)>1 {
            if abs(drawnBackstop.offset(point).distance)-abs(b.offset(point).distance)>margin {
                throw LaneShapeError("This lane turns back on itself, so the backstop line would cut across it. Use one lane per checkpoint for each leg.")
            }
        }
        func nearFirst(_ line:LanePlanePolyline)->LanePlanePolyline {
            beyond(line.points[0])<=beyond(line.points.last!) ? line : .init(Array(line.points.reversed()),extendStart:false,extendEnd:true)
        }
        let l=nearFirst(l0),r=nearFirst(r0)
        guard beyond(l.points[0])<0 && beyond(r.points[0])<0 else {throw LaneShapeError("Both limits must start on the near side of the backstop")}
        if l.crosses(r) { throw LaneShapeError("The left and right limits cross each other") }
        let start=(l.points[0]+r.points[0])*0.5
        guard beyond(start)<=(-1) else {throw LaneShapeError("The backstop runs through the start of the lane")}
        if let lHit=Self.rayHit(l.points,b.points),let rHit=Self.rayHit(r.points,b.points),beyond(l.points.last!)<0,beyond(r.points.last!)<0,
           Self.segmentsCross(l.points.last!,lHit,r.points.last!,rHit) {
            throw LaneShapeError("The limits meet before the backstop. End them at the backstop, a little apart.")
        }
        func beforeBackstop(_ point:LaneXY)->Bool {beyond(point)<0}
        func insideSide(_ line: LanePlanePolyline,_ other: LanePlanePolyline) throws -> Double {
            var leftVotes = 0, rightVotes = 0
            for i in 0..<(other.points.count-1) {
                let a = other.points[i], d = other.points[i+1]-a
                for k in 0...4 {
                    let p = a+d*(Double(k)/4)
                    guard beforeBackstop(p) else { continue }
                    let offset = line.offset(p)
                    guard offset.inDomain && abs(offset.distance) > 0.5 else { continue }
                    if offset.distance > 0 { leftVotes += 1 } else { rightVotes += 1 }
                }
            }
            guard leftVotes != rightVotes else {
                throw LaneShapeError("Can't tell which side of a limit is inside the lane; draw the limits side by side")
            }
            return leftVotes > rightVotes ? 1 : -1
        }
        let lInside = try insideSide(l,r), rInside = try insideSide(r,l)
        guard lInside != rInside else {throw LaneShapeError("Can't tell the left limit from the right; draw the limits side by side")}
        let ordered = lInside<0
        self.plane = plane; self.backstop = b; self.backstopOutside = backstopOutside
        self.left = ordered ? l : r; self.right = ordered ? r : l
        self.leftOutside = ordered ? -lInside : -rInside; self.rightOutside = ordered ? -rInside : -lInside
        self.leftWasDrawnAsRight = !ordered
    }

    private static func segmentsCross(_ a:LaneXY,_ b:LaneXY,_ c:LaneXY,_ d:LaneXY)->Bool {
        let ab=b-a,cd=d-c
        return ab.cross(c-a)*ab.cross(d-a)<0 && cd.cross(a-c)*cd.cross(b-c)<0
    }
    private static func rayHit(_ points:[LaneXY],_ line:[LaneXY])->LaneXY? {
        let a=points[points.count-2],direction=points.last!-a
        var best:LaneXY?,bestT=Double.infinity
        for i in 0..<(line.count-1) {
            let c=line[i],segment=line[i+1]-c,denominator=direction.cross(segment)
            if abs(denominator)<1e-12 {continue}
            let t=(c-a).cross(segment)/denominator,u=(c-a).cross(direction)/denominator
            if (u>=0 || i==0) && (u<=1 || i==line.count-2) && t>=1 && t<bestT {bestT=t;best=a+direction*t}
        }
        return best
    }

    public func read(_ position: GeoPoint) -> LaneReading {
        let q = plane.project(position)
        func outside(_ line: LanePlanePolyline,_ sign: Double) -> Double? {
            let result = line.offset(q)
            return result.inDomain ? result.distance*sign : nil
        }
        return .init(left: outside(left,leftOutside),right: outside(right,rightOutside),backstop: outside(backstop,backstopOutside))
    }
    /// Extend/trim a side limit at its intersection with the backstop.
    private func joined(_ points: [LaneXY]) -> [LaneXY] {
        let a = points[points.count-2], d = points.last!-a
        var best: LaneXY?, bestT = Double.infinity
        for i in 0..<(backstop.points.count-1) {
            let c = backstop.points[i], s = backstop.points[i+1]-c, denominator = d.cross(s)
            if abs(denominator) < 1e-12 { continue }
            let t = (c-a).cross(s)/denominator, u = (c-a).cross(d)/denominator
            if (u >= 0 || i == 0) && (u <= 1 || i == backstop.points.count-2) && t >= 0 && t < bestT {
                bestT = t; best = a+d*t
            }
        }
        guard let best else { return points }
        let kept = points.dropLast().filter { backstop.offset($0).distance*backstopOutside < 0 }
        return (kept.isEmpty ? [a] : kept)+[best]
    }
    /// Position along the backstop in metres, including its end rays.
    private func measure(_ point: LaneXY) -> Double {
        var best = Double.infinity, result = 0.0, travelled = 0.0
        for i in 0..<(backstop.points.count-1) {
            let a = backstop.points[i], d = backstop.points[i+1]-a
            var t = (point-a).dot(d)/d.dot(d)
            if i != 0 { t = max(0,t) }
            if i != backstop.points.count-2 { t = min(1,t) }
            let delta = point-(a+d*t), distance = delta.dot(delta)
            if distance < best { best = distance; result = travelled+t*d.length }
            travelled += d.length
        }
        return result
    }
    private func intervening(_ a: LaneXY,_ b: LaneXY) -> [LaneXY] {
        let start = measure(a), end = measure(b)
        var distance = 0.0, middle: [LaneXY] = []
        for i in backstop.points.indices {
            if i > 0 { distance += (backstop.points[i]-backstop.points[i-1]).length }
            if distance > min(start,end)+0.01 && distance < max(start,end)-0.01 { middle.append(backstop.points[i]) }
        }
        return start <= end ? middle : Array(middle.reversed())
    }
    public func outline() -> [GeoPoint] {
        let l = joined(left.points), r = joined(right.points)
        return (l+intervening(l.last!,r.last!)+r.reversed()).map(plane.unproject)
    }
    /// Finite visible geometry consistent with the guide: side limits reach the
    /// backstop; its end rays reach at least both side-limit intersections.
    public func mapLines() -> (left: [GeoPoint],right: [GeoPoint],backstop: [GeoPoint]) {
        let l = joined(left.points), r = joined(right.points)
        let ends = [l.last!,r.last!,backstop.points.first!,backstop.points.last!].sorted { measure($0) < measure($1) }
        let b = [ends.first!]+intervening(ends.first!,ends.last!)+[ends.last!]
        return (l.map(plane.unproject),r.map(plane.unproject),b.map(plane.unproject))
    }
}
