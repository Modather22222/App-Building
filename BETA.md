# Beta program & distribution — App Building

## Distribution decision (locked 2026-10-28)

**Direct APK now, Play Store later.**

- Direct: the rolling link `github.com/Modather22222/App-Building/releases/
  latest-build/app-release.apk` + per-app APKs from each generated app's
  release tag. Zero review friction for the beta.
- Play Store (post-beta) requires, in order:
  1. A real upload keystore (current APKs are debug-signed) + signing discipline.
  2. The privacy policy URL (PRIVACY.md hosted — use the repo raw link).
  3. Data-safety form: auth data (email), user content (chats/prompts),
     no third-party sharing — matches PRIVACY.md.
  4. appDensity of store listing: screenshots from the app (chat, build
     timeline, download screen).

## Beta recruitment (target: 10–20 Flutter devs)

Post template (X/reddit/Discord):

> I built App Building — a chat agent that turns an app idea into an
> installable APK. You describe screens and features, the agent scopes the
> plan, generates the full Flutter project, pushes it to GitHub and ships a
> debug-signed APK back into the chat. Looking for 10–20 Flutter devs to kick
> the tires: bad generations, weird UX, missing flows — everything is signal.
> [link]

Feedback loop per tester (ask in this order):

1. What did you try to build first? Did the FIRST plan proposal feel right?
2. Where did the build fail (if it did) — what did the error text tell you?
3. Did the APK install and run? (MIUI/Huawei installs are gold.)
4. What would you expect the free tier's 3 builds/month to cover?
5. Would you pay $19/mo for 10 builds? What's missing before that's real?

## Plan-size calibration (collect during beta)

- Median chat turns before a PLAN lands (server: funnel_view.planned_30d)
- Median prompt length + screens requested (projects.prompt inspection)
- Failure rate per user (failed / total projects) → informs refill-pack size

## Launch-blocking checklist

- [ ] App icon + splash (Phase 1 item — replaces the default Flutter icon)
- [ ] PRIVACY.md hosted at a public URL (raw GitHub link works for review)
- [ ] Real upload keystore + CI secret wiring
- [ ] R8 device-verified on a real generated app (slice 4 follow-up)
- [ ] Accessibility pass (Phase 1 item)
