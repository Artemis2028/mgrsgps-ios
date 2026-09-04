import Foundation
import XCTest

/// The shared fixture. The same file ships in the Android repo and is read by
/// `CoordinatesGoldenTest.kt`, so a change on one platform that the other does
/// not match turns a build red instead of turning up in the field.
struct Golden: Decodable {
    struct Tolerances: Decodable {
        let utmMeters: Double
        let latLonDegrees: Double
        let distanceMeters: Double
        let bearingDegrees: Double
        let convergenceDegrees: Double
    }
    struct UTMVector: Decodable {
        let name: String
        let lat: Double
        let lon: Double
        let zone: Int
        let hemisphere: String
        let easting: Double
        let northing: Double
        let band: String
    }
    struct ForwardVector: Decodable {
        let name: String
        let lat: Double
        let lon: Double
        let digits: Int
        let mgrs: String
    }
    struct ParseVector: Decodable {
        let mgrs: String
        let centreLat: Double
        let centreLon: Double
        let cornerLat: Double
        let cornerLon: Double
    }
    struct DistanceVector: Decodable {
        let name: String
        let fromLat: Double
        let fromLon: Double
        let toLat: Double
        let toLon: Double
        let meters: Double
        let bearing: Double
    }
    struct GraphicGeometryVector: Decodable {
        let type: String
        let vertexCount: Int
        /// "Point", "LineString", "Polygon", or "none" for nothing to draw.
        let kind: String
    }
    struct ConvergenceVector: Decodable {
        let lat: Double
        let lon: Double
        let zone: Int
        let degrees: Double
    }

    let schema: Int
    let tolerances: Tolerances
    let utm: [UTMVector]
    let mgrsForward: [ForwardVector]
    let mgrsParse: [ParseVector]
    let distance: [DistanceVector]
    let convergence: [ConvergenceVector]
    let graphicGeometry: [GraphicGeometryVector]
    let areaTypes: [String]

    static func load() throws -> Golden {
        guard let url = Bundle.module.url(forResource: "golden", withExtension: "json") else {
            throw NSError(domain: "Golden", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "golden.json is not in the test bundle",
            ])
        }
        return try JSONDecoder().decode(Golden.self, from: Data(contentsOf: url))
    }
}
