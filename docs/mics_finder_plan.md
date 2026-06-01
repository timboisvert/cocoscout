 # CocoScout Mics — Plan & Spec

*The greatest open mic finder in the United States.*

Status: **Proposed.** Not built yet. This document is a spec, not phasing.
Last updated: 2026-05-30.

---

## TL;DR (the elevator pitch)

`cocoscout.com/mics` is a public, **no-login-required** map+list of every open mic
in the United States. The home page resolves to "what's near me tonight."
Power-curated **city hubs** (Chicago, NYC, LA, Seattle, Austin, etc.) own the
SEO and the local flavor. Every mic page is its own SEO + social asset with
**JSON-LD `Event` schema**, rich OpenGraph cards, structured time/place data,
and freshness signals — so it wins for queries like *"Chicago open mics
tonight"*, *"wheelchair accessible standup mics near me"*, and
*"Sunday open mic Brooklyn"*.

Performers can sign in to CocoScout to **favorite** mics, get **sign-up open
alerts**, and (later) track their sets. Mics whose sign-ups are powered by
CocoScout show a **"Powered by CocoScout"** badge and serve as the conversion
funnel: every other producer sees that badge and gets a one-click path to
move their own sign-ups onto CocoScout.

**Producers** can **claim** a mic and become its source of truth. Anyone can
**challenge** an existing claim. Superadmins (and, later, trusted **hub
editors**) adjudicate.

We will out-build, out-data, and out-SEO every comedy-app, every old-school
forum thread, and every Google Sheet that has ever served as the "list of
mics" for a city.

---

## A mic is just a mic (and migration is the upgrade path)

The central architectural commitment of the project:

> **A mic is just a mic.** The public listing is a thin, self-sufficient
> record — name, venue, recurrence, sign-up info, blurb. We do **not**
> require any heavier CocoScout structure (no Organization, no Production,
> no Show, no SignUpForm) for a mic to exist, be browsable, or rank for
> SEO. That's true forever, even after producers come on board.
>
> **Migration is the upgrade path.** When a producer claims their mic and
> wants the full CocoScout experience — sign-ups, audience messaging,
> talent pools, payouts, the whole graph — the migration wizard creates
> the Production + recurring `Show`s + `SignUpForm` for them, then *links*
> them to the Mic. The Mic stays the constant. The richer CocoScout
> models are an optional projection of the same mic, switched on by the
> producer's choice.

Mechanically:

- The `Mic` model owns the minimum: venue, recurrence (day-of-week + local
  time + RRULE), sign-up method + URL + opens-at description, blurb,
  accessibility, format, host summary, last-verified, etc. **Every public
  listing — claimed or not — has all of this.**
- `Mic#production_id` is **optional**. Most rows start with it `nil`.
- When `production_id` is set (post-migration), the Mic page reads schedule
  from the Production's upcoming open-mic `Show`s and sign-up timing from
  its `SignUpForm`. The Mic's own recurrence/sign-up columns become
  display defaults — overridden cleanly by the linked records.
- The public view (URLs, layout, SEO output) is **identical** whether or
  not the Mic is linked. The reader never sees the difference except for a
  **"Powered by CocoScout"** badge and a different sign-up button.

### The migration moment

When a producer (whose Mic is currently unlinked) hits **"Power my
sign-ups with CocoScout"**, the wizard runs in one server-side transaction:

1. Ensure an `Organization` exists for them (use existing if signed-in
   manager of one; otherwise create one named after the venue + city).
2. Create a `Production` for this mic (name = Mic.name; production_type
   minimal).
3. Generate a series of `Show`s with `event_type: open_mic` from the Mic's
   `recurrence_rule`, projecting out e.g. 6 months. Re-projected by a
   periodic job as the calendar slides.
4. Create a `SignUpForm` covering those Shows (event_type_filter:
   `["open_mic"]`), prefilled to match the Mic's sign-up timing (opens
   offset, closes mode, cap).
5. Set `Mic.production_id = production.id`. Mic's recurrence + sign-up
   columns are left in place as immutable history.

From that moment forward, the producer manages everything through the
existing CocoScout manage UI (shows, sign-ups, messages, payouts). The
public Mic page transparently reflects whatever they configure there.

### The "already in CocoScout" path

If the claimant already has an `Organization` and a `Production` for this
mic, the wizard skips the generation steps and just sets
`Mic.production_id` to their existing Production. No data re-entry, no
duplicates.

### Why this shape

- **Onboarding is frictionless for unclaimed listings.** We can crawl /
  seed thousands of mics from public sources and have a useful site on
  day one, no Producers needed.
- **Producers see a clean before/after.** Their listing existed; now it's
  theirs and richer. The richer parts use the same CocoScout muscle they
  use for everything else.
- **No parallel data model.** Sign-ups go through `SignUpForm`,
  cancellations through `Show.canceled`, producer communications through
  `Message`. We don't reimplement any of that.

---

## Guiding principles

1. **Be the canonical registry.** If a mic exists, it's here. If a mic
   moved, the lineage is preserved. If a mic died, that's recorded too.
2. **Public-first, fast, server-rendered.** No login wall for browsing.
   HTML in < 200ms server time, full content visible without JS. JS is
   sprinkles, not foundation.
3. **Win local SEO.** Each hub page and each mic page is a long-lived,
   keyword-rich, structurally-valid, freshness-signaling SEO asset.
4. **Trust through verification + sunlight.** Producer claims are tracked
   and visible. Edits are audited. Stale data is decayed and re-prompted.
5. **CocoScout-shaped.** Pink + white visual system, the same Tailwind look
   the rest of the app uses. Feels native to the product.
6. **Conversion-aware.** Every public surface (especially "Powered by
   CocoScout" badges) is an entry point for performers → account creation
   and producers → CocoScout sign-up adoption.

---

## Audience & jobs-to-be-done

| Audience | Primary job |
|---|---|
| **Comedians** (standup, especially) | "Where can I go up tonight?" / "When does the bucket draw open?" |
| **Musicians / poets / storytellers** | Same as above, filtered by format |
| **First-timers** | "Where do I start? Which mics are welcoming?" |
| **Visiting performers** | "I'm in Austin Wed–Sat. What's on?" |
| **Audience / scouts / friends** | "Where do I go to see good standup tonight?" |
| **Producers / hosts** | "Make our mic discoverable and stop fielding 'is it on tonight?' texts." |
| **Bookers / agents** | "Who's hot on the Chicago open mic circuit right now?" |
| **SEO traffic** (cold) | They Google "Chicago open mic" — we own that result. |

---

## Information architecture (URL design)

Public URLs are stable, human-readable, SEO-shaped, and **never require login**:

```
/mics                                # smart homepage; geo-resolves to nearest city listing
/mics/submit                         # submit a mic (any city, US-wide; sign-in required)
/mics/chicago                        # hub: Chicago
/mics/chicago/tonight                # tonight in Chicago, time-ordered
/mics/chicago/tomorrow
/mics/chicago/this-week
/mics/chicago/map                    # map-first view
/mics/chicago/standup                # format filter as URL segment
/mics/chicago/standup/wheelchair-accessible
/mics/m/lincoln-lodge-monday         # individual mic detail
/mics/m/lincoln-lodge-monday/calendar.ics
/mics/search?q=brooklyn+poetry
/mics/near/41.8781,-87.6298?radius=5
/mics/format/standup
/mics/sitemap.xml                    # plus per-hub sub-sitemaps
/mics.json                           # public, throttled, documented API
```

Filter combinations that drive real search traffic get their own server-rendered,
crawlable URLs (not just JS query params). Other filters live in the query string.

Authenticated URLs (CocoScout's existing auth):

```
/mics/favorites
/mics/alerts                         # subscribed sign-up timing alerts
/mics/me/history                     # if/when we add set tracking
/mics/producer                       # producer dashboard
/mics/producer/<mic-slug>
/mics/producer/<mic-slug>/claim
/mics/producer/<mic-slug>/edit
```

Adjudication lives under `/superadmin/mics/claims` and `/superadmin/mics/challenges`.

---

## Public experience (no login)

### Homepage `/mics`

- **Hero:** "Find an open mic tonight." A single search box ("city, ZIP, or
  venue") and a big **"Use my location"** button.
- **Below the hero:** the visitor's resolved city → list of "Tonight near you"
  (time-ordered) + a teaser map. If the visitor's city has zero Mics, we
  surface the nearest city that does, plus a prominent
  **"Submit a mic in <their city>"** CTA.
- **Featured hub:** a richly-styled tile for Chicago at launch. As more
  cities graduate to hub status, additional tiles appear.
- **Submit a mic:** a primary CTA all the way from the homepage. Anyone
  with a CocoScout account can submit a Mic in any US city.
- **Trust signals:** count of active mics, count of producers, "last updated
  3 minutes ago."

### City listing page / Hub page `/mics/<city>`

Every city with ≥ 1 Mic gets a page at this URL. **Promoted hubs** (Chicago
at launch) get a richer, hand-curated version of the same page — the URL
never changes, only the depth of curation. Either tier is a primary SEO
asset:

- **Top:** city name, weather-respecting "Tonight" header, intro paragraph
  (locally editable by hub editors), the city's open-mic-of-the-week.
- **Tabs:** **Tonight · Tomorrow · This Week · Map · All**.
- **Time-ordered list** (default). Each row: time, venue, format icons,
  sign-up status (open/closed/upcoming), accessibility icon, distance from
  visitor, **"Powered by CocoScout"** badge where applicable.
- **Sort selector:** event start time (default for Tonight) / sign-up open
  time / distance / sign-up deadline.
- **Filter rail** (collapsible — sticky on desktop; bottom-sheet on mobile).
- **Map mode:** full-bleed map with clustered pins and a slide-up list. Pin
  hover shows mini-card; tap opens the detail page.
- **Local editor panel** (when a hub editor is signed in): inline approve /
  flag suggestions.
- **Footer:** SEO-rich internal links (other formats, other days, nearby
  cities, "What's an open mic?" FAQ, claim CTA).

### Mic detail page `/mics/m/<slug>`

This page is the canonical source of truth for one mic and one of our most
important SEO assets.

- **Header:** Name, venue, neighborhood, format pills, accessibility icons,
  status (Active / Cancelled tonight / On hiatus), **"Last verified by
  producer 3 days ago"**.
- **Hero block:** Map snippet + venue photo (if available) + "Get directions"
  + "Add to calendar (ICS)" + "Share."
- **What you need to know strip:** Format · spot length · cost · sign-up
  method · sign-up opens · sign-up cap · drink minimum · age.
- **Schedule:** Recurrence ("every Monday 8pm CT"), next 6 occurrences with
  per-occurrence status (cancelled / extra-spots / running as planned).
- **Sign-up details:** prose + structured info. If pre-signup, the **exact
  time the sign-up opens**, the link, and a button **"Alert me 5 minutes
  before sign-up opens"** (requires login).
- **Hosts / producers:** names, links to public profiles (CocoScout existing
  pattern), optional Instagram handles.
- **"Powered by CocoScout" badge** OR **"Are you the producer? Move your
  sign-ups to CocoScout — free, in 5 minutes."**
- **Recent attendance pulse:** "12 performers signed up last week" if we
  have CocoScout data; otherwise omitted.
- **Vibes / ratings** (stretch): 4 axes (audience, vibe, list odds, time
  discipline). 0–5 stars.
- **Related mics:** "Same producer," "Other mics tonight nearby," "Same
  night of week."
- **Edit suggestions:** anyone can suggest a correction.
- **Audit footer:** "Edited 4 times in the last year. Verified by the
  producer on 2026-05-12."

---

## Authenticated experience

Signed-in CocoScout accounts get:

- **Favorites** — heart icon on any mic; sticky list at `/mics/favorites`.
- **Sign-up open alerts** — per mic, opt in. Web push, email, optional SMS.
  This is one of the most product-valuable features in the whole spec
  (see Stretch features).
- **My Mics** — a list of mics you've favorited, signed up for via
  CocoScout, or attended.
- **Submit a new mic** — anyone signed in can submit; goes through a
  light moderation queue.
- **Suggest edits with attribution** (auto-approve after N approved
  contributions).
- **My account** ties into existing CocoScout auth and (when ready) social
  login.

---

## Producer experience

### Producer identity = CocoScout account (always)

**Every producer and co-producer of a mic has a CocoScout User account.**
There is no anonymous, email-only, or "lightweight" producer role. The
moment someone is approved as a producer of a Mic, there is a `User`
record they sign in with — and from that User we tie everything else:
producer rights on this Mic, the audit log, the inbox where challenges
arrive, alerts they configure, and (when they migrate) the Organization
they manage.

What this means in practice:

- **`MicProducer.user_id` is `NOT NULL`.** No producer without an account.
  Same for `lead_producer_user_id` on `Mic`.
- Claim flow requires being signed in. If a visitor hits "Claim this mic"
  while logged out, we route them through the existing CocoScout sign-up
  /sign-in flow first, then come back to the claim form with their
  account already attached.
- A producer can exist with **no Organization yet** — they can manage
  Mic-level fields (schedule, blurb, accessibility, hosts) without one.
  Creating the Organization is what *migration* does, not what *claiming*
  does. That keeps the on-ramp light: claim now (free, one form), migrate
  to CocoScout sign-ups whenever they're ready.
- Hub editors and superadmin adjudicators are also Users by definition;
  permissions hang off the existing CocoScout role model.

### Claim a mic

A signed-in user clicks **"Claim this mic"** on the detail page. The form
collects:

1. **Role** — producer / co-producer / host.
2. **Proof** — one or more of:
   - Code emailed to a venue-published address (e.g. the listed mic
     email) — verified against the claimer's CocoScout account email or
     a confirmed alternate.
   - Instagram DM verification (we publish a token; they DM us from the
     mic's known account; we match).
   - Manual review (upload a photo / link to a recent flyer / link to
     announced show).

Outcomes:

- **Auto-approved** when the proof unambiguously matches (e.g., the
  code-email landed on a venue-published address).
- **Pending** in the moderation queue otherwise (superadmin + hub
  editors).
- **Rejected** with reason logged; user can re-file with new evidence.

On approval we insert a `MicProducer` row linking `Mic` ↔ `User`. The
existing CocoScout `Session` + Authentication concern carries them into
the producer dashboard.

### Manage a mic

Once claimed, a producer can edit any field on the mic, post one-off
occurrence updates ("running as planned tonight" / "cancelled" /
"online-only"), invite **co-producers** (by CocoScout email — if the
invitee doesn't have an account, we send the existing `PersonInvitation`
flow), hand off lead-producer status, archive the mic, and (when ready)
**migrate sign-ups onto CocoScout** via the wizard described above.

Producer dashboard `/mics/producer`:

- List of mics they manage with at-a-glance "needs attention" flags
  (e.g., "Schedule hasn't been confirmed in 30 days").
- Quick **post status** affordance ("Mic is on for tonight").
- Co-producer management: invite, demote, remove. Invites that hit a
  non-account-holder send a CocoScout invite; they only become producers
  once they accept and have an account.
- Notification preferences for sign-up activity, challenges filed, edit
  suggestions on their mics.
- **Migrate sign-ups to CocoScout** — single CTA that triggers the
  Organization + Production + Shows + SignUpForm wizard (described in
  *A mic is just a mic* above).
- Add a one-off bonus date / cancel a specific date.

### Multiple producers

One or more `MicProducer` rows per mic, each `belongs_to :user` (required).
All co-producers can edit by default. A single `Mic.lead_producer_user_id`
designates the primary contact for adjudication and the default recipient
for inbound challenge notifications.

### Migrating sign-ups to CocoScout

When a producer wants CocoScout-powered sign-ups, the wizard:

1. Imports the mic's schedule into a `SignUpForm` template (existing system).
2. Sets sign-up open offsets (e.g., "opens at 12pm day-of").
3. Generates a sign-up URL — when the mic's `signup_url` matches one of
   ours, the **"Powered by CocoScout"** badge auto-lights.

---

## Challenges & adjudication

Anyone can challenge an existing producer claim ("I actually run this mic,
they took it over from me").

Workflow:

1. Challenger files at `/mics/m/<slug>/challenge` with reason + evidence.
2. Existing producer is notified (in-app + email) and has **72 hours** to
   respond.
3. Both parties' statements are sealed pending review.
4. Superadmin (or **hub editor** when delegated) reviews at
   `/superadmin/mics/challenges`. Outcomes:
   - **Replace** — challenger becomes lead, current producer demoted/removed.
   - **Co-produce** — both kept.
   - **Dismiss** — challenge denied, marked frivolous if abusive.
   - **Request more info** — back to both parties.
5. Outcome is visible on the mic's audit log, but evidence stays private to
   adjudicators. Repeated frivolous challenges throttle a user from filing
   new ones.

This is one of the messier parts of the product. Doing it well (clear,
respectful, decisive) protects the mic ecosystem's trust.

---

## City hubs (Chicago first, anywhere-can-list, hubs graduate in)

### Two tiers, one URL space

Every city with at least one Mic gets a page at `/mics/<city-slug>`. The
**richness** of that page depends on whether the city has been promoted
to a **hub**:

- **City listing page** (default for any city with ≥ 1 Mic). Auto-generated.
  Title-tag, meta, list, map, and SEO-grade structured data are all
  produced from the underlying Mics. No intro copy, no curated featured
  list, no local editor team — just a clean, fast, complete list.
- **Hub** (curated layer on top). When promoted, the same URL gains:
  hand-written intro markdown, a featured-mics slot, a hub editor team,
  default-radius tuning, optional accent styling, a weekly "mic of the
  week" curation. The URL never changes — Google never sees a re-shuffle.

### Launch posture

- **Chicago is the first hub.** Hand-curated to a high standard: every
  active Chicago mic seeded, accurate, claimed where possible, with a
  written intro and at least one local hub editor lined up. This is the
  flagship that proves the format.
- **Every other US city is a city listing page from day one.** Including
  Podunkville, Indiana. Anyone can submit a mic anywhere; the system
  creates the city record on the fly if it doesn't exist. The listing
  page renders the moment there's one Mic in it.
- **Submission is open to any signed-in CocoScout user**, anywhere.
  Submissions enter the same light moderation queue as edit suggestions.
- **No "All US" landing page.** The `/mics` homepage geo-resolves to a
  city; if the visitor's city has no mics, we show the nearest city with
  mics + the "Submit a mic" CTA.

### Bringing a new hub online

A city listing page graduates to a hub when **all** of these are true:

1. **Scale signal.** Active mic count ≥ 10 in the city, sustained for at
   least 4 weeks. The admin queue surfaces candidates automatically.
2. **Local steward.** At least one credible **hub editor** application
   from someone in or active in that scene. (Producers of multiple mics
   in the city auto-qualify; others go through a short review.)
3. **Curation budget.** We (or the hub editor) commit to writing the
   intro copy and the first few featured-mic picks before flipping the
   switch.

When all three land, a superadmin (or, later, an established hub editor
in a neighboring city) flips the `CityHub` row to active. The URL stays
the same; the page gains its curated layer; we announce the new hub in a
short blog post + an OG-rich social card. That blog post and the
upgraded page become net-new SEO assets — graduation is a marketing
moment.

### Promotion candidates (tracked, not promised)

We watch (don't pre-commit to) the obvious next-up cities — **NYC, LA,
Seattle, Austin, Boston, Atlanta, Nashville, Denver, Portland (OR),
Philadelphia, DC, SF, San Diego, Twin Cities, Houston, Miami, Phoenix** —
plus any city where the criteria above happen to be met first. We'd
rather have one excellent Chicago than 18 thin landing pages.

### Hub editors

Hub editors are unpaid community trust. Their motivation: the same as a
Wikipedia city-page custodian — pride, visibility, and tools. Per hub we
expect 1–3 editors; they can:

- Approve/reject claim and edit suggestions for mics in their city.
- Set the hub intro and curated featured mics.
- Flag spam / abuse to superadmin.
- Recommend other people for editor status in their hub.

Their name + role are credited on the hub page (with opt-out).

### Data model implication

A small change from the earlier draft: `CityHub` is **not** required for a
city to have a public page. Cities live as a derived concept (a Mic's
`Venue.city + state` is canonical). The `CityHub` row only exists for
graduated hubs, and is what unlocks intro markdown, featured-mic slots,
editor membership, and the few hub-only fields. City listing pages render
without one.

---

## Data model

**Headline:** the public finder is a new thin `Mic` model (plus a handful
of finder-only siblings). It stands alone. **After a producer migrates**,
the same Mic *also* points at an existing CocoScout `Production` and
projects through `Show` + `SignUpForm` for richer behavior. Nothing about
Production/Show/SignUpForm changes structurally.

### New (primary)

The `Mic` is the always-present record. Everything else listed below is
finder-only metadata that orbits it.

### Existing CocoScout models, only used post-migration

| Existing | Role when a Mic links to it (else: not involved) |
|---|---|
| `Production` | The producer's Production for this mic. Reused as-is; no schema changes required. |
| `Show` (`event_type: open_mic`) | One occurrence of the mic, projected from the producer's recurring shows. Per-date status via existing `Show.canceled` plus a small `Show#mic_status` enum addition. |
| `SignUpForm` | Sign-up timing + cap when the producer wants CocoScout to power sign-ups. `event_type_filter` already supports `["open_mic"]`. No new sign-up engine. |
| `Location` | Stays as-is for org-private spaces. Public `Venue` is a new, separate model. |
| `User` / `Person` | Claimants, producers, hub editors, favoriters. |
| `Message` | Producer ↔ performer DMs route through the existing messaging system (we never expose producer emails publicly). |

### New (the public-finder layer)

| New entity | Purpose |
|---|---|
| `Mic` | The public listing. `belongs_to :venue`. `belongs_to :production, optional: true`. When the production is set, the mic is "powered by CocoScout"; when nil, the listing carries enough recurrence + sign-up metadata to stand on its own. |
| `Venue` | Public, deduplicated venue (name, address, city, state, postal, lat, lng, timezone, neighborhood, venue_type, accessibility defaults). Separate from `Location` (which is org-scoped private space). |
| `MicProducer` | `Mic` ↔ `User` (user_id **NOT NULL** — every producer has a CocoScout account). Role enum: `producer` / `co_producer` / `host`. Independent of CocoScout `production_permissions` — when a Mic has a Production, this row gates the finder-side edit rights; the existing `ProductionPermission` is the authority for the actual CocoScout Production. |
| `MicClaim` | A claim attempt; status pending/approved/rejected; evidence + adjudicator. |
| `MicChallenge` | A dispute against current producer(s); workflow as described in Adjudication. |
| `MicFavorite` | `User` ↔ `Mic` with an optional private note. |
| `MicSignupAlert` | A user's opt-in to be pinged before this Mic's sign-up opens. References either a `SignUpForm` (when linked) or the Mic's literal `signup_opens_at_text` (when not). |
| `MicSuggestion` | A public visitor's proposed edit, awaiting moderator approval. |
| `MicEdit` | Per-field audit log. |
| `MicTag` | Free-form tags (`lgbtq-friendly`, `first-timer-friendly`, `21+`, etc.). Join-table to Mic. |
| `MicLineageLink` *(stretch)* | "This mic moved venues" — preserves continuity / SEO. |
| `MicReview` *(stretch)* | 4-axis ratings (audience, vibe, list odds, time discipline). |
| `MicAttendance` *(stretch)* | Opt-in "I went tonight" check-ins. |
| `CityHub` | Hub metadata + editor list + intro + featured Mic ids. |

### Key `Mic` columns

```
slug, name (auto-derived from Production.name when linked, or self-set),
venue_id,
production_id (nullable — set when the mic is claimed by a CocoScout producer),
status enum (active | dormant | ended),
format enum (standup | music | poetry | storytelling | magic |
              variety | hiphop_cypher | improv_jam | mixed | virtual),

# Recurrence — used only when production_id is nil.
# When linked, we read from Production's open_mic Shows.
day_of_week (0–6),
starts_local_time,
recurrence_rule (RRULE string; weekly is the common case),
canceled_until (date),

# Sign-up — used only when production_id is nil.
# When linked, we read from the Production's SignUpForm.
signup_method enum (bucket_draw | pre_signup | walk_up |
                    lottery_online | invite_only | hybrid),
signup_url,
signup_opens_offset_minutes,
signup_opens_at_text  # "Mon 9am CT" — exactly as a producer would describe it

# Display + metadata
blurb (text),
spot_length_minutes,
signup_cap,
cost enum (free | drink_minimum | pay_to_perform | pay_pass_the_hat),
drink_minimum_amount_cents, cover_amount_cents, min_age,
accessibility (jsonb: wheelchair, hearing_loop, gender_neutral_restroom, …),
host_summary,

# Trust + audit
last_verified_at, last_verified_by_user_id,
claimed_at, lead_producer_user_id,
created_at, updated_at
```

### Small adds to existing tables

- `Show`: add `mic_status` enum (`scheduled` | `running_as_planned` |
  `cancelled` | `online_only` | `extra_spots`), defaulting to nil so
  non-mic shows are unaffected.
- `Production`: no schema change strictly required. Optional: a
  `public_mic_id` reverse pointer for fast lookup (or rely on
  `Mic.find_by(production_id: production.id)`).
- No changes to `SignUpForm`.

### Reading the schedule

When a Mic page renders the schedule, the controller does:

```ruby
upcoming =
  if mic.production_id
    mic.production.shows
       .where(event_type: :open_mic)
       .where("date_and_time >= ?", Time.current)
       .order(:date_and_time)
       .limit(6)
  else
    mic.next_six_occurrences # computed from recurrence_rule + canceled_until
  end
```

`upcoming` is the same shape either way. The view never branches.

### Reading the sign-up timing

```ruby
signup =
  if mic.production_id
    mic.production.sign_up_forms
       .where("event_type_filter @> ?", [:open_mic].to_json)
       .active
       .first
    # → reads form.opens_at / form.closes_at / form.closes_mode / etc.
  else
    {
      url: mic.signup_url,
      opens_at_text: mic.signup_opens_at_text,
      opens_offset_minutes: mic.signup_opens_offset_minutes
    }
  end
```

Same shape in both branches, so the alert system, the badge logic, and
the display all share one path.

---

## SEO — best in the world

Everything below is treated as launch-required, not stretch.

### Technical foundation

- **Server-rendered HTML** (Rails default) — every public page returns full
  semantic HTML without JS. JS hydrates the map and filters.
- **Performance budget:** < 1.5s LCP on 4G mobile. Image lazy-loading,
  pre-fetched hub pages from homepage, fully cacheable mic detail pages
  (5-min CDN TTL with surrogate-key purges on edit).
- **Stable, descriptive URLs.** Slugs are locked at creation; renames
  301-redirect from the old slug forever.
- **Canonical tags** everywhere a filter combo can be reached via multiple
  routes.
- **Sitemap:** Top-level index at `/mics/sitemap.xml`; per-hub
  `/mics/sitemap-<city>.xml`. Hand-rolled by a Rails controller streaming
  XML (no `sitemap_generator` gem); cached by Solid Cache and bumped on
  publish. Per-hub split keeps any single file well under Google's 50k-URL
  limit forever.
- **`robots.txt`:** explicit allow for `/mics/*`; disallow tracking params.
- **`hreflang`:** English-only at launch but tagged correctly for future
  Spanish translation of the standup-heavy hubs (Miami, LA, NYC).

### Page-level SEO

- Title tag formula:
  - Hub: *"Open Mics in <City> — <Day-of-week> | CocoScout"*
  - Mic: *"<Mic Name> — <Day> Open Mic at <Venue>, <Neighborhood>, <City>"*
  - Format pivots: *"Standup Open Mics in <City> Tonight"*
- Meta description templated, never auto-LLMed gibberish — written by us
  with mic-specific variables.
- **JSON-LD `Event`** on every mic detail page, one entry per upcoming
  occurrence. Set `eventStatus` to `EventScheduled` / `EventCancelled` so
  Google can surface cancellation directly in search.
- **`LocalBusiness`** schema for venues with addresses.
- **`ItemList`** schema on hub pages.
- **`BreadcrumbList`** on every nested page.
- **`FAQPage`** schema on a "How open mics work" content page per hub.
- **OpenGraph images** — at launch, one carefully designed static image per
  hub (Chicago, NYC, etc.) plus a generic mic template. Per-mic dynamic OG
  images are *not* launch-required and are NOT generated with headless
  Chrome — when we do them, we'll compose them with the existing
  `image_processing` + libvips pipeline (the same one driving headshots
  and posters) on a background Solid Queue job.
- `og:type=event`, `og:event:start_time`, `og:locality`.
- Twitter cards (`summary_large_image`) with author handles when known.
- Soft 404 prevention: dormant mics keep their URL with `og:event:status` =
  `EventCancelled` rather than disappearing.

### Content strategy (long-tail)

Each hub gets a small, **hand-written** content layer that gives Google
something to grip:

- "How open mics work in <City>"
- "First-time tips for performing at a <City> open mic"
- "Wheelchair-accessible open mics in <City>"
- "Where to do music open mics in <City>"

These pages link densely between mics and hubs (internal link equity), are
HTML-only, and are designed to age well (we update them quarterly with a
"as of <date>" footer).

### Freshness signals

- `last_verified_at` is **exposed in JSON-LD** as `dateModified`.
- Producer "running tonight" posts are crawled as `EventScheduled`
  re-affirmations.
- We surface "Verified by producer N hours ago" prominently — Google reads
  user trust signals too.

---

## Sharing & integrations

- **Per-mic ICS calendar download** (with `RRULE` for recurring) and
  **iCal/Google Calendar subscription** ("subscribe to this mic").
- **Per-hub iCal feed** (subscribe to "all Chicago open mics this week").
- **Public JSON API** at `/mics.json` — throttled, documented; we want to
  be the OpenStreetMap of open mics.
- **Embed widget**: `<script src="https://cocoscout.com/mics/embed.js"
  data-mic-id="..."></script>` — drops a Powered-by-CocoScout card on any
  venue website. Bonus: SEO backlinks from venue sites.
- **Tonight-in-<city> embed**: same idea, for blogs / comedy-club sites.
- **Slack/Discord bots** (stretch): subscribe a channel to a mic's
  "running/cancelled/list-open" updates.
- **OpenGraph share previews** that are **rich and pretty** for every page.

---

## Trust, safety & moderation

- **Audit log per mic** — every field change records who/when/why/source.
  Visible to producers; superadmins see everything.
- **Edit suggestions** from anonymous visitors require email + captcha and
  are rate-limited per IP.
- **Stale-data decay:** if `last_verified_at` is > 90 days, the mic detail
  shows a yellow "Outdated — needs verification" banner with one-click
  re-verify for producers. After 180 days, the mic is greyed in lists.
- **Privacy of contact info:** Producer emails and phone numbers are never
  surfaced publicly. Communication routes through CocoScout messaging
  (which we already have).
- **Anti-spam:** new submissions require email; require a 24-hour cooldown
  before the listing is publicly searchable; flagged content moves to a
  hub-editor review.

---

## Stretch features (deepest thinking — the unfair-advantage stack)

These aren't extras. These are the reasons performers tell their friends
about us.

1. **Sign-up open alerts.** The most-requested feature in the open-mic
   world. Comics live in fear of forgetting when bucket draws open. We
   become the canonical alarm system: per-mic, opt-in, choose web push /
   email / SMS / native push. *Tomorrow's bucket draw at 6pm? You get one
   ping at 5:55.* Massive retention hook.
2. **Bucket draw producer tool.** In-app randomizer that pulls names from
   the bucket, time-stamps it, and produces a tamper-evident log. Solves
   a real producer pain ("did you cheat? show me the list").
3. **"On the way" social signal.** Opt-in "I'm headed there tonight."
   Producers see how many comics expect to attend; performers can see
   familiar names. Privacy-toggleable, defaults to anonymous count only.
4. **My Five Tonight (route planner).** Pick 5 mics tonight; we sort them
   by feasibility, show driving/transit times between them, and warn when
   the lineup is impossible. Hosts on your route get a "she's on her way"
   signal.
5. **Travel mode.** "I'm in Austin Wed–Sat." Filter every page by that
   visitor's window with one click. Massive for touring comics.
6. **Comic set builder & history.** Sign-in users can manage a library of
   bits, log which they used at each mic, and avoid burning the same set
   at the same venue. End-of-year recap ("Wrapped for comics"): 134 mics,
   12 venues, 4h 12m on stage.
7. **Walk-up confidence score.** For mics whose sign-ups are on CocoScout,
   we know how fast lists fill. *"Last week, this list filled in 4 minutes.
   You're going to want to be early."*
8. **Quality / vibes ratings.** 0–5 across four axes. Aggregated only;
   individual reviews require sign-in and reasonable use guards.
9. **Festival & showcase integration.** Festivals can mark which open mics
   they're scouting from. Producers get a badge ("a scout from this
   festival was here last week"). Performers see status: "Showcase
   inviting" / "Open audition tonight."
10. **First-timer mode.** A filter, a tag, and a short "What to expect"
    helper. Mics opt-in to be first-timer-friendly; we feature them when
    a brand-new account browses.
11. **Mic of the week (per hub).** Hand-curated, generated email newsletter
    per city. SEO-rich blog post + share-friendly.
12. **PWA + native push.** Install to home screen; the alerts feature is
    100x better with native push than with email.
13. **Heatmaps.** "Where are the most comics tonight?" Useful for venues
    deciding when to start their own mic.
14. **Lineage tracking.** When a mic moves venues, we preserve continuity.
    Same `OpenMic` record, new `Venue`. Display: "Hosted at the Lincoln
    Lodge 2018–2025, now at the Big Comedy Garage 2025–." Excellent SEO
    asset.
15. **Tip jar / pass-the-hat indicator.** Surfaces which mics tip the
    performer, which require a drink, which are pay-to-play.
16. **Comp/Drop list manager.** Producer tool to confirm who's coming,
    pre-bump who didn't show, drop empty spots to walk-ups.
17. **Open Mic Discoverer feed (RSS).** Per city, per format. Aggregators
    pull from us; we become the canonical registry.
18. **Producer-side: who's hot in your city.** Booking-grade analytics for
    the producer of a top mic — frequency, attendance, average late
    arrivals (for those who want it).
19. **Audience invite shortlink per performer.** "I'm performing at this
    mic Tue — come watch." Counts as conversions, builds an audience.
20. **Year in Review per city.** "Chicago did 7,412 mics this year. Top 5
    spots, average sign-up speed, most active producer." This is press
    bait. We'd want this every December.
21. **Verified host badges.** Known hosts get a checkmark and a unified
    profile across the mics they host.
22. **Multilingual.** Spanish translations of the long-tail hub content for
    LA, NYC, Miami, Chicago. Untapped SEO surface.
23. **Calendar conflict-free planning.** A signed-in performer who already
    favorited a Tuesday mic gets a gentle "overlap" warning when they
    favorite another Tuesday mic at the same time.
24. **"Producers also produce."** When you visit one mic's page, see the
    other mics that producer runs. Like an artist's discography.
25. **"How they sign up" infographic.** A single illustration per
    sign-up-method. Repeatedly useful, link-baity.

---

## Visual design

- **CocoScout pink + white**, our usual Tailwind look and components. Same
  shadow/rounded/border conventions as the existing site.
- **Density on lists**, generosity on the mic detail page. Gmail-tight on
  the inbox-like tonight list; magazine-feel on the detail page.
- **Map style:** light Mapbox base with pink pins. Active mic pins glow.
  Mics happening in the next 60 minutes get a subtle pulse.
- **Empty states** that direct the visitor somewhere useful (nearest hub,
  "suggest a mic," etc.).
- **Loading**: skeleton rows for the list, light shimmer for the map.
- **Accessibility:** WCAG AA contrast, keyboard-nav-able, screen-reader
  labels on map pins, prefers-reduced-motion respected.

---

## Tech sketch

**Same stack as the rest of CocoScout — no new gems, no new providers.**
The full inventory the finder needs is already in `Gemfile`:

- Rails 8 + Postgres
- Hotwire (Turbo + Stimulus) via `importmap-rails`
- Tailwind v4
- Solid Queue (background jobs), Solid Cache (caching), Solid Cable (live
  pushes when we want them)
- `icalendar` — already present; we use it for per-mic and per-hub ICS
- `image_processing` + libvips — already present; OG images later
- Active Storage — already present
- `rpush` — already present; native push for the mobile app, which gives
  us the sign-up-alert delivery channel for free on iOS/Android

### What slots in where

- **Routing.** Public namespace `/mics` on `Mics::PublicController` (and
  siblings: `Mics::HubsController`, `Mics::DetailController`,
  `Mics::SearchController`). Authenticated: `Mics::FavoritesController`,
  `Mics::AlertsController`, `Mics::ProducersController`,
  `Mics::ClaimsController`, `Mics::ChallengesController`. Superadmin:
  `Superadmin::MicsController` for queues.
- **Models.** Land in `app/models/mic.rb`, `app/models/venue.rb`,
  `app/models/mic_*` for the siblings. **No new model duplicates
  `Production` / `Show` / `SignUpForm` — those are referenced via
  `Mic#production_id` (optional).**
- **Map.** Two options, pick at build time:
  - *(default)* **Leaflet via importmap** with OpenStreetMap tiles. Zero
    API keys, no vendor lock, ships as one tiny Stimulus controller. Fits
    the existing JS pattern exactly.
  - *(launch alt)* **No JS map**. Pure server-rendered list + per-venue
    deep links to Google/Apple Maps. Faster, simpler, still SEO-perfect.
    Add the Leaflet view as a progressive enhancement when ready.
- **Geocoding.** Add `lat`/`lng`/`timezone` columns to the new `Venue`
  table. On `Venue` save, enqueue a Solid Queue job that calls the
  **OpenStreetMap Nominatim API** (free, attribution required) via plain
  `Net::HTTP`. No `geocoder` gem — a 30-line service object handles
  cache + rate-limit. (Switch to a paid provider only if scale demands.)
- **Search.** Postgres `ILIKE` over `mics.name`, `venues.name`,
  `venues.city`, `venues.neighborhood`, and (where applicable) the linked
  `productions.name`. Already how the rest of CocoScout searches. No
  trigram extension required at launch; we can add `pg_trgm` later
  without changing the API.
- **Distance / "near me".** Add `lat`/`lng` to `Venue` and use the
  Haversine formula in a small SQL helper (`6371 * acos(...)`). No
  `Geocoder` gem needed.
- **Background jobs (Solid Queue).**
  - Sign-up alert dispatch (precise per-mic; reads `SignUpForm.opens_at`
    when linked, computed from `signup_opens_offset_minutes` otherwise).
  - "Needs verification" nudges to producers on `last_verified_at > 90d`.
  - Sitemap freshness bump on publish.
  - (later) OG image composition on mic update.
- **Caching.** Solid Cache fragment caching for mic cards keyed by
  `cache_key_with_version` plus `last_verified_at`. Full-page Solid Cache
  for hub indexes with a small TTL (~5 min) and surrogate purge on
  producer edits.
- **Public JSON API.** `/mics.json` and `/mics/<slug>.json` — same
  Rails JSON conventions used elsewhere. Pagy for pagination. Rate-limited
  with the same `Rails.cache`-backed throttle we use elsewhere.
- **Alerts delivery.**
  - **Web push** — adding a tiny service worker + `Push API` is the only
    notable new web infra. Falls outside the "no new dependency" rule
    cleanly: it's browser-native, no library required.
  - **Native push (iOS/Android)** — `rpush` already wired for the mobile
    app handles this; we route mic alerts through the same channel.
  - **Email** — existing Action Mailer / `AuthMailer`-style pattern.
  - **SMS** — out of scope for V1.
- **ICS.** `icalendar` gem (already in Gemfile) generates per-mic and
  per-hub feeds.
- **Sitemap.** A controller streaming XML with `render plain:` + ETag.
  Cached by Solid Cache; surrogate-purged on edits.
- **Producer migration wizard.** Lives under `/mics/producer/<slug>/migrate`.
  Server-side service object that, in one transaction: ensures an
  `Organization` exists for the claimer, creates a `Production`, generates
  recurring `Show`s with `event_type: open_mic` from the Mic's
  recurrence, creates a `SignUpForm` covering those Shows, links
  `Mic.production_id`. Existing CocoScout SignUpForm setup screens take
  over from there for any tuning.

### What we deliberately don't add to the Gemfile

- `geocoder` — replaced by a small Nominatim adapter
- `pg_search` — replaced by `ILIKE`
- `sitemap_generator` — replaced by a streaming controller
- `mapbox` / `mapbox-rb` — not needed; Leaflet + OSM via importmap
- `searchkick` / `meilisearch` — not needed at launch
- Any headless-Chrome OG renderer — libvips composes our images

---

## Risks & open questions

1. **Data acquisition cold-start. *Decided.*** Chicago-first, anywhere-can-list,
   hubs graduate in (see *City hubs* above).
   - **Chicago:** hand-curate every active mic, claim what we can pre-launch,
     write the intro, line up a hub editor. Target: a Chicago page that
     beats the best community Google Sheet on day one.
   - **Rest of the US:** open submissions from day one — any signed-in
     CocoScout user can submit a Mic anywhere. New cities materialize on
     the fly as soon as they have a Mic.
   - **Seeding outside Chicago** is *opportunistic, not gated*: where
     public Google Sheets, Discord lists, or partner scenes are willing
     and licit, we ingest. Where they're not, the city stays at "1 mic +
     'submit yours' CTA" until performers fill it in. We don't block
     launch on national coverage.
   - **No imports without explicit permission** from list owners — we
     value our trust posture more than we value a fast number.
2. **Producer claim contention at launch.** Many mics will have no
   claimant. Tolerable — the listing is still useful. Some mics will have
   *two* claimants. Plan for visible queue from day one.
3. **Open data vs lock-in.** The richer our API, the easier for a
   competitor to scrape and copy. We accept this — being the canonical
   data source is a stronger moat than secrecy.
4. **Notification cost.** SMS for sign-up open alerts costs real money.
   Default to web push + email; charge for SMS (or limit to paying
   producers).
5. **OG image rendering load.** Headless Chrome jobs are expensive at
   scale; alternative is a templated SVG → PNG with Vips. We start cheap
   and upgrade if quality bites.
6. **Performer privacy when "on the way" is enabled.** Default to
   anonymized counts; only opt-in to surface identity.
7. **Adjudication labor.** Initially superadmin. Plan to delegate to hub
   editors within the first 90 days.
8. **What about non-US mics?** Out of scope for V1 (the SEO bet is
   US-shaped), but data model is country-agnostic so we can roll into
   other countries cleanly.

---

## What we are deliberately NOT building (yet)

- Ticketing for ticketed shows (we have HotTix elsewhere).
- A full social network (timelines, follower graphs).
- Comedy class / workshop listings beyond a single tag.
- A producer monetization tier (kept simple at launch; door open later).
- International coverage.

---

## Appendix A — full filter taxonomy

Filters available on hub + search pages:

- **When**: tonight / tomorrow / this week / next 7 days / custom range
- **Format**: standup, music, poetry / spoken word, storytelling, magic,
  variety, hip-hop cypher, improv jam, mixed, virtual
- **Sign-up method**: bucket draw, pre-signup (online), walk-up, lottery
  (online), invite-only, hybrid
- **Sign-up status right now**: open · upcoming · closed
- **Cost**: free, drink minimum (with $ filter), pay-to-perform,
  pass-the-hat
- **Spot length**: 3 / 5 / 7 / 8+ minutes
- **Accessibility**: wheelchair accessible, gender-neutral restroom,
  hearing accommodations, no stairs to stage
- **Atmosphere tags**: lgbtq-friendly, first-timer-friendly, family-friendly,
  21+ only, all ages, indoor, outdoor, virtual
- **Venue type**: bar / coffee shop / comedy club / basement / theater /
  online
- **Distance from me**: 1 / 3 / 5 / 10 / 25 mi (or custom)
- **Producer**: filter to one named producer's mics
- **Powered by CocoScout**: yes / no / either
- **Free text search**: matches mic name, venue, host, neighborhood

---

## Appendix B — sample mic detail (for design / copy)

```
Lincoln Lodge Monday Open Mic
Comedy · Standup · Bucket draw
Lincoln Lodge, Lincoln Square, Chicago, IL · Mondays 8:00 PM CT
Last verified by Adam — 2 days ago. Running as planned tonight.

Need to know
- 5-minute spots · 12 spots · Free
- Bucket draw opens 7:30 PM at the bar
- Wheelchair accessible · 21+ · drink minimum

Schedule
Mon May 30  8:00 PM  Running as planned
Mon Jun 6   8:00 PM  Schedule confirmed
Mon Jun 13  8:00 PM  ...

Sign up
Walk in and put your name in the bucket between 7:30 and 7:55 PM.
[Alert me 5 minutes before the bucket closes]

Hosted by
Adam Burke · Mary Lin (@marylinx) ·

Powered by CocoScout sign-ups? No.
If you produce this mic and want to power your signups with CocoScout,
[Claim this mic].

Similar mics
- Tuesday standup, Big Comedy Garage, Logan Square — 2 mi
- Lincoln Lodge Thursday show (booked) — same venue
- Lincoln Lodge Comic of the Year — same producer
```

---

## Build plan

Three blocks. Build top-to-bottom in order. Each block has a clear "done"
bar; only when it's met do we move to the next. No phasing beyond that —
the whole thing is V1.

### Block 1 — Foundation + public site (read-only)

The goal: an unauthenticated visitor can hit `/mics`, land on the nearest
city listing, browse mics, filter, open a detail page, share it, and
subscribe to its iCal — all server-rendered, fast, SEO-perfect.

1. **Migrations + models** (in this order so each step compiles green):
   - `Venue` (name, address1/2, city, state, postal_code, country,
     timezone, lat, lng, neighborhood, venue_type, accessibility jsonb)
   - `Mic` (slug unique, name, venue_id, production_id nullable, status,
     format, recurrence_rule, day_of_week, starts_local_time,
     canceled_until, signup_method, signup_url, signup_opens_offset_minutes,
     signup_opens_at_text, blurb, spot_length_minutes, signup_cap, cost,
     drink_minimum_amount_cents, cover_amount_cents, min_age,
     accessibility jsonb, host_summary, last_verified_at,
     last_verified_by_user_id, claimed_at, lead_producer_user_id)
   - `MicTag` + `mic_taggings` join
   - `CityHub` (slug unique, name, state, intro_markdown, lat, lng,
     default_radius_miles, timezone, status enum, featured_mic_ids jsonb)
   - `MicEdit` audit log skeleton
   - Add `Show.mic_status` enum column (nullable; default nil so other
     event types are unaffected)
   - Geocoding columns on `Venue` are populated by a Solid Queue
     `VenueGeocodeJob` that hits OpenStreetMap Nominatim via plain
     `Net::HTTP` with the required `User-Agent` and 1 req/sec rate-limit
   - Factories for everything above
2. **Slug + recurrence helpers.** A `Mic#to_param` slug strategy
   (`{venue-shortname}-{day}` + collision suffix), a tiny
   `Mic#next_six_occurrences` that handles both production-linked and
   self-described mics.
3. **Routing.** Public namespace under `/mics`:
   - `/mics` (homepage)
   - `/mics/<city-slug>` (city listing — auto or hub-enriched)
   - `/mics/<city-slug>/tonight` `/tomorrow` `/this-week`
   - `/mics/<city-slug>/<format>` (and `/<accessibility-tag>` segment)
   - `/mics/m/<slug>` (detail) + `.ics`
   - `/mics/search`
   - `/mics/sitemap.xml` + `/mics/sitemap-<city>.xml`
4. **Controllers + views.**
   - `Mics::PublicController` (homepage, geo-resolve, search)
   - `Mics::CitiesController` (city listing + hub-enrichment branch)
   - `Mics::DetailController` (mic detail, ICS export)
   - Compact list rows reusing the Gmail-style pattern we already built
     (`shared/messages/_compact_row` style — sender/subject/date but with
     mic shape: name · venue/neighborhood · time).
   - Filter rail (Tailwind, Stimulus where it actually helps; degrade to
     working `<form>` submission).
5. **SEO output, structurally complete.** Title/meta templates,
   `og:`/`twitter:`/`event:` tags, `JSON-LD Event` + `LocalBusiness` +
   `ItemList` + `BreadcrumbList`, canonical, lang tag, `hreflang en-US`.
   Static hub OG image for Chicago + a generic mic template.
6. **Sitemap controller.** Streaming XML, Solid-Cache backed,
   surrogate-purge on Mic save.
7. **ICS export.** Per-mic + per-city, generated with the `icalendar`
   gem already in the Gemfile.

**Done bar:** All of `/mics/chicago/tonight`, a mic detail page, the
sitemap, and `.ics` work for seeded fixture data. Lighthouse SEO ≥ 95.
A signed-out visitor can do their full browse workflow with no JS.

---

### Block 2 — Submission, claims, producers, challenges

The goal: anyone with a CocoScout account can submit a Mic anywhere;
claim a Mic; manage it; invite co-producers; file or respond to
challenges. Hub editors and superadmin have a working adjudication
queue.

1. **Migrations + models.**
   - `MicSuggestion` (anonymous-able edit suggestion; payload jsonb)
   - `MicClaim` (claimant_user_id NOT NULL, status, role,
     proof jsonb, adjudicator_user_id, decided_at, reason)
   - `MicProducer` (mic_id, user_id NOT NULL, role enum, accepted_at)
   - `MicChallenge` (mic_id, challenger_user_id NOT NULL,
     target_user_id, reason text, evidence jsonb, status, adjudicator,
     decided_at, outcome enum)
   - Add `hub_editor` flag on `CityHub` via a `city_hub_memberships` join.
2. **Submission flow** at `/mics/submit`. Sign-in required (uses existing
   `Authentication` concern). Form collects: venue (autocomplete from
   existing `Venue`s; create new if missing), name, day/time, format,
   sign-up method + URL + opens-at description, blurb, accessibility,
   tags. Lands as a Mic with `status: pending`. Drops into the moderation
   queue.
3. **Moderation queue** at `/superadmin/mics/queue` and
   `/mics/hubs/<city>/queue` (the latter for hub editors). One-click
   approve/reject; rejection requires a reason.
4. **Claim flow** at `/mics/m/<slug>/claim`. Sign-in required (auto-route
   logged-out visitors through `/signin?return_to=...`, which already
   works). Form, proof options, status display. Auto-approve when email
   matches a venue-published address; else queue.
5. **Producer dashboard** at `/mics/producer`:
   - List of mics this user manages
   - Per-mic edit form (all Mic fields)
   - One-off occurrence post ("running tonight" / "cancelled tonight" /
     "online-only") — writes a `MicEdit` row + (when production-linked)
     a `Show.mic_status` update
   - Co-producer management (invite by email; uses existing
     `PersonInvitation` flow when the invitee has no account yet — they
     only become a `MicProducer` after accepting)
   - "Mark as last-verified" one-click button (bumps
     `last_verified_at`)
6. **Challenge flow.**
   - `/mics/m/<slug>/challenge` for any signed-in user
   - 72-hour response notification to current lead producer (existing
     `Message` system)
   - Superadmin + hub-editor adjudication view
   - Four outcomes (replace / co-produce / dismiss / request-more-info)
   - Frivolous-challenge throttling (per-user counter, soft block)
7. **Hub editor management.** Superadmin can grant `hub_editor` on any
   `CityHub`. Hub editors see only their city's queues.

**Done bar:** A real test user can submit a mic in a new city, watch it
get approved, claim it, manage it, invite a co-producer, and file (and
adjudicate) a challenge end-to-end.

---

### Block 3 — Migration, alerts, favorites, Chicago go-live

The goal: producers can migrate their Mic to CocoScout-powered sign-ups
in one click; performers can favorite mics and get sign-up open alerts;
Chicago is seeded, hand-curated, and publicly launched.

1. **Migration wizard** at `/mics/producer/<slug>/migrate`. Service
   object `Mics::MigrationService` that, in one transaction:
   - Ensures an `Organization` for the producer (use existing if they
     manage one; otherwise create one and assign them as manager via
     existing `organization_roles` pattern)
   - Creates a `Production` named after the Mic
   - Generates 6 months of `Show`s with `event_type: open_mic` from the
     Mic's `recurrence_rule`, with shared `recurrence_group_id`
   - Creates a `SignUpForm` with `event_type_filter: ["open_mic"]`,
     prefilled timing from the Mic's columns
   - Sets `Mic.production_id`
   - Logs the migration to `MicEdit`
   A nightly Solid Queue job re-projects Shows as the 6-month window
   slides.
2. **"Powered by CocoScout" detection.** A `Mic#powered_by_cocoscout?`
   helper returns true iff `production_id` is set AND there's an active
   linked `SignUpForm`. The badge + the alternate "claim this mic" CTA
   key off this method everywhere.
3. **Favorites.** `MicFavorite` model. Heart button on the detail and row
   partials. `/mics/favorites` list page for signed-in users.
   `Mics::FavoritesController#toggle` is a tiny POST.
4. **Sign-up open alerts.**
   - `MicSignupAlert` model (user_id, mic_id, channels jsonb, lead_time
     minutes default 5)
   - When the Mic is production-linked, alert time =
     `SignUpForm#opens_at` minus lead_time. When self-described, computed
     from the next occurrence + `signup_opens_offset_minutes`.
   - A precise Solid Queue scheduler that enqueues a delivery job at the
     exact target time.
   - Delivery channels: **web push** (new service worker at
     `/sw.js`, `Push API`-based, no library), **email** (existing
     mailer pattern), and **native push** via the existing `rpush` infra
     used by the mobile app.
   - `/mics/alerts` UI for managing them.
5. **Map view (Leaflet via importmap).** Add Leaflet as an importmap
   entry, a single `mics-map_controller.js` Stimulus controller, and
   `/mics/<city>/map`. Cluster pins; pink for active, gray for
   dormant. Pure progressive enhancement — the list view stays the
   primary content. Acceptable to ship Block 3 with the map as a
   second-page link if needed.
6. **Public JSON API.** `/mics.json`, `/mics/<city>.json`,
   `/mics/m/<slug>.json` — versioned, paginated with pagy, ETagged,
   `Rails.cache`-throttled.
7. **Embed widget.** A tiny `/mics/embed/<slug>.js` that injects a
   styled card into any third-party page. Same `Rails.cache` throttle.
   Bonus SEO from venue sites linking back.
8. **Audit log + stale-data nudges.**
   - Show the per-mic audit log to producers (and to superadmin in full)
   - Solid Queue cron: nightly job flags Mics with `last_verified_at` >
     90 days, mails the lead producer; > 180 days, grey them in lists
9. **Chicago seeding.**
   - Hand-curate every known active Chicago mic (target: 50–100 rows)
   - Reach out to known producers, pre-claim where appropriate
   - Write the Chicago hub intro markdown
   - Line up one hub editor; promote the `CityHub` row to active
   - Stage final review on a non-prod URL
10. **Go-live**: route `/mics` traffic, ping the
    sitemap, announce.

**Done bar:** Chicago launches as a top-quality hub. A performer can
favorite a mic, set an alert, get the push notification 5 minutes before
sign-ups open, and tap through. A producer can migrate their mic in one
wizard pass and see sign-ups running through CocoScout. The rest of the
US has open submissions and a working city-listing page wherever a Mic
exists.

---

### Out of V1 (deliberate)

These are in the spec but deferred until the V1 above is shipped and
breathing:

- Bucket draw producer tool · "On the way" social signal · Comic set
  builder + year-in-review · Walk-up confidence score · 4-axis ratings ·
  Heatmaps · Festival integration · Lineage tracking · Multi-language ·
  Travel mode · Attendance check-ins · SMS alerts · Per-mic dynamic OG
  images (we ship static hub-level OG images and the generic mic
  template; the dynamic ones come later)

---

### Pre-launch checklist (run before flipping Chicago)

- [ ] Lighthouse: SEO ≥ 95, Performance ≥ 90 on the Chicago hub and a
      representative mic detail page
- [ ] `robots.txt` allows `/mics/*`; sitemap submitted in Search Console
- [ ] JSON-LD validates with no warnings in Google's Rich Results test
      for the hub, a mic detail, and a city listing
- [ ] OG cards render correctly in Facebook Sharing Debugger, Twitter
      Card Validator, LinkedIn Post Inspector, iMessage preview, Discord
      embed, Slack unfurl
- [ ] ICS files validate in `ical` + import cleanly into Google
      Calendar, Apple Calendar, Outlook
- [ ] Sign-up open alert end-to-end on a real device (web push + native)
- [ ] Claim → adjudicate → producer dashboard happy path on a real
      account
- [ ] Migration wizard happy path on a fresh test account
- [ ] Nominatim attribution rendered per their license requirement
- [ ] `/up` healthcheck still green; Solid Queue dashboard happy

---

## Appendix C — what makes this "the world's best"

A short list to come back to when we're tempted to cut things:

1. **Coverage**: more mics, more cities, more current.
2. **Freshness**: nobody else is "verified by producer 2 hours ago."
3. **Sign-up open alerts**: the killer retention feature.
4. **Sign-up integration**: best-in-class for any mic that wants it.
5. **SEO**: structurally honest, content-rich, perpetually current.
6. **Trust**: claims + challenges + audit log + privacy.
7. **Local soul**: hubs feel like a local zine, not a SaaS.
8. **Speed**: opens like a static site, behaves like an app.
9. **API + embeds**: we become the data source the rest of comedy uses.
10. **Care**: the design feels human; the copy reads like someone who's
    actually done a Tuesday bucket draw at 7:28 PM wrote it.
