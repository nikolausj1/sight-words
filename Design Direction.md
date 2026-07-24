---
title: "Design Direction — Paper-Cut"
created: 2026-07-24
status: agreed with Justin (samples in _inbox/design style; Phases A+B approved)
---

# Sight Words — Paper-Cut Design Direction (v2 visual language)

Binding for all Phase A+B work. Reference samples: `_inbox/design style/*.png` — layered paper-cut: organic wavy-edged shapes, concentric depth rings, soft short drop shadows between layers, scenes framed inside cut "windows", saturated-but-soft color fields. NO characters. Sample 4 (night/teal rings) = the night-mode reference.

## 1. Paper system (new Theme layer — `PaperTheme`)

- **PaperLayer**: the core primitive — an organic rounded blob shape (smooth closed spline over jittered control points; 2-4 seeded variants so edges aren't identical everywhere) filled with a flat color, casting `shadow(color: .black.opacity(0.14), radius: 6, y: 4)`. Layers stack: each ring inset ~14-20pt, one tint step darker/lighter.
- **PaperWindow**: 2-3 concentric PaperLayers with the content inside the innermost — THE container for every game board, card area, and modal. Kills the floating-white-card look: the space around content is layered colored paper, never bare background.
- **Paper texture**: existing noise texture at very low opacity on every layer (paper grain).
- **Fills**: per-game accent families (see §3); home + shared surfaces use warm cream/sage/sky families from the samples.
- **Edge flora**: bottom-edge paper leaf/hill silhouette strips (generated art, §5) on home + game screens for depth, behind interactive content, never overlapping touch targets.

## 2. Button system — kid-scale (research: 6-8yo need >adult targets; ~2cm primary)

- **PaperKeyButton** (replaces ChunkyKey usage on kid-facing screens): puffy paper tile, bold saturated fill + white 3pt inner stroke, soft shadow. Sizes: `hero` 88pt min-height (Play!, Show answer, Next), `primary` 72pt (scoring, game actions, Yes/✓), `chip` 60pt (shelf tiles stay 84pt but adopt paper look). Corner radius: organic-blob or 20pt continuous. Min spacing between targets 16pt.
- **Touch response (all buttons)**: squash-and-bounce — press: scale 0.92 + shadow flattens (y:4→1) + slight rotate ±1°; release: overshoot spring to 1.04 then settle 1.0 (`Theme.Motion.tileLift`), `Feedback.fire(.keyTap)` on press. Reduce Motion: opacity dip only.
- **SpeakerButton (redesign)**: 64pt round paper badge, warm gold fill, white speaker glyph, sits on a small paper ring; while speaking: gentle wobble + 3 animated paper "sound arc" petals appearing sequentially. This is THE persistent replay affordance everywhere (games top-left, cards).
- **CloseButton (redesign)**: 64pt round paper badge, soft coral fill (not harsh red), white ✕; press-and-hold retained (0.6s) but the radial fill becomes a paper ring "unrolling" around the badge; wiggles once if tapped briefly (teaches the hold).
- Parent-facing screens (parent area) KEEP current adult-density styling — this system is for kid surfaces.

## 3. Per-game accent colors (paper fills; identity + wayfinding)

wordHunt: leaf green family. sayMatch: sky blue. memory: violet. missingLetter: coral/orange. spellingBuilder: sunshine gold. trickyWords: warm red-orange. Shelf tiles, PaperWindow rings, in-game highlights and RoundCelebration confetti bias use the game's family. Home Play! stays primary blue.

## 4. Composition rules (fixes "white space looks like a bug")

- Every screen: full-bleed backdrop (scene art or paper color field) → PaperWindow(s) → content. Bare `bg` color as a visible field is BANNED on kid screens.
- Game boards: PaperWindow fills ~80% of the safe area's smaller dimension; word lists/trays sit in their own smaller PaperWindows; remaining margins show backdrop + edge flora, not emptiness.
- Home: sky-to-ground scene backdrop (art §5), Play! on a paper pedestal ring, shelf tiles as paper chips floating on a foreground paper hill strip.

## 5. Art inventory (Gemini, paper-cut prompts; NO characters/text)

Style line: "layered paper cut out art style, flat colored paper shapes with soft drop shadows between layers, organic wavy cut edges, depth through stacked paper layers, children's book quality, absolutely no text, no characters, no animals with faces."
- `paper-scene-day` (4:3 ×2 cand.): daytime paper landscape — cream sky, sun, paper clouds, layered green hills, calm empty center.
- `paper-scene-evening` (4:3 ×2): same composition, dusk palette (amber/violet).
- `paper-scene-night` (4:3 ×2): sample-4-inspired — deep teal/navy, paper moon + stars.
- `paper-flora-strip` (wide ×2): bottom-edge leaf/hill silhouette strip, transparent-top feel (solid bottom band).
- `gameicon-*` ×5 regenerated as ONE family (paper-cut objects, per-game accent fills, same framing/scale, no apples/extras).
- `garden-bed` (4:3 ×2): empty paper garden — soil rows on a hill, sky, room for many small plants.
- `garden-sprout`, `garden-flower-1..4`, `garden-tree` (1:1, transparent-look on cream): individual paper plants, small, same shadow language.
- Splash stays (fox & owl, Justin's call 2026-07-22).

## 6. Phase A feel items (unchanged from approved plan)

Speech-length-aware beats (AVAudioPlayer duration + completion-driven pacing replaces fixed sleeps; SpeechService exposes duration/completion); "One more round?" end-of-game flow (RoundCelebration gains a second PaperKey "Again!" beside "Done" — replays a fresh round set, max 3 sets/sitting then gentle "All done for now!"); designed home→game transition (paper window irises open from tapped shelf tile position); Missing Letter voice beat ("Now read it!" after each completed word, optional/skippable per §1 voice rules); Tricky Words tile launches a game-capable mode (rotates games, deck = needsReview words, no new); tile chrome folded back into GameKit (single source).

## 7. Word Garden (Phase B reward — approved with A+B)

- New kid screen off home (paper chip next to profile: "My Garden"): a paper garden scene; every MASTERED word plants a paper flower/plant (deterministic variety from word hash; sprout appears at `fluent`, blooms at `mastered`). Tap a plant → hears the word + a tiny bounce. Counter chip "N words growing".
- No currency, no purchases, no streaks pressure, nothing to lose — plants never die. Pure progress made visible. New Rachel clips: "Look at your garden grow!", "A new flower!" (+ manifest).
- Guided session complete: if a word crossed to mastered this session, a 2.5s garden moment plays (flower blooms in) before Done.
- Data: derived entirely from existing WordProgress states — no new persistence beyond a per-word planted-variant seed.

## 8. Night mode (Phase B)

Auto by clock (after 19:00 local or before 07:00): scene art swaps to `paper-scene-night`/evening, PaperLayer fills shift to the deep-teal family, white text warms, overall brightness cap (no pure white), speaker/close badges dim-adjust. Parent toggle: Auto / Always day / Always night. Smooth crossfade on change.
