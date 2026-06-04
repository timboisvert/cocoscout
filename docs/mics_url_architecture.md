# Find a Mic — URL architecture (who sees what, where they do it)

A reference for the four roles touching the mics finder:

- **public** — anyone, signed in or not
- **mic owner / producer** — a User listed on `mic.mic_producers`
- **city captain** — a User with `CityHubMembership.role = editor` for a hub
- **superadmin** — a User whose email is in `User::SUPERADMIN_EMAILS`

Superadmins are the implicit captains for any hub without one.

---

## Public — accessible to everyone

| Path | What |
|---|---|
| `/mics` | Find-a-mic home (hub grid + vote-for-city + city search) |
| `/mics/search?q=…` | Global mic + venue + city search |
| `/mics/:city_slug` | City listing with filters (When / Format / Distance / Sign-up / Accessibility) |
| `/mics/:city_slug/tonight` | "Tonight" bucket |
| `/mics/:city_slug/tomorrow` | "Tomorrow" bucket |
| `/mics/:city_slug/this-week` | "This week" bucket |
| `/mics/:city_slug/:format_segment` | Format bucket (`standup`, `music`, `poetry`, `open-stage`) |
| `/mics/:city_slug/map` | Map view (alias of `/mics/:city_slug?view=map`) |
| `/mics/:city_slug/calendar.ics` | Subscribe-via-iCal for the whole city |
| `/mics/m/:slug` | Public mic detail page (404s for `pending=true` unless `manageable_by?`) |
| `/mics/m/:slug/calendar.ics` | Subscribe-via-iCal for a single mic |
| `/mics/submit` | Submit a mic (lands as `pending`) |
| `/mics/m/:slug/suggest` | Submit a public suggestion (modal trigger on the mic page) |
| `/mics/m/:slug/claim` | Claim ownership of a mic |
| `/mics/m/:slug/challenge` | Challenge ownership |
| `/mics/m/:slug/announcements` | View announcements (POST endpoint for producers) |
| `/api/mics.json`, `/api/mics/m/:slug.json`, `/api/mics/:city_slug.json` | JSON for sitemap + 3rd-party tools |

---

## Signed-in (any logged-in user)

| Path | What |
|---|---|
| `/mics/my` | "My Mics" — favorites + the mics this user runs |
| `/mics/m/:slug/favorite` (POST/DELETE) | Toggle favorite |
| `/mics/m/:slug/alerts` (POST), `/mics/alerts/:id` (DELETE) | Manage sign-up open alerts |
| `/mics/city_votes` (POST) | Vote for a future city |

---

## Mic owner / producer — `manageable_by?(user)` is true

These all live at `/mics/producer/:slug` (same URL, view adapts to role):

| Path | Action |
|---|---|
| `/mics/producer/:slug` | Edit page — name, format, schedule, sign-up info, accessibility, pause, etc. |
| `/mics/producer/:slug` (PATCH) | Save edits |
| `/mics/producer/:slug/venue` (PATCH) | Edit current venue in place |
| `/mics/producer/:slug/move_venue` (POST) | Re-point this mic at a different venue |
| `/mics/producer/:slug/verify` (POST) | One-click "verify this listing is current" |
| `/mics/producer/:slug/status` (POST) | Post a status for a specific date (cancelled / online only / extra spots) |
| `/mics/producer/:slug/cancel_date` (POST) | Cancel one specific date |
| `/mics/producer/:slug/producers` (POST) | Add a mic runner (with email lookup + invite-if-missing) |
| `/mics/producer/:slug/producers/:id` (DELETE) | Remove a runner (or leave the mic, if it's yourself) |
| `/mics/producer/:slug/producers/:id/set_lead` (POST) | Promote a runner to lead |
| `/mics/producer/:slug/links` (POST) | Add a social link |
| `/mics/producer/:slug/links/:id` (DELETE) | Remove a social link |
| `/mics/producer/:slug/announcements` (POST) | Post an announcement |
| `/mics/producer/:slug/suggestions/:id/approve` `/reject` (POST) | Act on community edit suggestions for *their* mic |
| `/mics/producer/:slug/migrate` (GET/POST) | Migrate this mic to a CocoScout-powered Production + sign-up form |

**Producers do NOT see:** slug field, delete button, captain-level moderation surfaces.

---

## City captain — `CityHubMembership.role = editor` for the relevant hub

Mirrors the producer page for their own mics (via `manageable_by?` returning true through hub membership) **plus** hub-wide moderation surfaces:

| Path | Action |
|---|---|
| `/mics/hubs/:slug` | Captain dashboard — overview of the hub: stats, mics list, recent activity |
| `/mics/hubs/:slug/queue` | Captain queue — pending submissions / claims / challenges / suggestions scoped to the hub |
| `/mics/hubs/:slug/submissions/:id/{approve,reject}` (POST) | Act on submissions |
| `/mics/hubs/:slug/claims/:id/{approve,reject}` (POST) | Act on claims |
| `/mics/hubs/:slug/challenges/:id/resolve` (POST) | Resolve a challenge (replaced / co_produce / rejected) |
| `/mics/hubs/:slug/suggestions/:id/{approve,reject}` (POST) | Act on suggestions |
| `/mics/producer/:slug/*` (any mic in their hub) | Edit any mic in the hub, including slug + delete |

**Captains see what producers see PLUS**: slug edit, delete button, hub-scoped queue, and they receive in-app notifications for any submission/claim/challenge/suggestion landing on a mic whose venue rolls up to their hub.

---

## Superadmin — `User::SUPERADMIN_EMAILS`

Implicit captain for every hub. Everything captains can do, but global rather than hub-scoped:

| Path | Action |
|---|---|
| `/superadmin/mics` | Unified admin surface: pending queue + full-text search across every mic in every hub |
| `/superadmin/mics/queue` | Permanent 301 to `/superadmin/mics` (legacy URL) |
| `/superadmin/mics/queue/:id/{approve_submission,reject_submission}` (POST) | Act on submissions globally |
| `/superadmin/mics/claims/:id/{approve,reject}` (POST) | Act on claims globally |
| `/superadmin/mics/challenges/:id/resolve` (POST) | Resolve challenges globally |
| `/superadmin/mics/suggestions/:id/{approve,reject}` (POST) | Act on suggestions globally |
| `/superadmin/mics/hubs` | City hub management — create, promote, archive, appoint captains |
| `/superadmin/mics/hubs/:slug` | Single hub admin — settings, captains, smart suburb roll-up |
| `/superadmin/mics/hubs/:slug/editors` (POST) | Add a captain (email lookup + invite-if-missing) |
| `/superadmin/mics/hubs/:slug/editors/:user_id` (DELETE) | Remove a captain |
| `/superadmin/mics/hubs/:slug/rollup_venues` (POST) | Smart suburb roll-up — assign neighbor-city venues to the hub |
| `/superadmin/mics/hubs/:id/promote` (POST) | Promote a draft hub to active |

Superadmins also have impersonation buttons next to every captain row and every producer row, so they can preview each role's view.

---

## Sign-in / sign-out

Generic CocoScout auth — the same `/signin` / `/signup` / `/signout` URLs serve everyone. Authentication is a single shared identity across the entire platform (productions, auditions, open mics). The signed-in account strip at the bottom of every mics page exposes `/signout`.

---

## Notifications

Every new submission / claim / challenge / suggestion fires `Mics::NotificationService`, which sends an in-app message to:

- the captain(s) of the affected mic's hub if any exist, OR
- every superadmin if the hub has no captain (or the venue has no hub)

The notification copy is rendered through `ContentTemplate` records:

- `mic_submission_filed`
- `mic_claim_filed`
- `mic_challenge_filed`
- `mic_suggestion_filed`

Producers don't get notified via this path — they see suggestions on their own producer edit page's "Pending suggestions" section.

---

## How `manageable_by?` resolves

`Mic#manageable_by?(user)` returns true if **any** of these is true:

1. `user.superadmin?`
2. `user` is on `mic.mic_producers`
3. `mic.venue.city_hub.editor?(user)` (captain of the hub the venue rolls up to)

That's the single predicate gating the Edit button, the producer edit page, slug visibility, delete capability, and pending-mic preview access.
