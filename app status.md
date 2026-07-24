# Sight Words — Check-In

### Project

An adaptive sight-word flash-card app for Vinny (7) and Chase — one word at a time, scored by a parent or the child, with spaced repetition, optional on-device voice-check, and a parent dashboard. Universal iPad/iPhone, built as a visual/UX sibling to Multiplication Adventure.

### Stage

**Active Development** (feature-complete against the v1 PRD, including stretch features — voice-check, hold-to-talk, iPhone support, generated art/SFX — but not yet validated with a real kid).

### Health

🟡 **Needs attention** — the app has never been used by Vinny or Chase; everything past "does it build and look right in the simulator" is still unverified against a real 7-year-old's voice and attention span.

### Waiting on Me ⭐

- **Run an actual session with Vinny** (Practice Together, then On My Own with voice-check) — this is the only way to know if the mic thresholds, hold-to-talk vs. automatic, and pacing are right.
- **Kids' iPad deploys** — needs your go-ahead plus registering Vinny's and Chase's UDIDs for this bundle ID (standing rule: never pushed without your explicit word).
- **Public repo has the kids' first names/ages in the PRD** — flagged when I pushed it public; you haven't said whether to scrub it or leave it (matches your Math Tutor repo's pattern).
- Your iPhone build is now **stale** — it has last week's UI but not the visual/CX pass (art, SFX, celebration, streak chip) that just went to your iPad.

### Next Session

- On-device test with Vinny: both practice modes, voice-check on, note anything confusing or mis-heard.
- Redeploy the current build to your iPhone (quick, just needs a device build + install).
- Decide the kids'-iPad question and, if yes, register UDIDs and Ad Hoc deploy.
- Resolve the public-repo name-exposure flag (scrub or accept).
- If aiming at the App Store, do a scoping pass — see readiness list below, since the PRD currently treats that as explicitly out of scope.

### Deferred

- Quick-check assessment mode (no-hints test)
- Mastery testing in sentence/phrase context and mixed with look-alike words
- Per-word phonics reteach tips (e.g., "said: the middle 'ai'…")
- Voice-check in Practice Together mode (parent already judges there)

### App Store Readiness

The PRD currently makes "no App Store release" an explicit non-goal (household Ad Hoc installs only) — this list is what changing that decision would require:

- Explicit decision to pursue store release (scope change from the current PRD)
- Privacy nutrition label + App Review disclosure for microphone/speech-recognition use
- Kids Category compliance review — parental gate exists already, but full COPPA/data-collection checklist not done (no analytics/tracking currently, which helps)
- Privacy policy URL, support URL, store screenshots per device size, description/keywords
- Real device testing beyond your iPad (currently: sim + one physical device)
- Confirm ElevenLabs voice license permits commercial App Store distribution (fine as a "design-time asset" for personal use per your Build Guide; store distribution may need a license check)
- TestFlight beta with the actual kids before any public release
- Version/build-number bump plan; confirm no debug-only demo hooks leak into a release build (currently gated behind `#if DEBUG`, worth a final grep before archiving)

### Biggest Risk

Every UX and voice-check decision so far has been validated in a simulator or by an adult, not by a 7-year-old — the real test with Vinny could invalidate assumptions baked into several features already shipped.