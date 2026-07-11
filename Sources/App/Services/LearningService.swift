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

    /// Count of words eligible for a Tricky Words session (needsReview or
    /// learning) — mirrors `SessionBuilder`'s `.tricky` candidate filter so the
    /// home screen's disabled state (§6.3) matches what the deck would build.
    func countTricky(for profile: Profile) -> Int {
        pool(for: profile).filter { $0.needsReview || $0.state == .learning }.count
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
            wp.firstSeenAt = snapshot.lastSeenAt ?? .now
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

    /// Persists which control style (parent-scored vs solo) a session used, so a
    /// later Tricky Words session (§6.3) can mirror the last-used style.
    func recordControlStyleUsed(profile: Profile, style: String) {
        profile.lastUsedControlStyle = style
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

    // MARK: Level -> active Dolch lists (onboarding §6.2, parent mini-form)

    /// Cumulative per PRD §6.2: Pre-K -> pre-primer; K -> +primer; 1 -> +first;
    /// 2 -> +second; 3+ -> +third. `level` matches `Profile.level` ("PreK"|"K"|"1"|"2"|"3").
    static func activeListIDs(forLevel level: String) -> [String] {
        switch level {
        case "PreK": return ["dolchPrePrimer"]
        case "K":    return ["dolchPrePrimer", "dolchPrimer"]
        case "1":    return ["dolchPrePrimer", "dolchPrimer", "dolchFirst"]
        case "2":    return ["dolchPrePrimer", "dolchPrimer", "dolchFirst", "dolchSecond"]
        default:     return ["dolchPrePrimer", "dolchPrimer", "dolchFirst", "dolchSecond", "dolchThird"]
        }
    }

    /// Display names for the five Dolch lists + custom, used by the parent
    /// area's toggles and by the dedupe-rejection message (§6.12/§6.13).
    static let dolchListIDs = ["dolchPrePrimer", "dolchPrimer", "dolchFirst", "dolchSecond", "dolchThird"]

    static func listDisplayName(_ listID: String) -> String {
        switch listID {
        case "dolchPrePrimer": return "Pre-Primer"
        case "dolchPrimer":    return "Primer"
        case "dolchFirst":     return "First Grade"
        case "dolchSecond":    return "Second Grade"
        case "dolchThird":     return "Third Grade"
        case "custom":         return "Custom list"
        default:               return listID
        }
    }

    /// Word counts per list, for the toggles' "(40 words)" captions.
    func wordCount(listID: String) -> Int { allWordRecords().filter { $0.listID == listID }.count }

    // MARK: Profile management (parent area §6.12)

    /// Deactivates every other profile and activates this one. Switching swaps
    /// all state — the home screen, dashboard, and any in-flight session all
    /// key off `isActive` (§6.13: "switching profiles ... switches all state").
    func switchTo(_ profile: Profile) {
        for p in allProfiles() { p.isActive = (p.id == profile.id) }
        try? context.save()
    }

    /// Parent-created profiles skip onboarding (`onboarded = true`), same as
    /// Math Tutor. Does not switch to the new profile — the parent stays on
    /// whichever child they were managing.
    @discardableResult
    func createProfile(name: String, avatar: String, level: String = "K") -> Profile {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let p = Profile(name: trimmed.isEmpty ? "Player" : trimmed, avatarSymbol: avatar, level: level,
                        onboarded: true, isActive: false,
                        activeListIDs: Self.activeListIDs(forLevel: level))
        context.insert(p)
        try? context.save()
        return p
    }

    func rename(_ profile: Profile, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        profile.name = String(trimmed.prefix(12))
        try? context.save()
    }

    /// Never deletes the last remaining profile (§6.12/§6.13) — callers should
    /// also hide the destructive action in that case, but the service enforces
    /// it regardless.
    func delete(_ profile: Profile) {
        let all = allProfiles()
        guard all.count > 1 else { return }
        let wasActive = profile.isActive
        context.delete(profile)
        if wasActive, let next = all.first(where: { $0.id != profile.id }) {
            next.isActive = true
        }
        try? context.save()
    }

    /// Returns the profile to brand-new progress: clears word progress and
    /// session history, resets streak, but keeps identity (name/avatar/level).
    func resetProgress(_ profile: Profile) {
        for wp in profile.wordProgress { context.delete(wp) }
        for s in profile.sessions { context.delete(s) }
        profile.streakDays = 0
        profile.lastPracticeDate = nil
        try? context.save()
    }

    /// "Start over" (§6.12): wipes identity AND progress, sends the profile back
    /// through onboarding. The caller posts `.startOverRequested` afterward so
    /// `RootView` re-arms the splash + onboarding gate.
    func startOver(_ profile: Profile) {
        resetProgress(profile)
        profile.name = "Player"
        profile.avatarSymbol = "avatar1"
        profile.level = "K"
        profile.activeListIDs = []
        profile.onboarded = false
        try? context.save()
    }

    // MARK: Custom words (§6.12/§6.13)

    enum CustomWordError: Equatable {
        case duplicate(listName: String)
        case empty
    }

    /// Adds one custom word, deduped case-insensitively against every word ever
    /// created (Dolch or custom) — "one Word row per unique text, ever" (§6.13).
    /// Ensures "custom" is active for this profile so the word is usable right away.
    @discardableResult
    func addCustomWord(text: String, sentence: String?, for profile: Profile) -> CustomWordError? {
        let normalized = Self.normalize(text)
        guard !normalized.trimmingCharacters(in: .whitespaces).isEmpty else { return .empty }
        if let existing = allWordRecords().first(where: { $0.text.lowercased() == normalized.lowercased() }) {
            return .duplicate(listName: Self.listDisplayName(existing.listID))
        }
        let trimmedSentence = sentence?.trimmingCharacters(in: .whitespacesAndNewlines)
        let w = WordRecord(text: normalized, listID: "custom",
                           sentence: (trimmedSentence?.isEmpty ?? true) ? nil : trimmedSentence,
                           isCustom: true)
        context.insert(w)
        if !profile.activeListIDs.contains("custom") { profile.activeListIDs.append("custom") }
        try? context.save()
        return nil
    }

    /// Paste-a-list (§6.12): whitespace/comma-separated, lowercased, deduped.
    /// Returns how many were added and which were rejected (with the list they
    /// already live in), so the UI can report "already in Pre-Primer" per §6.13.
    func pasteWords(_ raw: String, for profile: Profile) -> (added: Int, rejected: [(word: String, listName: String)]) {
        let pieces = raw
            .split(whereSeparator: { $0 == "," || $0.isNewline || $0.isWhitespace })
            .map { Self.normalize(String($0)) }
            .filter { !$0.isEmpty }
        var seenThisPaste = Set<String>()
        var rejected: [(word: String, listName: String)] = []
        var added = 0
        var existingByLower = Dictionary(uniqueKeysWithValues: allWordRecords().map { ($0.text.lowercased(), $0) })
        var touchedCustom = false
        for word in pieces {
            let key = word.lowercased()
            if seenThisPaste.contains(key) { continue }   // dedupe within the paste itself
            seenThisPaste.insert(key)
            if let existing = existingByLower[key] {
                rejected.append((word: word, listName: Self.listDisplayName(existing.listID)))
                continue
            }
            let w = WordRecord(text: word, listID: "custom", sentence: nil, isCustom: true)
            context.insert(w)
            existingByLower[key] = w
            added += 1
            touchedCustom = true
        }
        if touchedCustom, !profile.activeListIDs.contains("custom") {
            profile.activeListIDs.append("custom")
        }
        try? context.save()
        return (added, rejected)
    }

    func updateCustomWordSentence(_ word: WordRecord, sentence: String?) {
        let trimmed = sentence?.trimmingCharacters(in: .whitespacesAndNewlines)
        word.sentence = (trimmed?.isEmpty ?? true) ? nil : trimmed
        try? context.save()
    }

    /// Deletes a custom word and every profile's progress on it (§6.12: "Deleting
    /// a custom word removes its progress"). Custom words are global (same
    /// uniqueness invariant as Dolch words), so progress is cleared everywhere,
    /// not just for the profile that happened to open the editor.
    func deleteCustomWord(_ word: WordRecord) {
        guard word.isCustom else { return }
        for profile in allProfiles() {
            for wp in profile.wordProgress where wp.wordText == word.text {
                context.delete(wp)
            }
        }
        context.delete(word)
        try? context.save()
    }

    func customWords() -> [WordRecord] {
        allWordRecords().filter { $0.isCustom }.sorted { $0.text.lowercased() < $1.text.lowercased() }
    }

    // MARK: Dashboard (§6.12)

    /// "Words I know" — fluent + mastered count, used by both the kid profile
    /// overlay's stat tile and the parent area's identity header.
    func wordsKnownCount(for profile: Profile) -> Int {
        profile.wordProgress.filter { $0.stateRaw == WordState.fluent.rawValue
                                    || $0.stateRaw == WordState.mastered.rawValue }.count
    }

    /// Every word this profile has ever been scored on (i.e. has a progress
    /// record) — new/never-introduced words don't show up in the dashboard.
    func introducedProgress(for profile: Profile) -> [WordProgressRecord] {
        profile.wordProgress.filter { $0.timesSeen > 0 }
    }

    // MARK: Debug / fresh data

    #if DEBUG
    /// Wipes all persisted data before bootstrap re-seeds it (`-freshData`).
    func wipeStore() {
        for p in allProfiles() { context.delete(p) }
        for w in allWordRecords() { context.delete(w) }
        try? context.save()
    }

    /// `-demoTricky` needs real content: if this profile has no tricky
    /// candidates yet, marks a couple of its active words as missed/learning so
    /// the Tricky Words screen has something to show. No-ops once any exist.
    func seedTrickyWordsIfNeeded(for profile: Profile) {
        guard countTricky(for: profile) == 0 else { return }
        for word in activeWords(for: profile).prefix(2) {
            let wp: WordProgressRecord
            if let existing = profile.wordProgress.first(where: { $0.wordText == word.text }) {
                wp = existing
            } else {
                wp = WordProgressRecord(wordText: word.text)
                wp.profile = profile
                context.insert(wp)
            }
            wp.stateRaw = WordState.learning.rawValue
            wp.needsReview = true
            wp.timesSeen = max(wp.timesSeen, 1)
            wp.timesMissed = max(wp.timesMissed, 1)
        }
        try? context.save()
    }

    /// `-demoDashboard` needs a believable dashboard: a few words in each of the
    /// Needs help / Almost fluent / Mastered groups. No-ops once this profile
    /// already has any progress at all, so it never overwrites real data.
    func seedDashboardDemoData(for profile: Profile) {
        guard profile.wordProgress.isEmpty else { return }
        let words = activeWords(for: profile)
        guard !words.isEmpty else { return }
        var pool = words[...]
        let now = Date.now
        let calendar = Calendar.current

        func next(_ n: Int) -> [WordRecord] {
            let taken = Array(pool.prefix(n))
            pool = pool.dropFirst(n)
            return taken
        }
        func makeRecord(_ word: WordRecord, state: WordState, needsReview: Bool, seen: Int,
                        correct: Int, missed: Int, recent: [String], fluentDays: Int,
                        avgMs: Int, daysAgo: Int) {
            let wp = WordProgressRecord(wordText: word.text)
            wp.stateRaw = state.rawValue
            wp.needsReview = needsReview
            wp.timesSeen = seen
            wp.timesCorrect = correct
            wp.timesMissed = missed
            wp.recentResults = recent
            wp.fluentDayCount = fluentDays
            wp.avgResponseMs = avgMs
            let seenDate = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
            wp.lastSeenAt = seenDate
            wp.firstSeenAt = calendar.date(byAdding: .day, value: -(daysAgo + seen), to: now) ?? seenDate
            wp.lastResult = recent.last
            wp.profile = profile
            context.insert(wp)
        }

        // Needs help: needsReview/learning, worst-first via timesMissed.
        for (i, w) in next(4).enumerated() {
            makeRecord(w, state: .learning, needsReview: true, seen: 5, correct: 2, missed: 3 - min(i, 2),
                      recent: ["gotIt", "notYet", "notYet", "almost", "notYet"],
                      fluentDays: 0, avgMs: 3200, daysAgo: i)
        }
        // Almost fluent: developing/fluent, with partial fluent-day progress.
        for (i, w) in next(4).enumerated() {
            let state: WordState = i % 2 == 0 ? .fluent : .developing
            makeRecord(w, state: state, needsReview: false, seen: 6, correct: 6, missed: 0,
                      recent: ["gotIt", "gotIt", "gotIt", "gotIt", "gotIt"],
                      fluentDays: state == .fluent ? (i % 2 == 0 ? 2 : 1) : 0, avgMs: 1400, daysAgo: i + 1)
        }
        // Mastered.
        for w in next(3) {
            makeRecord(w, state: .mastered, needsReview: false, seen: 9, correct: 9, missed: 0,
                      recent: ["gotIt", "gotIt", "gotIt", "gotIt", "gotIt"],
                      fluentDays: 3, avgMs: 1100, daysAgo: 5)
        }
        profile.streakDays = max(profile.streakDays, 3)
        profile.lastPracticeDate = now
        try? context.save()
    }
    #endif
}
