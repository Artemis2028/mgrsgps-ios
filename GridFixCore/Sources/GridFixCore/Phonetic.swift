import Foundation

/// NATO phonetic alphabet (ICAO/ACP-125) with military digit pronunciation —
/// Tree, Fower, Fife, Niner. Used to spell a grid for radio and to feed the
/// voice callout. Identical to the Android table.
public enum Phonetic {

    public static let letters: [Character: String] = [
        "A": "Alfa", "B": "Bravo", "C": "Charlie", "D": "Delta",
        "E": "Echo", "F": "Foxtrot", "G": "Golf", "H": "Hotel",
        "I": "India", "J": "Juliett", "K": "Kilo", "L": "Lima",
        "M": "Mike", "N": "November", "O": "Oscar", "P": "Papa",
        "Q": "Quebec", "R": "Romeo", "S": "Sierra", "T": "Tango",
        "U": "Uniform", "V": "Victor", "W": "Whiskey", "X": "Xray",
        "Y": "Yankee", "Z": "Zulu",
    ]

    public static let digits: [Character: String] = [
        "0": "Zero", "1": "One", "2": "Two", "3": "Tree",
        "4": "Fower", "5": "Fife", "6": "Six", "7": "Seven",
        "8": "Eight", "9": "Niner",
    ]

    static func word(_ c: Character) -> String? {
        // c.uppercased() can be more than one character (ß becomes SS), so take
        // the first rather than trapping on the Character initialiser.
        if let upper = c.uppercased().first, let l = letters[upper] { return l }
        return digits[c]
    }

    /// Spell one contiguous group: "VP" becomes "Victor Papa".
    public static func spellGroup(_ group: String) -> String {
        group.compactMap { word($0) }.joined(separator: " ")
    }

    /// Spell a full MGRS string for display, groups separated by a mid dot.
    public static func mgrs(_ full: String) -> String {
        groups(full).joined(separator: " · ")
    }

    /// The same content with comma pauses, for text to speech.
    public static func mgrsSpeech(_ full: String) -> String {
        groups(full).joined(separator: ", ")
    }

    static func groups(_ full: String) -> [String] {
        full.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .map { spellGroup(String($0)) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}
