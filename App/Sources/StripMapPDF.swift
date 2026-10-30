import GridFixCore
import UIKit

/// A4 route schematic and complete leg table. The PDF is always paper white,
/// independent of the field UI's night mode, and uses the same prepared rows.
enum StripMapPDF {
    static let page = CGRect(x: 0,y: 0,width: 595,height: 842)
    private static let margin: CGFloat = 40, contentWidth: CGFloat = 515, bottom: CGFloat = 802
    private static let rowHeight: CGFloat = 13
    private static let titleFont = UIFont.monospacedSystemFont(ofSize: 16,weight: .bold)
    private static let bodyFont = UIFont.monospacedSystemFont(ofSize: 9.5,weight: .regular)
    private static let boldFont = UIFont.monospacedSystemFont(ofSize: 9.5,weight: .bold)
    private static let smallFont = UIFont.monospacedSystemFont(ofSize: 8,weight: .regular)
    private struct PagePlan { var rows: Range<Int>; var overview: Bool; var totals: Bool; var tableY: CGFloat; var firstRowY: CGFloat }

    static func render(_ report: RouteCard.Report) throws -> Data {
        try Task.checkCancellation()
        let title = "ROUTE CARD - "+report.name.uppercased(with: Locale(identifier: "en_US_POSIX"))
        let titleHeight = height(title,font: titleFont)
        guard titleHeight <= 160 else { throw RouteCard.Failure.invalid("The route name is too long for a printable card. Shorten its name and export again.") }
        let continued = title+" (CONT.)", continuedHeight = height(continued,font: boldFont)
        let sketch = try RouteSketch.layout(report.points,width: Double(contentWidth),height: 280)
        let annotations = try plotLabels(sketch,closed: report.points.first == report.points.last)
        var notes = ["AZ: from leg start. BACK: from leg end. Verify bearings and grids before stepping off."]+report.notes
        if annotations.omitted > 0 { notes.append("Overview labels omitted for \(annotations.omitted) legs to avoid overlap. Every leg is listed in the table.") }
        let noteText = notes.joined(separator: "\n"), noteHeight = height(noteText,font: smallFont)
        let summaryHeight = 30+noteHeight
        let rowHeights = try report.rows.map { row -> CGFloat in
            try Task.checkCancellation()
            return rowHeight+(row.limits.map { height($0,font: smallFont)+4 } ?? 0)
        }
        var accumulated: [CGFloat] = [0]
        for height in rowHeights { accumulated.append(accumulated.last!+height) }
        var plans: [PagePlan] = [], index = 0
        while index < report.rows.count {
            let overview = plans.isEmpty
            let metadataY = margin+(overview ? titleHeight : continuedHeight)+12
            let gridY = overview ? metadataY+10+280+18 : metadataY+16
            let tableY = gridY+14, firstRowY = tableY+17
            var capacity = 0, rowBottom = firstRowY
            for height in rowHeights[index...] {
                if rowBottom+height > bottom { break }
                capacity += 1; rowBottom += height
            }
            if capacity == 0 {
                if overview { plans.append(.init(rows: index..<index,overview: true,totals: false,tableY: tableY,firstRowY: firstRowY)); continue }
                throw RouteCard.Failure.invalid("A lane label exceeds the printable page. Shorten its landmark names and retry.")
            }
            let remaining = report.rows.count-index
            let fitsSummary = firstRowY+accumulated.last!-accumulated[index]+summaryHeight <= bottom
            let count = fitsSummary ? remaining : min(capacity,max(1,remaining-1))
            plans.append(.init(rows: index..<(index+count),overview: overview,totals: fitsSummary,tableY: tableY,firstRowY: firstRowY))
            index += count
        }
        guard plans.last?.totals == true else { throw RouteCard.Failure.invalid("Route notes exceed the printable page. Shorten the route name and retry.") }
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String:title,kCGPDFContextCreator as String:"MGRS GPS iOS",kCGPDFContextSubject as String:"Route schematic and navigation leg table"]
        let renderer = UIGraphicsPDFRenderer(bounds: page,format: format)
        var cancelled = false
        let data = renderer.pdfData { context in
            for (number,plan) in plans.enumerated() {
                if Task.isCancelled { cancelled = true; break }
                context.beginPage(); let canvas = context.cgContext
                canvas.setFillColor(UIColor.white.cgColor); canvas.fill(page)
                paragraph(plan.overview ? title : continued,at: .init(x: margin,y: margin),font: plan.overview ? titleFont : boldFont)
                let metadataY = margin+(plan.overview ? titleHeight : continuedHeight)+12
                text("\(report.dtg) - north \(report.configuration.referenceLetter) - pace \(report.configuration.pacePer100m)/100 m - MGRS GPS",x: margin,y: metadataY,font: smallFont)
                if plan.overview { drawSketch(sketch,annotations: annotations,in: .init(x: margin,y: metadataY+10,width: contentWidth,height: 280),canvas: canvas) }
                text("START  "+report.startGrid,x: margin,y: plan.tableY-14,font: boldFont)
                tableHeader(at: plan.tableY,reference: report.configuration.referenceLetter,canvas: canvas)
                var y = plan.firstRowY
                for i in plan.rows {
                    if Task.isCancelled { cancelled = true; break }
                    let row = report.rows[i]
                    let values = [String(row.index),row.azimuth,row.backAzimuth,row.distance,String(row.paces),row.destinationGrid]
                    for (column,value) in values.enumerated() { text(value,x: columns[column],y: y,font: bodyFont) }
                    if let limits = row.limits { paragraph(limits,at: .init(x: margin,y: y+4),font: smallFont) }
                    y += rowHeights[i]
                }
                if cancelled { break }
                if plan.totals {
                    let summaryY = y+4
                    line(.init(x: margin,y: summaryY),.init(x: page.width-margin,y: summaryY),width: 0.8,canvas: canvas)
                    text("TOTAL  \(report.totalDistance)   \(report.totalPaces) paces",x: margin,y: summaryY+14,font: boldFont)
                    paragraph(noteText,at: .init(x: margin,y: summaryY+26),font: smallFont)
                }
                text("MGRS GPS - route card",x: margin,y: 824,font: smallFont,color: .darkGray)
                let footer = "Page \(number+1) of \(plans.count)"
                text(footer,x: page.width-margin-size(footer,font: smallFont).width,y: 824,font: smallFont,color: .darkGray)
            }
        }
        if cancelled { throw CancellationError() }
        try Task.checkCancellation()
        return data
    }
    static func filename(_ name: String) -> String {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = (title.isEmpty ? "route" : title).replacingOccurrences(of: "[^A-Za-z0-9_-]",with: "_",options: .regularExpression)
        return "gridfix_route_"+String(safe.prefix(100))
    }
    private static let columns: [CGFloat] = [40,74,168,262,340,398]
    private static func tableHeader(at y: CGFloat,reference: String,canvas: CGContext) {
        for (i,label) in ["LEG","AZ (\(reference))","BACK","DIST","PACES","TO GRID (8-DIGIT)"].enumerated() { text(label,x: columns[i],y: y,font: boldFont) }
        line(.init(x: margin,y: y+5),.init(x: page.width-margin,y: y+5),width: 0.8,canvas: canvas)
    }
    private static func attributes(_ font: UIFont,_ color: UIColor = .black) -> [NSAttributedString.Key:Any] { [.font:font,.foregroundColor:color] }
    private static func size(_ value: String,font: UIFont) -> CGSize { (value as NSString).size(withAttributes: attributes(font)) }
    private static func height(_ value: String,font: UIFont) -> CGFloat {
        ceil((value as NSString).boundingRect(with: .init(width: contentWidth,height: .greatestFiniteMagnitude),options: [.usesLineFragmentOrigin,.usesFontLeading],attributes: attributes(font),context: nil).height)
    }
    private static func text(_ value: String,x: CGFloat,y: CGFloat,font: UIFont,color: UIColor = .black) { (value as NSString).draw(at: .init(x: x,y: y-font.ascender),withAttributes: attributes(font,color)) }
    private static func paragraph(_ value: String,at point: CGPoint,font: UIFont) {
        (value as NSString).draw(with: .init(origin: point,size: .init(width: contentWidth,height: height(value,font: font)+1)),options: [.usesLineFragmentOrigin,.usesFontLeading],attributes: attributes(font),context: nil)
    }
    private static func line(_ a: CGPoint,_ b: CGPoint,width: CGFloat,canvas: CGContext) {
        canvas.setStrokeColor(UIColor.black.cgColor); canvas.setLineWidth(width); canvas.move(to: a); canvas.addLine(to: b); canvas.strokePath()
    }
    private struct PlotLabel { var value: String; var rect: CGRect }
    private struct PlotAnnotations { var labels: [PlotLabel]; var omitted: Int }
    private static func plotLabels(_ sketch: RouteSketch.Layout,closed: Bool) throws -> PlotAnnotations {
        var labels: [PlotLabel] = [], omitted = 0
        // Fixed-size spatial bins keep dense imported routes linear in vertex
        // count instead of testing every candidate against all placed labels.
        var occupied: [Int:[CGRect]] = [:]
        func cells(_ rect: CGRect) -> (ClosedRange<Int>,ClosedRange<Int>) {
            (Int(floor(rect.minX/24))...Int(floor(rect.maxX/24)),Int(floor(rect.minY/24))...Int(floor(rect.maxY/24)))
        }
        func reserve(_ rect: CGRect) {
            let (xs,ys) = cells(rect)
            for x in xs { for y in ys { occupied[x*64+y,default: []].append(rect) } }
        }
        func overlaps(_ rect: CGRect) -> Bool {
            let (xs,ys) = cells(rect)
            for x in xs { for y in ys { if occupied[x*64+y,default: []].contains(where: { $0.intersects(rect) }) { return true } } }
            return false
        }
        reserve(CGRect(x: contentWidth-44,y: 4,width: 40,height: 48))
        reserve(CGRect(x: 8,y: 246,width: contentWidth-16,height: 30))
        let bounds = CGRect(x: 4,y: 30,width: contentWidth-8,height: 212)
        func place(_ value: String,_ point: CGPoint,priority: Bool = false) -> Bool {
            let measure = size(value,font: boldFont)
            let positions: [CGPoint] = [
                .init(x: point.x+5,y: point.y-measure.height-4),.init(x: point.x+5,y: point.y+4),
                .init(x: point.x-measure.width-5,y: point.y-measure.height-4),.init(x: point.x-measure.width-5,y: point.y+4),
                .init(x: point.x-measure.width/2,y: point.y-measure.height-12),.init(x: point.x-measure.width/2,y: point.y+12)
            ]
            let choices = positions.map { CGRect(origin: $0,size: measure).insetBy(dx: -2,dy: -1) }
            for rect in choices where bounds.contains(rect) && !overlaps(rect) {
                labels.append(.init(value: value,rect: rect)); reserve(rect.insetBy(dx: -2,dy: -2)); return true
            }
            if priority {
                let rect = CGRect(x: min(max(point.x+5,8),contentWidth-measure.width-8),y: min(max(point.y+5,32),230-measure.height),width: measure.width,height: measure.height)
                labels.append(.init(value: value,rect: rect)); reserve(rect.insetBy(dx: -3,dy: -3)); return true
            }
            return false
        }
        let points = sketch.points.map { CGPoint(x: $0.x,y: $0.y) }
        if let start = points.first, let end = points.last {
            if closed { _ = place("SP / RP",start,priority: true) }
            else { _ = place("SP",start,priority: true); _ = place("RP",end,priority: true) }
        }
        for i in 0..<(points.count-1) {
            if i % 128 == 0 { try Task.checkCancellation() }
            let middle = CGPoint(x: (points[i].x+points[i+1].x)/2,y: (points[i].y+points[i+1].y)/2)
            if !place(String(i+1),middle) { omitted += 1 }
        }
        return .init(labels: labels,omitted: omitted)
    }
    private static func drawSketch(_ sketch: RouteSketch.Layout,annotations: PlotAnnotations,in box: CGRect,canvas: CGContext) {
        canvas.saveGState(); canvas.translateBy(x: box.minX,y: box.minY)
        let rect = CGRect(origin: .zero,size: box.size)
        canvas.setStrokeColor(UIColor.darkGray.cgColor); canvas.setLineWidth(0.8); canvas.stroke(rect)
        text("ROUTE SCHEMATIC - TRUE NORTH UP",x: 12,y: 16,font: smallFont)
        let points = sketch.points.map { CGPoint(x: $0.x,y: $0.y) }
        canvas.setStrokeColor(UIColor.black.cgColor); canvas.setLineWidth(2); canvas.setLineJoin(.round)
        if let first = points.first { canvas.move(to: first); for p in points.dropFirst() { canvas.addLine(to: p) }; canvas.strokePath() }
        canvas.setFillColor(UIColor.black.cgColor)
        for point in points { canvas.fillEllipse(in: .init(x: point.x-3,y: point.y-3,width: 6,height: 6)) }
        for label in annotations.labels {
            canvas.setFillColor(UIColor.white.cgColor); canvas.fill(label.rect)
            text(label.value,x: label.rect.minX+2,y: label.rect.minY+1+boldFont.ascender,font: boldFont)
        }
        let nx = box.width-24
        line(.init(x: nx,y: 38),.init(x: nx,y: 16),width: 2,canvas: canvas)
        canvas.move(to: .init(x: nx,y: 12)); canvas.addLine(to: .init(x: nx-4,y: 21)); canvas.addLine(to: .init(x: nx+4,y: 21)); canvas.closePath()
        canvas.setFillColor(UIColor.black.cgColor); canvas.fillPath()
        text("N",x: nx-3,y: 48,font: boldFont)
        let x: CGFloat = 12, y = box.height-14, length = CGFloat(sketch.scaleBar.lengthPoints)
        line(.init(x: x,y: y),.init(x: x+length,y: y),width: 2,canvas: canvas)
        for end in [x,x+length] { line(.init(x: end,y: y-4),.init(x: end,y: y+4),width: 2,canvas: canvas) }
        let scale = "approx. "+sketch.scaleBar.label
        let labelX = max(x,min(box.width-size(scale,font: bodyFont).width-6,x+length/2-size(scale,font: bodyFont).width/2))
        text(scale,x: labelX,y: y-7,font: bodyFont)
        canvas.restoreGState()
    }
}
