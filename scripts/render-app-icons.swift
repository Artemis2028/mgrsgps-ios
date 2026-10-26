#!/usr/bin/env swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// GridFix Android release/1.1.0: drawable/ic_launcher_foreground.xml and
// values/colors.xml. Keep the original 108-unit geometry and opaque background;
// each platform applies its own icon mask, so do not bake rounded corners in.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let phone = root.appendingPathComponent("App/Resources/Assets.xcassets")
let watch = root.appendingPathComponent("Watch/Resources/Assets.xcassets")
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let background = CGColor(colorSpace: space,components: [11/255,14/255,19/255,1])!
let foreground = CGColor(colorSpace: space,components: [123/255,198/255,126/255,1])!

func json(_ value: Any,to url: URL) throws {
    try JSONSerialization.data(withJSONObject: value,options: [.prettyPrinted,.sortedKeys]).write(to: url,options: .atomic)
}
func render(_ size: Int,to url: URL) throws {
    // RGB without alpha is required for opaque App Store artwork.
    guard let context = CGContext(data: nil,width: size,height: size,bitsPerComponent: 8,bytesPerRow: size*4,
                                  space: space,bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("Cannot create icon bitmap") }
    context.setFillColor(background); context.fill(CGRect(x: 0,y: 0,width: size,height: size))
    context.scaleBy(x: CGFloat(size)/108,y: CGFloat(size)/108)
    context.setShouldAntialias(true)
    context.setStrokeColor(foreground); context.setLineWidth(4)
    context.strokeEllipse(in: CGRect(x: 30,y: 30,width: 48,height: 48))
    context.setLineCap(.round)
    for (x1,y1,x2,y2) in [(54,22,54,38),(54,70,54,86),(22,54,38,54),(70,54,86,54)] {
        context.move(to: CGPoint(x: x1,y: y1)); context.addLine(to: CGPoint(x: x2,y: y2)); context.strokePath()
    }
    context.setFillColor(foreground); context.fillEllipse(in: CGRect(x: 50.5,y: 50.5,width: 7,height: 7))
    guard let image = context.makeImage(),let destination = CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil) else { fatalError("Cannot encode icon") }
    CGImageDestinationAddImage(destination,image,nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Cannot write icon") }
}

for assets in [phone,watch] {
    try FileManager.default.createDirectory(at: assets.appendingPathComponent("AppIcon.appiconset"),withIntermediateDirectories: true)
    try json(["info":["author":"xcode","version":1]],to: assets.appendingPathComponent("Contents.json"))
}
// Explicit legacy slots preserve iOS 16 iPhone/iPad compatibility as well as
// the full-size marketing image. Reuse equal-size renders, rather than resize
// a previously rasterized mark and soften its thin strokes.
let slots: [(String,String,String)] = [
    ("iphone","20x20","2x"),("iphone","20x20","3x"),
    ("iphone","29x29","2x"),("iphone","29x29","3x"),
    ("iphone","40x40","2x"),("iphone","40x40","3x"),
    ("iphone","60x60","2x"),("iphone","60x60","3x"),
    ("ipad","20x20","1x"),("ipad","20x20","2x"),
    ("ipad","29x29","1x"),("ipad","29x29","2x"),
    ("ipad","40x40","1x"),("ipad","40x40","2x"),
    ("ipad","76x76","1x"),("ipad","76x76","2x"),("ipad","83.5x83.5","2x"),
    ("ios-marketing","1024x1024","1x")
]
var images: [[String: String]] = [],rendered = Set<Int>()
for (idiom,size,scale) in slots {
    let pixels = Int((Double(size.components(separatedBy: "x")[0])!*Double(scale.dropLast())!).rounded())
    let filename = "GridFix-\(pixels).png"
    if rendered.insert(pixels).inserted { try render(pixels,to: phone.appendingPathComponent("AppIcon.appiconset/"+filename)) }
    images.append(["idiom":idiom,"size":size,"scale":scale,"filename":filename])
}
try json(["images":images,"info":["author":"xcode","version":1]],to: phone.appendingPathComponent("AppIcon.appiconset/Contents.json"))
try render(1024,to: watch.appendingPathComponent("AppIcon.appiconset/GridFix-1024.png"))
try json(["images":[["idiom":"universal","platform":"watchos","size":"1024x1024","filename":"GridFix-1024.png"]],
          "info":["author":"xcode","version":1]],to: watch.appendingPathComponent("AppIcon.appiconset/Contents.json"))
print("Rendered Android GridFix mark for iPhone/iPad and Apple Watch")
