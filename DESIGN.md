# App Factory — Design Notes (v1)

Source: `dribbble-world-class-mobile-design` skill. Build target: Flutter, Material 3 (Android-first APK channel).

## Direction Chosen

- **Mode:** Crafted Utility (AI assistant + dev tool; trust-constrained per user: "trustworthy and clean, no fancy")
- **Subject:** App Factory — chat agent that turns prompts into shipped MVP Flutter apps; audience: Flutter developers
- **Platform soul:** Material 3 Expressive, restrained (M3 `NavigationBar`, `FilledButton`, sheets)
- **Color theme:** Forked *Field* (Productivity/Crafted Utility) light palette + *Midnight Pro*-style semantic dark override; primary tuned violet→indigo `#6366F1` / `#818CF8` for trust
- **Typography:** Roboto Native system scale (no font bundling); mono (`monospace`) only for build metadata
- **Layout:** #7 Tab & Stack shell (Chats/Apps/Profile) + #1 Stack & Card lists + #12 sticky bottom composer/CTA (+ #4 list-first settings)
- **Signature element (restrained):** build-pipeline timeline card in project detail — stage dots animate pending→spinner→green check with `medium` haptic on "Ready"; plus pulsing typing dots during agent streaming

## Token system (Flutter implementation)

| Token | Light | Dark |
|---|---|---|
| scaffold bg | `#FAFAF8` | `#0B0C10` |
| brand primary | seed `#6366F1` | seed `#818CF8` |
| card | `surfaceContainerLow` + 1px `outlineVariant@50%` border, r16, 0 elevation | same rules |
| fields | filled `#F2F3F6` | filled `#161821` |
| status/queued | amber-700 `#B45309` | same |
| status/building | sky-600 `#0284C7` | same |
| status/ready | green-600 `#16A34A` | same |
| status/failed | red-600 `#DC2626` | same |
| radius | card 16 / field 14 / button 12 / sheet 20 / pill 999 |
| spacing | 4pt grid, gutter 16, gaps 8/12/16, section 32 |

Rules honored: dark = semantic override (not inversion); no glass on cards; status pills = 12% tint bg + colored dot + label (icon+label, never color-only); text-on-tint checked for contrast.

## Screen map & flows

1. **System splash** (default launcher theme, no custom animation)
2. **Onboarding** (2 pages: value "Describe it. Ship it." → 3-step how-it-works; Skip top-right; CTA bottom)
3. **Auth** (SegmentedButton sign in/up, email+password with inline validation, guest escape; honest footnote about MVP auth)
4. **Shell:** M3 NavigationBar 68dp — Chats / Apps / Profile; per-tab state preserved
5. **Chats:** list rows (44pt icon tile, title, one-liner, timeAgo); FAB.extended "New chat"; empty = ghost rows + icon + outcome headline + single CTA
6. **Chat:** reverse-anchored bubbles (user = primary right, agent = `surfaceContainerHighest` left with 30px agent dot), streaming agent text, typing dots while empty, long-press copy, wrap-composer sticky bottom + 48pt send button (scale 0.88 press + selection haptic); "Build this app" button spawns project → pushes detail
7. **Apps:** rows with status pill + indeterminate bar while active; long-press sheet: details / simulate failure (dev) / delete; FAB "New app" → Chats tab
8. **Project detail:** header (name+summary) → pipeline timeline card (build stages: Generating→Pushing→Queued (queue-wait copy)→Building→Ready, durations shown when done) → build info list (mono, repo/requested/status/artifact) → sticky bottom bar (progress + primary CTA: Download APK / Retry build / stage-disabled state)
9. **Profile:** identity header → plan card (Starter $19, usage meters for slots/builds/edits + honest "demo data" note, Upgrade → snackbar placeholder) → settings list (Appearance sheet w/ live theme switch, build notifications toggle, About v1.0.0) → sign out (confirm dialog)

### Haptic map
send/selection → `selectionClick`; chat open/new app → `lightImpact`; build start/commit/copy → `mediumImpact`; build ready/fail → `mediumImpact`; long-press menus → `mediumImpact`.

### Motion
Press scale 0.88 @120ms easeOut; typing dots 1100ms loop; page push = system M3 transitions; dots 22px pill morph on onboarding. No parallax, no looping marquees, no glass.

## Compliance notes
- Primary CTAs always bottom-third (composer/CTA bar/FAB) — never top.
- Touch targets ≥ 44/48pt; icon buttons 48px.
- Empty states: first-use ghost preview + one CTA (Chats, Apps); deleted-app removal gives toast; failed build keeps last stage visible with retry (error state designed, not blank).
- No hamburger; no identical-iOS-UI problem (M3 native widgets on Android-first channel).
- Dynamic Type: default M3 text scale; 135% audit pending (TODO Phase 1).

## Deliberate restraint list (what we did NOT add, per user)
No gradients, no glass/glow, no hero animations, no custom fonts, no custom splash system, no animated app icon. Future "wow" budget reserved for the pipeline timeline card (signature) if desired later.
