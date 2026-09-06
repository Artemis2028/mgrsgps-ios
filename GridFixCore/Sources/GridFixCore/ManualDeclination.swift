import Foundation

/// Convert a fully entered angle only when its reference is known.
///
/// Ported from Android `location/ManualDeclination.kt` at 0.9.32. Returns nil
/// when the text is incomplete, out of range, or a grid-magnetic entry lacks
/// a finite convergence.
public enum ManualDeclination {

    /// East-positive degrees in −180…180, or nil if the entry must not be saved.
    public static func resolve(text: String, east: Bool, mils: Bool,
                               asGridMagnetic: Bool, convergence: Double?) -> Double? {
        guard let entered = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              entered.isFinite else { return nil }
        let degrees = mils ? entered * 360.0 / 6400.0 : entered
        guard degrees >= 0.0 && degrees <= 180.0 else { return nil }
        let signed = east ? degrees : -degrees
        let result: Double
        if asGridMagnetic {
            guard let conv = convergence, conv.isFinite else { return nil }
            result = signed + conv
        } else {
            result = signed
        }
        return ((result + 540.0).truncatingRemainder(dividingBy: 360.0)) - 180.0
    }
}
