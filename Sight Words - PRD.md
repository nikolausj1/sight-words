---
title: "Sight Words - PRD"
created: 2026-07-11
modified: 2026-07-11
version: 1.0
author: Claude Fable 5 (claude-fable-5)
tags:
---

# Sight Words - Product Requirements Document

| | |
|---|---|
| **Product** | Sight Words - adaptive flash cards that manage repetition so a kid learns to read words on sight |
| **Platform** | iOS (iPad, household devices) |
| **Status** | v1.0 PRD - draft for Justin's review 2026-07-11 |
| **Companion docs** | `Project Build Guide.md` (accounts, stack, deployment - follow it, do not restate it); `Chat Context.md` (source concept); Math Tutor project at `_Projects/Math Tutor` (shell code to port, see §9) |

## 1. Overview and Vision

**The problem.** Vinny (7) is learning to read and needs daily sight-word practice. Paper flash cards work but can't track which words he misses, can't space repetition intelligently, and depend entirely on a parent running the session. Existing apps bury the words under games, coins, and characters — the decoration competes with the learning.

**The one-liner.** A smart flash-card deck: one large word on screen, someone scores whether he read it, and the app decides when that word comes back — sooner if missed, later if fluent, retired only when he's read it fast across multiple days.

**Why this approach wins.** The scoring judgment stays with a human (parent, or the child self-reporting), which is reliable where speech recognition is not — so the app never falsely tells a 7-year-old he's wrong. The iPad's real advantage over paper is applied where it actually helps: adaptive repetition, consistent pronunciation, and a dashboard that tells the parent exactly which words need work. Optional voice-check exists as a convenience, never as the source of truth.

## 2. Users

- **Vinny, 7** — learning to read; primary learner. Reads best in short, successful bursts; gets discouraged when told he's wrong, so correction must be calm and punishment-free. Uses his iPad Air (see Build Guide device table).
- **Chase** — second child profile from day one, same app, own progress. iPad 10th gen.
- **Justin (dad)** — runs parent-scored sessions, manages word lists (including pasting the teacher's list), reads the dashboard to know what to work on. Accesses the parent area on either kid's iPad.

## 3. Goals and Success Criteria

**Goals:**

- Five focused minutes a day moves words from "needs help" to automatic recognition.
- The parent always knows which words to work on without keeping notes.
- The child experiences mostly success: sessions feel doable, never punishing.
- Works with whatever list his school sends home, not just the built-in lists.

**Success criteria (testable):**

1. A word scored **incorrect** reappears within 2–4 cards of the same session, every time.
2. A word is marked **Mastered** only after a first-try fast-correct read in sessions on **3 or more distinct days** — never from a single session.
3. A default 12-card session completes in about 5 minutes at a normal pace.
4. Session composition honors ~70% familiar / 20% developing / 10% new whenever the word pool allows (max 2 new words per session).
5. Scheduler engine smoke test: 50+ assertions green via the Build Guide's no-Xcode test recipe.
6. Fully offline: airplane mode changes nothing.
7. The dashboard answers "which words does he need help with?" in one glance (a named "Needs help" group, worst first).

**The one-sentence test:** A week after "because" first appears, Vinny reads it cold in under two seconds, and the dashboard shows it moved from Needs help to Mastered.

## 4. Scope

**In scope (v1):**

- Splash, onboarding, multi-profile system, and parent area — ported from Multiplication Adventure (§7, §9)
- **Practice Together** (parent-scored: Got it / Almost / Not yet)
- **On My Own** (self-practice: child taps Show answer, self-scores)
- **Tricky Words** (session built only from missed/slow words)
- Adaptive repetition engine + word state machine (§6.9)
- Preloaded Dolch lists (pre-primer → 3rd grade, 220 words) with per-profile list activation, plus custom "teacher's list" entry
- New-word introduction flow and reteach flow
- Word audio: AVSpeechSynthesizer first (placeholder-first), then bundled pre-generated ElevenLabs clips for the 220 Dolch words; AVSpeech remains the fallback for custom words
- **Voice-check** (optional, OFF by default, per-profile toggle): on-device speech recognition assists self-practice; never the source of truth
- Parent dashboard with per-word status

**Out of scope (non-goals):**

- **No gamification** — no coins, characters, hearts, leaderboards, or animations during practice, by decision: the word is the focus and wrong answers must cost nothing. (A brief low-key celebration between card groups is the ceiling.)
- **No speech recognition as the source of truth**, by decision: misheard kids' speech destroys trust. Voice-check only ever assists and is always overridable.
- No accounts, cloud sync, or backend — on-device only, per Build Guide preference.
- No App Store release — household Ad Hoc installs only.
- No phonics curriculum — this app builds sight recognition, it does not teach decoding.
- No portrait or iPhone support — landscape iPad only, matching Multiplication Adventure.

**Deferred (v2+ candidates):**

- Quick-check assessment mode (short no-hints test) — v2
- Mastery testing in sentence/phrase context and mixed with look-alike words — v2
- Per-word phonics reteach tips ("said: the middle 'ai' is the part to remember") — v2; v1 reteach is the generic flow in §6.6
- ElevenLabs audio for sentences (v1 sentences use AVSpeech) — v2, pending cost check
- Voice-check in Practice Together mode — v2 if ever; the parent is already the judge there

## 5. Product Principles

1. **The word is the focus.** Nothing moves or decorates the screen while he's reading.
2. **Never punish.** No buzzers, no "Wrong", no red X, nothing lost. Correction is calm: say the word, have him repeat it, bring it back soon.
3. **Short and successful.** ~5 minutes, 70/20/10 mix. A session that feels like repeated failure is a scheduling bug.
4. **Human judgment beats automation.** Parent scoring > self-scoring > voice-check, in that order of authority.
5. **Fluency means fast.** The goal is automatic recognition, so response time matters — but it is measured invisibly, never shown as a timer.

## 6. Functional Requirements

Navigation matches Multiplication Adventure: no NavigationStack; a single hub screen with everything else as `fullScreenCover`, sheet, or in-hierarchy overlay in a ZStack.

### 6.1 Screen A — Splash

Port of Math Tutor's `SplashView`: full-bleed `Image("splash")` over black, shown only if `Art.exists("splash")`, auto-dismisses after 1.6s with a 0.6s ease-out fade, suppressed under demo/screenshot launch args. Until splash art exists, no splash shows (placeholder-first).

### 6.2 Screen B — Onboarding (first run per profile)

Port of Math Tutor's 5-step flow and style: night-sky gradient backdrop, capsule progress bar, back chevron, ChunkyKey buttons, asymmetric slide transitions.

1. **Welcome** — "Ready to become a word wizard?" subtitle "Big words. Short practice. You've got this." Green "Let's go!" button. No keyboard on the first beat.
2. **Name** — "What's your name, reader?" — centered text field, 12-char cap, dark-plate style.
3. **Level** — "What grade are you in?" — chunky buttons: Pre-K, K, 1, 2, 3+. Maps to active Dolch lists cumulatively: Pre-K → pre-primer; K → + primer; 1 → + first grade; 2 → + second grade; 3+ → + third grade. (Parent can change lists later; the 10%-new cap means a big pool never floods a session.)
4. **Avatar** — "Pick your reader!" — ported `AvatarCarousel`.
5. **Ready** — big avatar badge, "You're ready, {name}!", accent "Start reading!" button. Finishing writes name/level/avatar, sets `onboarded = true`, and plays the avatar-flight animation to the home screen's profile chip.

Profiles created from the parent area skip onboarding (`onboarded = true` at creation), same as Math Tutor.

### 6.3 Screen C — Home (hub)

- Top-left: profile chip (avatar + name) → tap opens Screen I (kid profile overlay).
- Top-right: gear (44×44 dark-plate) → Screen J (parent area).
- Center: three large ChunkyKey mode buttons:
  - **Practice Together** (primary blue) → Screen D
  - **On My Own** (correct green) → Screen E
  - **Tricky Words** (accent gold) → Screen D or E depending on last-used mode, deck = trouble words only
- Under the buttons, one quiet line: "12 words ready today" (count of due + new words).
- **Empty state** (no active lists / zero words): buttons disabled with the message "Ask a grown-up to pick your word lists" and the gear gently highlighted.
- **Nothing-due state:** buttons stay enabled (session builds from review words); line reads "All caught up — want to practice anyway?"
- **Tricky Words empty:** that button shows "No tricky words right now!" and is disabled.

### 6.4 Screen D — Practice Together (parent-scored session)

The core loop. Deliberately plain screen:

- Top: "Word 7 of 12" + a thin segmented progress strip. Small darkPlate exit (×) — exiting mid-session saves all results scored so far and discards the rest.
- Center: the word, SF Rounded heavy, as large as fits (a 12-char word like "together" must still be huge).
- Bottom: three large ChunkyKey scoring buttons, always visible, parent-facing:
  - **Got it** (correct green, checkmark)
  - **Almost** (accent gold, circle)
  - **Not yet** (gentle neutral — deliberately not red, per Principle 2)
- Side controls (darkPlate, small): 🔊 speaker (plays the word's audio) and "In a sentence" (reveals the word's sentence below the word; tap again to hide).
- The word stays on screen until scored. Response time is measured silently from word-appear to score-tap.

**On Got it:** app says "Correct. {word}." and advances after ~0.5s. No confetti.
**On Almost:** app says the word, advances; word is reinserted 5–8 cards later.
**On Not yet:** app says "This word is {word}. Say {word}." — 3-second pause for him to repeat (no detection, just a beat) — then "Good. We'll see it again soon." Word reinserted 2–4 cards later.
**Second Not yet on the same word in one session:** reteach flow (§6.6) before continuing.

Every 5 cards, a one-beat low-key acknowledgment (e.g. the progress strip pulses + "Nice work" voice line) — never a screen takeover.

**New words** in the deck open with the intro flow (§6.5) instead of a bare card.

**Error states:** if bundled audio is missing for a word, AVSpeech speaks it (silent fallback, same as Math Tutor's missing-SFX no-op). If TTS itself fails, the session continues without audio and the speaker button is dimmed.

### 6.5 New-word introduction (inline, within a session)

First time a word is ever shown to this profile:

1. Word appears with a soft "New word" tag; app says the word.
2. "Say {word}." — pause for him to repeat.
3. Sentence appears below and is read aloud.
4. Card flips into a normal practice card later in the same session (counts as its first scored exposure).

### 6.6 Reteach flow (inline interstitial)

Triggered by a second miss of the same word in one session (either mode):

1. App says the word; word shown large.
2. "Say {word}" — pause.
3. Letters displayed spaced-out (b e c a u s e) while the app says it once more.
4. Sentence shown and read aloud.
5. "Let's see it again soon" → continue; word reinserted 2–4 cards later. No limit — if missed again, reteach repeats, and excess repeats simply roll into tomorrow's deck (a third miss ends its appearances for this session).

### 6.7 Screen E — On My Own (self-practice session)

Same layout and rules as Screen D, except scoring:

- Bottom center: one big ChunkyKey **Show answer** button.
- On tap: app says the word; two buttons replace it: **I got it** (green) / **Not yet** (gentle). Honest self-report; response time = word-appear → Show-answer tap.
- With **voice-check ON** (§6.8), listening starts automatically and Show answer remains available the whole time as the manual path.

### 6.8 Voice-check (optional overlay on Screen E)

Per-profile toggle in parent settings, **OFF by default**. Uses `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true` — nothing leaves the iPad. Mic + speech permissions requested on first enable, from the parent area (not mid-session, not from the child).

Behavior per card:

- A small pulsing mic indicator (darkPlate) shows it's listening. It waits for him to start speaking; listening window ~6s of silence before it gently prompts: "Give it a try, or tap Show answer."
- **Confident match** (transcript token equals the target, case-insensitive, or is in the target's homophone set — e.g. to/two/too, there/their, for/four, know/no, right/write, by/buy, one/won, ate/eight, blue/blew, red/read, be/bee, see/sea, new/knew, so/sew, our/hour, its/it's, would/wood, hi/high): scored correct — "Correct. {word}."
- **Low confidence or near-miss:** "I think you said '{heard}'. Is that right?" → **Yes** (scored correct) / **Try again** (relisten). Never auto-scored wrong.
- **No match after 2 tries or no speech:** falls back to Show answer + self-score. Recognition failure is never recorded as an incorrect answer.
- Manual buttons always override anything voice-check concluded.

**Permission denied:** the settings toggle shows "Microphone access is off — enable it in the Settings app" with a deep link; sessions behave as if voice-check were off. **Recognizer unavailable** (unsupported device/locale): toggle disabled with a one-line explanation.

### 6.9 Word state machine and scheduler (the engine)

Lives in `Sources/Engine/` as pure Swift, UI-free, smoke-testable.

**States:** `new → learning → developing → fluent → mastered`, plus a `needsReview` flag.

**Response-time bands** (word-appear → score/reveal): fast < 2s; developing 2–5s; slow > 5s.

**Within-session queue rules:**

| Result | Reinsertion |
|---|---|
| Got it, fast | Done for the session |
| Got it, slow (or any Almost) | 5–8 cards later |
| Not yet | 2–4 cards later |
| Not yet ×2 (same session) | Reteach (§6.6), then 2–4 cards later |

**State transitions (end of each scored exposure):**

| Case | Effect |
|---|---|
| `new` word completes intro + first scored exposure | → `learning` |
| `learning`/`developing`, correct + fast, first try of the session | one "fluent day" credited (max one per calendar day); → `fluent` |
| correct but slow, or Almost | → `developing` |
| Not yet (any state) | → `learning`, `needsReview = true`; fluent-day count resets |
| `fluent` with fluent-day credits on ≥3 distinct days | → `mastered` |
| `fluent`/`mastered` word missed | → `developing`, `needsReview = true`, fluent-day count resets |

**Cross-session due dates:** learning → due same/next day; developing → next day; fluent → +3 days; mastered → +7 days (light maintenance, so mastered words still resurface occasionally).

**Session builder:** default 12 cards (10–15 valid) = ~70% familiar (due `developing`/`fluent`/`mastered`), ~20% `learning`/`needsReview`, ~10% `new` (hard cap 2 new). Short buckets backfill from the next-most-familiar bucket. If the whole pool is smaller than the session size, the session is just the pool. Tricky Words sessions draw only `needsReview` + `learning` words, no new words.

### 6.10 Screen F — Session complete

Word-count summary in the child's voice: "You read 12 words!" — plus a list of any words to watch ("We'll practice these again: because, where"), one warm celebrate-spring animation (Theme celebrate motion), and Done → home. No stars, no scores, no grades on the child-facing screen.

### 6.11 Screen I — Kid profile overlay

Simplified port of Math Tutor's trophy room (same dark-card style over a scrim): tappable avatar (opens the carousel), inline-editable name (12-char cap), and two stat tiles only: **day streak** and **words I know** (fluent + mastered count). No guardian gallery, no XP — nothing to grind.

### 6.12 Screen J — Parent area

Port of Math Tutor's `ParentAreaView` structure: gear → fullScreenCover; dimmed scrim; centered light card, two columns. **Year-of-birth gate** (adult 18–100, NumberPadView) wraps management and destructive actions only; viewing the dashboard is ungated.

**Left column (cards):**

- **Players** — profile rows (avatar, name, active check, Switch, … menu: Rename / Reset progress / Delete — never delete the last profile). Add player (gated) creates a profile with `onboarded = true` via a mini form (name, avatar, level).
- **Word lists** (gated, per active profile) — toggles for the five Dolch lists with word counts; **Custom list** section: add words via a text field (one word) or paste-many (whitespace/comma-separated, lowercased, deduped against everything already present — a custom word that duplicates a Dolch word is rejected with "already in {list}"). Each custom word gets an optional parent-entered sentence; without one, the word simply has no sentence card. Deleting a custom word removes its progress. Deactivating a list hides its words from sessions but **preserves progress** for reactivation.
- **Settings** (gated) — per profile: Sound effects (default on), **Voice-check** (default off; triggers permission flow §6.8), session length (10 / 12 / 15, default 12).
- **How it works** — collapsible explainer of states, the 70/20/10 mix, and what Mastered means.

**Right column:** identity header (active child avatar, name, streak, words-known) + the dashboard:

- **Needs help** — `needsReview` + `learning` words, most-missed first, each with accuracy and last-practiced.
- **Almost fluent** — `developing` + `fluent` words with fluent-day progress ("2 of 3 days").
- **Mastered** — collapsed count, expandable.
- Tapping any word: detail popover — state, accuracy, average response time, last 5 results, times seen, first seen. Empty dashboard state (new profile): "Start the first session to see progress here."

### 6.13 Edge cases

| Case | Behavior |
|---|---|
| App backgrounded/killed mid-session | Scored cards persist immediately; unscored remainder discarded; home shows normal state |
| Same word in Dolch + pasted custom list | Custom add rejected; one Word row per unique text, ever |
| Both kids share one iPad | Profiles are per-install; switching profiles in the parent area switches all state |
| Day rolls over mid-session | Fluent-day credits use the session's start date |
| Parent taps score before child reads (accidental) | No undo in v1 — one mis-scored card self-corrects via scheduling; not worth UI |
| All active words mastered | Sessions become maintenance reviews of due mastered words; dashboard suggests activating the next list |
| Word too long for the type size | Font autoshrinks to fit width; never wraps |
| Voice-check hears a sibling/background talk | Confidence gate + confirmation flow absorbs it; worst case the child taps Try again or Show answer |

## 7. Visual and Design Spec

**Match Multiplication Adventure.** The shell (splash, onboarding, profile, parent area) should be indistinguishable in style from the Math Tutor app; the two apps are siblings. Port the token layer and components rather than restyling (file list in §9).

- **Palette (Theme.swift, verbatim):** bg near-white (0.97,0.98,1.0); surface white; ink (0.12,0.14,0.22); inkSoft (0.42,0.45,0.55); primary friendly blue (0.30,0.45,0.98); accent warm gold (1.0,0.72,0.20); correct green (0.20,0.78,0.50); gentle neutral (0.62,0.66,0.78). Onboarding backdrop gradient (0.11,0.12,0.30)→(0.05,0.05,0.14).
- **Typography:** SF Rounded everywhere. The practice word uses the `display`/heavy face at the largest size that fits — the word is the hero, exactly as the numeral is in Math Tutor.
- **Metrics/motion:** corner 22 / cornerSmall 14 / gap 16 / pad 24; snappy spring in-loop, celebrate spring at session end; PopButtonStyle press behavior; respect Reduce Motion.
- **Components:** ChunkyKeyStyle for all big kid-facing buttons; darkPlate for controls over content; cardSurface (flat, hairline border, no shadow) for parent-area cards; ModalCloseButton; AvatarBadge/AvatarCarousel; NumberPadView for the gate.
- **Tone:** calm, warm, spare. The practice screen looks closer to a beautifully-set flash card than to a game.
- **Art is placeholder-first** (Build Guide): the app must feel complete with SF-Symbol avatars, no splash art, and no custom sounds. Splash art, avatar art, and SFX are generated later into `_review/` for Justin to pick (3–4 candidates each), wired in via the `Art.exists()` pattern with zero view changes.
- **Sound/haptics:** port `Feedback.fire(event)` — events for keyTap, correct, almost, reteach, sessionComplete; `.ambient` session; missing sound files silently no-op. Word/sentence speech: AVSpeechSynthesizer (child-appropriate rate ~0.45) until ElevenLabs clips land; clips are bundled `m4a`, looked up by word, AVSpeech fallback (§4).

## 8. Data Model

SwiftData, one ModelContainer, cascade deletes from Profile (Math Tutor pattern). A `LearningService`-style class owns all mutations, bootstrap, and migration heals.

- **Profile** — `id: UUID`, `name`, `avatarSymbol`, `level` (PreK/K/1/2/3), `onboarded: Bool`, `isActive: Bool` (exactly one active), `createdAt`, `soundOn = true`, `voiceCheckOn = false`, `sessionSize = 12`, `streakDays`, `lastPracticeDate`. Relationships: `wordProgress`, `sessions` (cascade).
- **Word** — `id`, `text` (lowercased, globally unique), `listID` (`dolchPrePrimer | dolchPrimer | dolchFirst | dolchSecond | dolchThird | custom`), `sentence: String?`, `isCustom: Bool`. Dolch words seeded from bundled JSON at bootstrap; custom words created in the parent area. Invariant: one Word per unique `text`.
- **WordProgress** (per profile × word) — `state` (new/learning/developing/fluent/mastered), `needsReview: Bool`, `timesSeen`, `timesCorrect`, `timesMissed`, `lastResult`, `lastSeenAt`, `dueDate`, `avgResponseMs`, `recentResults` (last 5), `fluentDayCount`, `lastFluentDay`. Invariants: `fluentDayCount` increments at most once per calendar day and resets on any miss; `state == .mastered` requires `fluentDayCount >= 3`.
- **SessionRecord** — `date`, `mode` (parent/solo/tricky), `cardsPlayed`, `gotIt`, `almost`, `notYet`, `durationSec`, profile relationship.
- **Per-profile active lists** — `activeListIDs: [String]` on Profile.

**Seed content:** `dolch-words.json` bundled in the app: 220 entries `{ "text", "list", "sentence" }`. Claude generates one kid-friendly example sentence per word (≤8 words, simpler than the target word where possible) during Phase 1; Justin reviews/edits the JSON directly in the repo — it is the single source of truth for built-in content. Homophone sets for voice-check live in a small `homophones.json` alongside it.

## 9. Tech Stack and Architecture

Per the Build Guide iOS section. Project-specific facts only:

- **Repo:** `nikolausj1/sight-words` · **Bundle ID:** `com.levelup.sightwords` · **Display name:** "Sight Words" (working title — open question §12).
- **project.yml:** copy Math Tutor's conventions — XcodeGen, iOS 17+, `TARGETED_DEVICE_FAMILY: "2"`, landscape-only + `UIRequiresFullScreen`, generated Info.plist, `ITSAppUsesNonExemptEncryption: NO`, team `6A4J2GTB6F`. Add `NSMicrophoneUsageDescription` + `NSSpeechRecognitionUsageDescription` (voice-check).
- **Structure:** `Sources/Engine/` (word state machine, scheduler, session builder — pure Foundation, no UI imports) and `Sources/App/` (SwiftUI). Engine is exercised by `Tests/SmokeTest.swift` via the Build Guide recipe.
- **Ported from Math Tutor at kickoff (copy files, separate repos — copy, don't reference):** `Theme/Theme.swift`, `Theme/WorldComponents.swift` (trim to ChunkyKeyStyle, ModalCloseButton, darkPlate, cardSurface, noise texture), `Theme/Feedback.swift`, `Views/AvatarBadge.swift`, `Views/NumberPadView.swift`, plus the `Art.exists()` helper; splash/onboarding/parent-area views are re-implemented in the same style using `RootView.swift`, `Onboarding/OnboardingView.swift`, and `ParentAreaView.swift` as direct references.
- **Frameworks:** SwiftUI, SwiftData, AVFoundation (AVSpeechSynthesizer + clip playback), Speech (`SFSpeechRecognizer`, on-device only). No third-party dependencies.
- **Rejected:** speech-recognition-first scoring (trust, per Chat Context); web app (needs offline + mic + kid-friendly full screen); cross-app shared framework with Math Tutor (overhead not worth it for a household app — plain file copies).

## 10. Build Phases

1. **Phase 0 — Kickoff.** Build Guide checklist: repo, `_inbox/`/`_review/`, gitignores, XcodeGen scaffold, port the §9 theme/component files. **Exit:** empty themed app builds and launches on the iPad sim, screenshot.
2. **Phase 1 — Engine + content.** Word/WordProgress/Profile/SessionRecord models; `dolch-words.json` (all 220 words + sentences) + `homophones.json`; state machine, scheduler, session builder. **Exit:** smoke test 50+ assertions green (reinsertion windows, 70/20/10 mix, 3-day mastery, miss-resets).
3. **Phase 2 — Practice Together.** Screens C (minimal) + D + F, new-word intro, reteach, AVSpeech audio, persistence of results. **Exit:** full parent-scored session on sim, screenshots of every state (incl. empty/nothing-due home).
4. **Phase 3 — On My Own.** Screen E, Show-answer flow, Tricky Words mode. **Exit:** sim-verified solo session + tricky session.
5. **Phase 4 — Shell.** Splash hook, onboarding (B), profiles + kid overlay (I), parent area (J: gate, players, word lists incl. paste-a-list, settings, dashboard). **Exit:** first-run → onboarding → session → dashboard walkthrough on sim, screenshots for Justin.
6. **Phase 5 — Voice-check.** SFSpeechRecognizer overlay per §6.8 behind the settings toggle. Core app fully usable with it off — this phase may slip past day one without hurting v1. **Exit:** sim-verified UI states; recognition itself validated on-device later (mic doesn't work meaningfully in sim).
7. **Phase 6 — Audio pass.** Ask Justin, then batch-generate ~220 ElevenLabs word clips (+ feedback phrases) into `_review/`, bundle approved set, wire lookup-with-fallback. **Exit:** spot-check playback on sim; custom word falls back to AVSpeech.
8. **Phase 7 — Polish + deploy.** Full sim-verify screenshot pass → **Justin approves** → Ad Hoc export, deploy to Vinny's and Chase's iPads (Build Guide Recipe B; register UDIDs for the new bundle ID first). **Exit:** app launches on both iPads; first live session with Vinny.

## 11. Acceptance Criteria

- [ ] First run shows onboarding; completing it lands on home with the chosen name/avatar; second launch skips straight to home.
- [ ] A 12-card Practice Together session works end to end; each scoring button behaves per §6.4 (including the Not-yet repeat-after-me beat).
- [ ] A word scored Not yet reappears within 2–4 cards; a second miss triggers the reteach flow.
- [ ] A word reaches Mastered only after fast-correct first-try reads on 3 distinct days (verifiable via engine test and dashboard).
- [ ] On My Own works without a parent; voice-check (when enabled) auto-scores confident matches, asks "I think you said…" on low confidence, and never auto-marks wrong.
- [ ] Tricky Words builds sessions only from missed/slow words and disables itself when empty.
- [ ] Pasting a teacher's list creates custom words, deduped, usable in the next session; a duplicate of a Dolch word is rejected with the list named.
- [ ] Dashboard shows Needs help / Almost fluent / Mastered groups with per-word detail popovers; year-of-birth gate blocks management actions but not the dashboard.
- [ ] Two profiles hold fully independent progress; switching in the parent area swaps everything; last profile cannot be deleted.
- [ ] Every word is spoken: bundled clip if present, AVSpeech otherwise (test with a custom word).
- [ ] Airplane mode: everything above still passes (voice-check uses on-device recognition or degrades gracefully).
- [ ] Whole app matches the Multiplication Adventure look (side-by-side screenshot check of splash, onboarding, parent area).

## 12. Risks and Open Questions

**Risks:**

- **ElevenLabs batch cost/time (~220+ clips).** Mitigation: AVSpeech already ships as the working voice; ask Justin before generating; batch is one-time and bundled.
- **Ad Hoc provisioning for a new bundle ID on the kids' iPads.** Mitigation: register both UDIDs for `com.levelup.sightwords` before Phase 7 (Build Guide Recipe B; error signature documented there).
- **Speech recognition mishears a quiet 7-year-old.** Mitigation: off by default, confidence-gated confirmation, homophone sets, manual override always present, never records a wrong answer on recognition failure. Needs a real-device test with Vinny — the simulator cannot validate it.
- **One-day scope.** Mitigation: Phases 0–4 are the day-one target; Phases 5–6 are explicitly slippable without hurting the core product.

**Open questions (non-blocking — flag, don't decide):**

- App display name: "Sight Words" is the working title; Justin may want something in the Adventure family. Placeholder rule: ship as "Sight Words".
- Sentence audio: AVSpeech in v1; ElevenLabs upgrade is a v2 decision after word-clip cost is known.
- Whether Chase's profile starts at a different level than Vinny's (parent can set it either way at creation; default K).
