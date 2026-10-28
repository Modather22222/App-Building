# Privacy & Terms — App Building (plain-language summary)

_Last updated: 2026-10-28. This summary is the product-facing contract; it is
deliberately short and readable._

## What we store

| Data | Where | Why |
|---|---|---|
| Email + password | Supabase Auth | Sign-in only; no marketing email |
| Chat conversations | Supabase (chats, messages) | Restoring your chat history when you reinstall |
| App ideas / build prompts | Supabase (projects) | Driving the build pipeline |
| Build metadata | Supabase (projects, funnel_events) | Showing build status, sizes, and anonymous usage counters |
| Generated code + APKs | GitHub (public repos under pool accounts) | Building and delivering the APK — **these repos are public** |

## What we do NOT do

- No advertising, no tracking SDKs, no third-party analytics beyond the
  anonymous funnel counters (signup → chat → plan → build → download).
- No selling or sharing of personal data. There is no data to sell — the app
  stores only what it needs to function.
- We do not read your private chats as a matter of course; support may inspect
  a chat thread **only** if you ask for help with a bug and consent.

## Your data, your control

- Delete a chat or a built app in the app → it is deleted from the server.
- Want everything gone? Email the address on the app's store listing (or open
  an issue on the factory repo) and the account + all rows are removed.
- Generated apps live in public repos — **do not put secrets** in app prompts.

## Terms of use (summary)

- The service builds MVP Flutter apps from your prompts using AI. Output is
  yours to use, including commercially.
- The service is provided as-is, in beta: builds can fail, quotas apply per
  plan, and nothing is guaranteed available. Do not rely on it for
  safety-critical software.
- Abuse (rate-limit evasion, spamming the pipeline, hostile prompts) ends the
  account's access.
- Paid plans are coming; until billing exists all plan enforcement is soft.
