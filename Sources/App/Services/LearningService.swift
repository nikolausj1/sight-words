import Foundation
import SwiftData

/// Bridges SwiftData persistence to the pure Engine, scoped to one profile at a
/// time: seeding, profile bootstrap, pool building for the session builder, and
/// recording results. Owns every `ModelContext` mutation (Math Tutor pattern).
@MainActor
struct LearningService {
    let context: ModelContext

    // MARK: Bootstrap

    /// Idempotent: seeds the Dolch word catalog once, and creates a default
    /// active profile if none exists yet.
    func bootstrap() {
        seedWordsIfNeeded()
        let profiles = allProfiles()
        if profiles.isEmpty {
            let p = Profile(name: "Player 1", level: "K", onboarded: false, isActive: true,
                            activeListIDs: ["dolchPrePrimer", "dolchPrimer"])
            context.insert(p)
        } else if !profiles.contains(where: { $0.isActive }) {
            profiles[0].isActive = true
        }
        try? context.save()
    }

    private func seedWordsIfNeeded() {
        let existing = (try? context.fetchCount(FetchDescriptor<WordRecord>())) ?? 0
        guard existing == 0 else { return }
        guard let url = Bundle.main.url(forResource: "dolch-words", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return }
        struct Entry: Decodable { let text: String; let list: String; let sentence: String? }
        guard let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        for e in entries {
            let w = WordRecord(text: Self.normalize(e.text), listID: e.list,
                               sentence: e.sentence, isCustom: false)
            context.insert(w)
        }
        try? context.save()
    }

    /// "I" stays capitalized; every other word is lowercased — applies to both
    /// bundled Dolch content and future custom words (dedup happens on this form).
    static func normalize(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.lowercased() == "i" ? "I" : trimmed.lowercased()
    }

    // MARK: Profiles

    func allProfiles() -> [Profile] {
        (try? context.fetch(FetchDescriptor<Profile>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    }

    func activeProfile() -> Profile {
        if let a = allProfiles().first(where: { $0.isActive }) { return a }
        if let f = allProfiles().first { f.isActive = true; try? context.save(); return f }
        let p = Profile(); context.insert(p); try? context.save(); return p
    }

    // MARK: Word catalog

    private func allWordRecords() -> [WordRecord] {
        (try? context.fetch(FetchDescriptor<WordRecord>())) ?? []
    }

    /// Words active for a profile's current lists (Dolch + custom).
    func activeWords(for profile: Profile) -> [WordRecord] {
        allWordRecords().filter { profile.activeListIDs.contains($0.listID) }
    }

    func hasActiveWords(for profile: Profile) -> Bool { !activeWords(for: profile).isEmpty }

    /// Engine `WordSnapshot.id` is always lowercased, so "I" round-trips as "i" —
    /// these two helpers translate back to the real display/lookup text.
    func sentence(for engineID: String) -> String? {
        allWordRecords().first { $0.text.lowercased() == engineID }?.sentence
    }

    func displayText(forID engineID: String) -> String {
        allWordRecords().first { $0.text.lowercased() == engineID }?.text ?? engineID
    }

    // MARK: Pool building (Engine bridge)

    /// The profile's session pool: one `WordSnapshot` per active word, joining
    /// any existing progress record. A word never introduced to this profile is
    /// treated as `.new` without needing a `WordProgressRecord` yet.
    func pool(for profile: Profile) -> [WordSnapshot] {
        let words = activeWords(for: profile)
        let progressByText = Dictionary(uniqueKeysWithValues: profile.wordProgress.map { ($0.wordText, $0) })
        return words.map { word in
            progressByText[word.text]?.snapshot ?? WordSnapshot(id: word.text)
        }
    }

    /// Count of due + new words, for the home screen's "N words ready today" line.
    func readyCount(for profile: Profile, now: Date = .now) -> Int {
        pool(for: profile).filter { snap in
            snap.state == .new || (snap.dueDate.map { $0 <= now } ?? true)
        }.count
    }

    // MARK: Recording

    /// Persists a scored word: updates the existing progress record, or creates
    /// one lazily on a word's first-ever scored exposure for this profile.
    func recordScore(profile: Profile, snapshot: WordSnapshot) {
        let text = displayText(forID: snapshot.id)
        if let existing = profile.wordProgress.first(where: { $0.wordText == text }) {
            existing.apply(snapshot)
        } else {
            let wp = WordProgressRecord(wordText: text)
            wp.apply(snapshot)
            wp.profile = profile
            context.insert(wp)
        }
        try? context.save()
    }

    struct SessionStats {
        var mode: String
        var cardsPlayed: Int
        var gotIt: Int
        var almost: Int
        var notYet: Int
        var durationSec: Double
    }

    /// Writes the session record and updates the streak: +1 if last practice was
    /// yesterday, unchanged if already practiced today, reset to 1 otherwise.
    func sessionFinished(profile: Profile, stats: SessionStats, now: Date = .now) {
        let rec = PracticeSession(date: now, mode: stats.mode, cardsPlayed: stats.cardsPlayed,
                                  gotIt: stats.gotIt, almost: stats.almost, notYet: stats.notYet,
                                  durationSec: stats.durationSec)
        rec.profile = profile
        context.insert(rec)
        updateStreak(profile: profile, now: now)
        try? context.save()
    }

    private func updateStreak(profile: Profile, now: Date, calendar: Calendar = .current) {
        defer { profile.lastPracticeDate = now }
        guard let last = profile.lastPracticeDate else { profile.streakDays = 1; return }
        if calendar.isDate(last, inSameDayAs: now) { return }   // already practiced today
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: last),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        profile.streakDays = (days == 1) ? profile.streakDays + 1 : 1
    }

    // MARK: Debug / fresh data

    #if DEBUG
    /// Wipes all persisted data before bootstrap re-seeds it (`-freshData`).
    func wipeStore() {
        for p in allProfiles() { context.delete(p) }
        for w in allWordRecords() { context.delete(w) }
        try? context.save()
    }
    #endif
}
