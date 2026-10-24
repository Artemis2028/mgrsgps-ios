import GridFixCore
import SwiftUI
import UIKit

/// The Android catalog's exact unit PNGs plus its normalized mission-task paths.
/// No generic flag fallback is used for known military symbols.
@MainActor
enum MilitaryMarkerRenderer {
    private static let cache: NSCache<NSString,UIImage> = {
        let value = NSCache<NSString,UIImage>(); value.totalCostLimit = 16 * 1024 * 1024; return value
    }()
    static func image(symbol: String,affiliation: String = "none",echelon: String = "",rotation: Double = 0,night: Bool = false,metadata: WaypointMetadata = .init()) -> UIImage {
        let key = "\(symbol)|\(affiliation)|\(echelon)|\(rotation)|\(night)|\(metadata.color ?? "")|\(metadata.milgpsSymbolCode ?? -1)" as NSString
        if let image = cache.object(forKey: key) { return image }
        let format = UIGraphicsImageRendererFormat(); format.scale = 2
        let image = UIGraphicsImageRenderer(size: CGSize(width: 64,height: 64),format: format).image { r in
            let c = r.cgContext; c.scaleBy(x: 0.64,y: 0.64); c.setLineCap(.butt); c.setLineJoin(.round)
            let color = color(affiliation,night: night,imported: metadata.color)
            func line(_ x: Double,_ y: Double,_ a: Double,_ b: Double,_ width: Double = 8) {
                c.setStrokeColor(color.cgColor); c.setLineWidth(width); c.move(to: .init(x: x,y: y)); c.addLine(to: .init(x: a,y: b)); c.strokePath()
            }
            func poly(_ points: [(Double,Double)],fill: Bool = false,closed: Bool = false) {
                guard let p = points.first else { return }; c.beginPath(); c.move(to: .init(x: p.0,y: p.1))
                points.dropFirst().forEach { c.addLine(to: .init(x: $0.0,y: $0.1)) }; if closed { c.closePath() }
                c.setStrokeColor(color.cgColor); c.setFillColor(color.cgColor); c.setLineWidth(8)
                if fill { c.fillPath() } else { c.strokePath() }
            }
            func arc(_ x: Double,_ y: Double,_ radius: Double,_ start: Double,_ sweep: Double) {
                c.beginPath(); c.addArc(center: .init(x: x,y: y),radius: radius,startAngle: start * .pi/180,endAngle: (start+sweep) * .pi/180,clockwise: false)
                c.setLineWidth(8); c.setStrokeColor(color.cgColor); c.strokePath()
            }
            func arrow(_ x: Double,_ y: Double,_ angle: Double,_ length: Double = 15,_ solid: Bool = true) {
                let a = angle * .pi/180, back = 150.0 * .pi/180
                let p = (x+length*cos(a+back),y+length*sin(a+back)), q = (x+length*cos(a-back),y+length*sin(a-back))
                if solid { poly([(x,y),p,q],fill: true,closed: true) } else { line(x,y,p.0,p.1); line(x,y,q.0,q.1) }
            }
            func text(_ value: String,_ size: Double = 55) {
                let attributes: [NSAttributedString.Key: Any] = [.font:UIFont.monospacedSystemFont(ofSize: size,weight: .bold),.foregroundColor:color]
                let s = (value as NSString).size(withAttributes: attributes)
                (value as NSString).draw(at: CGPoint(x: 50-s.width/2,y: 50-s.height/2),withAttributes: attributes)
            }
            if let imported = MilGpsSymbols.decode(metadata.milgpsSymbolCode) {
                c.setFillColor(color.cgColor)
                let path = UIBezierPath()
                switch imported.shape {
                case .circle: path.append(UIBezierPath(ovalIn: CGRect(x: 10,y: 10,width: 80,height: 80)))
                case .square: path.append(UIBezierPath(rect: CGRect(x: 12,y: 12,width: 76,height: 76)))
                case .triangle:
                    path.move(to: .init(x: 50,y: 8)); path.addLine(to: .init(x: 94,y: 88)); path.addLine(to: .init(x: 6,y: 88)); path.close()
                case .cross:
                    let p: [(Double,Double)] = [(41,10),(59,10),(59,41),(90,41),(90,59),(59,59),(59,90),(41,90),(41,59),(10,59),(10,41),(41,41)]
                    path.move(to: .init(x: p[0].0,y: p[0].1)); p.dropFirst().forEach { path.addLine(to: .init(x: $0.0,y: $0.1)) }; path.close()
                case .star:
                    for i in 0..<10 {
                        let a = -Double.pi/2 + Double(i) * Double.pi/5, r = i%2 == 0 ? 46.0 : 25.0
                        let p = CGPoint(x: 50+r*cos(a),y: 50+r*sin(a))
                        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }; path.close()
                }
                c.addPath(path.cgPath); c.fillPath()
                c.setStrokeColor(UIColor.black.withAlphaComponent(0.65).cgColor); c.setLineWidth(5.5); c.addPath(path.cgPath); c.strokePath()
                if let char = imported.character {
                    let attrs: [NSAttributedString.Key: Any] = [.font:UIFont.monospacedSystemFont(ofSize: 43,weight: .bold),.foregroundColor:UIColor.black]
                    let size = (char as NSString).size(withAttributes: attrs)
                    (char as NSString).draw(at: CGPoint(x: 50-size.width/2,y: 50-size.height/2+(imported.shape == .triangle ? 9 : 0)),withAttributes: attrs)
                }; return
            }
            if symbol.hasPrefix("nato_"), let source = unitImage(symbol,night: night) {
                source.draw(in: CGRect(x: 0,y: 0,width: 100,height: 100))
                drawEchelon(echelon,color: color,in: c); return
            }
            if symbol.hasPrefix("task_") {
                if let letter = ["task_screen":"S","task_guard":"G","task_cover":"C"][symbol] { text(letter); return }
                c.saveGState(); c.translateBy(x: 50,y: 50); c.rotate(by: rotation * .pi/180); c.translateBy(x: -50,y: -50)
                switch symbol {
                case "task_block": line(8,50,72,50); line(72,16,72,84)
                case "task_sbf":
                    line(16,66,84,66); line(16,66,5,86); line(84,66,95,86)
                    for x in [16.0,84] { line(x,66,x,18); arrow(x,10,-90) }
                case "task_abf": line(50,70,50,16); arrow(50,10,-90); line(50,70,18,92); line(50,70,82,92)
                case "task_ambush":
                    c.beginPath(); c.move(to: .init(x: 10,y: 76)); c.addQuadCurve(to: .init(x: 90,y: 76),control: .init(x: 50,y: 42)); c.setStrokeColor(color.cgColor); c.setLineWidth(8); c.strokePath()
                    for i in 1...6 {
                        let t = Double(i)/7, u = 1-t, x = u*u*10+2*u*t*50+t*t*90, y = u*u*76+2*u*t*42+t*t*76
                        let dx = 80.0, dy = 2*u*(-34)+2*t*34, len = hypot(dx,dy)
                        line(x,y,x-dy/len*11,y+dx/len*11,6.4)
                    }
                    line(50,59,50,14); arrow(50,8,-90)
                case "task_fix":
                    line(6,50,22,50)
                    var x = 22.0, up = true
                    while x < 66 { line(x,up ? 50 : 32,x+11,up ? 32 : 50); x += 11; up.toggle() }
                    line(x,50,86,50); arrow(92,50,0,15,false)
                case "task_secure":
                    arc(50,50,32,-60,300); arrow(50+32*cos(240 * .pi/180),50+32*sin(240 * .pi/180),330)
                case "task_occupy":
                    c.setStrokeColor(color.cgColor); c.setLineWidth(8); c.strokeEllipse(in: CGRect(x: 20,y: 20,width: 60,height: 60))
                    line(5,95,45,55); line(35,45,55,65); line(35,65,55,45)
                case "task_retain","task_isolate":
                    let isolate = symbol == "task_isolate", start = isolate ? -70.0 : -50.0, sweep = isolate ? 320.0 : 280.0
                    arc(50,50,26,start,sweep)
                    for i in 0..<(isolate ? 8 : 10) {
                        let a = (isolate ? -60+300*Double(i)/7 : -50+280*Double(i)/9) * .pi/180
                        if isolate {
                            poly([(50+26*cos(a-0.1),50+26*sin(a-0.1)),(50+35.1*cos(a),50+35.1*sin(a)),(50+26*cos(a+0.1),50+26*sin(a+0.1))],fill: true,closed: true)
                        } else { line(50+26*cos(a),50+26*sin(a),50+36.4*cos(a),50+36.4*sin(a),6) }
                    }
                    if isolate { arrow(50+26*cos(250 * .pi/180),50+26*sin(250 * .pi/180),340,13) }
                    else { line(50,2,50,28); arrow(50,34,90,13) }
                case "task_seize":
                    c.setStrokeColor(color.cgColor); c.setLineWidth(8); c.strokeEllipse(in: CGRect(x: 50,y: 18,width: 32,height: 32))
                    arc(66,34,40,100,130); arrow(66+40*cos(230 * .pi/180),34+40*sin(230 * .pi/180),320,14)
                case "task_clear":
                    line(86,18,86,82); for y in [26.0,50,74] { line(86,y,24,y); arrow(16,y,180,13) }
                case "task_destroy": line(16,16,84,84); line(16,84,84,16)
                case "task_contain":
                    arc(50,52,32,180,180); for x in [18.0,82] { line(x,52,x,68); arrow(x,74,90,12) }
                case "task_disrupt":
                    line(28,14,28,86); for (i,x) in [66.0,86,66].enumerated() { let y = 24+26*Double(i); line(28,y,x,y); arrow(x+6,y,0,12) }
                case "task_breach":
                    for x in [32.0,68] { line(x,12,x,38); line(x,62,x,88) }; line(6,50,82,50); arrow(90,50,0,14)
                case "task_bypass":
                    line(40,46,40,88); line(60,46,60,88)
                    c.beginPath(); c.move(to: .init(x: 10,y: 86)); c.addQuadCurve(to: .init(x: 90,y: 72),control: .init(x: 50,y: -14)); c.setStrokeColor(color.cgColor); c.setLineWidth(8); c.strokePath(); arrow(92,80,78,13)
                case "task_penetrate": line(14,38,86,38); line(50,92,50,20); arrow(50,12,-90)
                default: text("?")
                }
                c.restoreGState(); if symbol == "task_contain" { text("ENY",20) }; return
            }
            c.setStrokeColor(color.cgColor); c.setFillColor(color.cgColor); c.setLineWidth(7)
            switch affiliation {
            case "friendly":
                let frame = UIBezierPath(roundedRect: CGRect(x: 4,y: 20,width: 92,height: 60),cornerRadius: 8); frame.lineWidth = 7; frame.stroke()
            case "hostile": poly([(50,5),(95,50),(50,95),(5,50)],closed: true)
            case "neutral": c.stroke(CGRect(x: 10,y: 10,width: 80,height: 80))
            case "unknown": c.strokeEllipse(in: CGRect(x: 6,y: 6,width: 88,height: 88))
            default: break
            }
            switch symbol {
            case "dot": c.fillEllipse(in: CGRect(x: 33.8,y: 33.8,width: 32.4,height: 32.4))
            case "square": c.fill(CGRect(x: 34.88,y: 34.88,width: 30.24,height: 30.24))
            case "triangle": poly([(50,30.2),(70.88,65.12),(29.12,65.12)],fill: true,closed: true)
            case "diamond": poly([(50,28.4),(71.6,50),(50,71.6),(28.4,50)],fill: true,closed: true)
            case "cross": c.saveGState(); c.translateBy(x: 50,y: 50); c.rotate(by: .pi/4); line(-21.6,0,21.6,0,10.8); line(0,-21.6,0,21.6,10.8); c.restoreGState()
            default:
                let names = ["flag":"flag","target":"scope","star":"star","home":"house","danger":"exclamationmark.triangle","water":"drop","camp":"tent","vehicle":"car","antenna":"antenna.radiowaves.left.and.right","medic":"cross.case"]
                UIImage(systemName: names[symbol] ?? "questionmark.square.dashed")?.withTintColor(color,renderingMode: .alwaysOriginal).draw(in: CGRect(x: 25,y: 25,width: 50,height: 50))
            }
            drawEchelon(echelon,color: color,in: c)
        }
        cache.setObject(image,forKey: key,cost: 128*128*4); return image
    }
    static func image(_ waypoint: Waypoint,night: Bool) -> UIImage { image(symbol: waypoint.symbol,affiliation: waypoint.affiliation,echelon: waypoint.echelon,rotation: waypoint.rotation,night: night,metadata: waypoint.metadata) }
    static func color(_ affiliation: String,night: Bool,imported: String? = nil) -> UIColor {
        if night { return .systemRed }
        if let imported, MilGpsSymbols.colors.contains(imported.lowercased()) { return WaypointMarkerStyle(waypoint: Waypoint(id: "preview",name: "",lat: 0,lon: 0,metadata: .init(color: imported)),night: false).color }
        switch affiliation {
        case "friendly": return .init(red: 91/255,green: 200/255,blue: 245/255,alpha: 1)
        case "hostile": return .init(red: 1,green: 107/255,blue: 96/255,alpha: 1)
        case "neutral": return .init(red: 143/255,green: 227/255,blue: 143/255,alpha: 1)
        case "unknown": return .init(red: 240/255,green: 224/255,blue: 96/255,alpha: 1)
        default: return UIColor(Blackout.accent)
        }
    }
    static func unitImage(_ key: String,night: Bool) -> UIImage? {
        let name = "asset|\(key)|\(night)" as NSString
        if let cached = cache.object(forKey: name) { return cached }
        guard let url = Bundle.main.url(forResource: key,withExtension: "png",subdirectory: "MilitarySymbols"), let input = UIImage(contentsOfFile: url.path)?.cgImage else { return nil }
        let width = input.width, height = input.height
        var bytes = [UInt8](repeating: 0,count: width*height*4)
        let ok = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let c = CGContext(data: buffer.baseAddress,width: width,height: height,bitsPerComponent: 8,bytesPerRow: width*4,space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            c.draw(input,in: CGRect(x: 0,y: 0,width: width,height: height)); return true
        }
        guard ok else { return nil }
        for i in stride(from: 0,to: bytes.count,by: 4) {
            if bytes[i] < 40 && bytes[i+1] < 40 && bytes[i+2] < 40 { bytes[i] = 0; bytes[i+1] = 0; bytes[i+2] = 0; bytes[i+3] = 0 }
            else if night { bytes[i] = UInt8(min(255,0.35*Double(bytes[i])+0.5*Double(bytes[i+1])+0.15*Double(bytes[i+2])+30)); bytes[i+1] = 0; bytes[i+2] = 0 }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData), let output = CGImage(width: width,height: height,bitsPerComponent: 8,bitsPerPixel: 32,bytesPerRow: width*4,space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),provider: provider,decode: nil,shouldInterpolate: true,intent: .defaultIntent) else { return nil }
        let result = UIImage(cgImage: output); cache.setObject(result,forKey: name,cost: width*height*4); return result
    }
    private static func drawEchelon(_ key: String,color: UIColor,in c: CGContext) {
        guard !key.isEmpty else { return }
        func line(_ a: CGPoint,_ b: CGPoint) {
            c.setLineWidth(10.83); c.setStrokeColor(UIColor.black.cgColor); c.move(to: a); c.addLine(to: b); c.strokePath()
            c.setLineWidth(5.7); c.setStrokeColor(color.cgColor); c.move(to: a); c.addLine(to: b); c.strokePath()
        }
        if key == "tm" {
            for (width,ink) in [(10.83,UIColor.black),(5.7,color)] { c.setLineWidth(width); c.setStrokeColor(ink.cgColor); c.strokeEllipse(in: CGRect(x: 38.22,y: -1.78,width: 23.56,height: 23.56)) }
            line(.init(x: 33.85,y: 26.15),.init(x: 66.15,y: -6.15)); return
        }
        let dots = ["sqd":1,"sec":2,"plt":3], bars = ["co":1,"bn":2,"rgt":3], crosses = ["bde":1,"div":2,"corps":3,"army":4]
        let count = dots[key] ?? bars[key] ?? crosses[key] ?? 0
        let gap = dots[key] != nil ? 14.82 : (bars[key] != nil ? 11.78 : 25.65)
        for i in 0..<count {
            let x = 50-gap*Double(count-1)/2+gap*Double(i)
            if dots[key] != nil {
                c.setFillColor(UIColor.black.cgColor); c.fillEllipse(in: CGRect(x: x-8.55,y: 1.45,width: 17.1,height: 17.1))
                c.setFillColor(color.cgColor); c.fillEllipse(in: CGRect(x: x-5.7,y: 4.3,width: 11.4,height: 11.4))
            } else if bars[key] != nil { line(.init(x: x,y: -0.45),.init(x: x,y: 20.45)) }
            else { line(.init(x: x-10.45,y: -0.45),.init(x: x+10.45,y: 20.45)); line(.init(x: x-10.45,y: 20.45),.init(x: x+10.45,y: -0.45)) }
        }
    }
}

struct MilitaryMarker: View {
    let symbol: String
    var affiliation = "none"
    var echelon = ""
    var rotation = 0.0
    var metadata = WaypointMetadata()
    @Environment(\.fieldNight) private var night
    var body: some View { Image(uiImage: MilitaryMarkerRenderer.image(symbol: symbol,affiliation: affiliation,echelon: echelon,rotation: rotation,night: night,metadata: metadata)).resizable().scaledToFit().accessibilityLabel(MilitarySymbols.label(symbol)) }
}
