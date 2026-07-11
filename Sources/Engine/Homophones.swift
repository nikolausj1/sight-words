import Foundation

/// Lookup table for voice-check homophone matching (PRD §6.8). Parses a JSON array
/// of groups, e.g. `[["to","two","too"], ["there","their","they're"]]`.
///
/// The JSON file itself (`homophones.json`) is another worker's deliverable and
/// lives in Resources/ -- this type only knows how to parse whatever `Data` it's
/// given, so it's tested here with small inline JSON.
public struct HomophoneTable {
    private var groupIndex: [String: Int] = [:]

    public init(json: Data) {
        guard let groups = try? JSONDecoder().decode([[String]].self, from: json) else {
            return
        }
        for (i, group) in groups.enumerated() {
            for word in group {
                groupIndex[word.lowercased()] = i
            }
        }
    }

    /// True if `heard` should be accepted as a match for `target`: identical
    /// (case-insensitive) or both members of the same homophone group.
    public func matches(heard: String, target: String) -> Bool {
        let h = heard.lowercased()
        let t = target.lowercased()
        if h == t { return true }
        guard let hi = groupIndex[h], let ti = groupIndex[t] else { return false }
        return hi == ti
    }
}
