# Advanced ticketing: plan (draft 1, 2026-10-29) — release V1.4 (V1.3 is Books)

Canvas (every screen below): https://claude.ai/artifact/Lbh9JQSGVbp7sXFoaJ98Aj

## Scope (Tim, 2026-10-29)
- **In:** 1 reserved seating, 2 season subscriptions and memberships, 3 group sales and holds, 7 the baseline (dynamic pricing, waitlists, PDF tickets, door hardware).
- **Later:** 5 patron CRM and donations ("not ready for that yet").
- **Out:** 4 allocations and consignment, 6 multiple venues and box-office tills.

## Executive summary
Ticketing today is general admission: a count per ticket type, 10-minute checkout holds, passes and deals on one shared checkout (`TicketPurchase`), the Door on a phone, and every dollar through `OrgCashEntry` and `LedgerPosting`. This plan adds four things on top, without changing those seams:

1. **Seats.** A chart per room (`LocationSpace`), and reserved shows where ticket types become price zones. The database itself stops two people getting one seat.
2. **Seasons.** Subscriptions are fixed-seat dated passes that renew. Memberships are a yearly level that gives member prices and an early on-sale.
3. **Groups.** Seats held for a school or company, paid on an invoice (card, bank or check), released automatically if unpaid.
4. **Baseline.** PDF tickets, a waitlist that offers returned seats, pricing rules the manager writes, and scanners, printers and readers at the door.

**Order:** PDF tickets → waitlist → groups (general admission) → seating → pricing rules → memberships → subscriptions → door hardware. Each step is useful on its own; seasons wait for seats because a subscription's whole point is the same seat every time.

Everything stays inside Pro and the Ticketing module (managers only). There is no Enterprise tier in code, only marketing copy; see decision D1.

---

## Seams this plan respects
- `Ticketing::Inventory` is the only seat counter. It gains seat awareness; nothing else counts seats.
- `Ticketing::ListingPayload` is the only listing description. It gains `seating` and zones.
- `TicketPricing.quote` is the only fee math: 50¢ per paid ticket, processing at cost once per checkout, buyer-pays or absorb, all-in display.
- `TicketOrderSettlement` → `OrgCashEntry` + `LedgerPosting` is the only way ticket money lands. Groups and seasons create ordinary `TicketOrder`s, so the door, refunds, Show Financials, contract splits and the money release keep working.
- `TicketOrderRefund.policy_check` stays the refund gate; "sold" stays `TicketListing#worth_keeping?`.
- Emails render from `TicketingTemplates` / seeded ContentTemplates; PDFs and sends run in jobs.

---

## 0. Locations and rooms (organization level), revised 2026-10-29

Tim, 10/29: seating starts with the room, and "rooms and locations don't just affect ticketing", so they have to be defined properly at the organization level first.

**Today:**
- Organization settings → Locations → a location (address, notes) with "spaces" (name, description, capacity, one default), edited in pop-up windows.
- Shows, rental contracts (`space_rentals`, where an empty room means "Entire venue"), classes, auditions (location only), staffing lines and ticketing all read them.
- Ticketing never uses a room's capacity.

**The rule (Tim, 10/29):** rooms belong to every plan. A Producer-tier organization uses them for shows and events and never sees tickets. **Nothing on a room may depend on ticketing (or any Pro module); ticketing depends on rooms, never the reverse.** No ticketing columns go on `location_spaces` or `locations`, and the room's pages and models never read ticketing tables.

**Changes (free, every plan):**
- **Say "rooms"** in every screen and email (the model stays `LocationSpace`). Contracts already say rooms.
- **Every location has at least one room.**
  - A new location starts with "Main room".
  - Existing locations with no rooms get one in a backfill.
  - A show with a location but no room lands in the location's default room.
  - "Entire venue" stays, for rentals and buyouts, and keeps its overlap rule.
- **A room gets its own page** instead of a pop-up: Organization settings → Locations → location → room. It has:
  - Details: name, description, **most people allowed** (today's `capacity`), step-free entrance, default room.
  - **Coming up in this room:** shows, events, rehearsals, classes.
- **The location page lists rooms as rows** with their limit and what's next. The Locations list shows each location's rooms at a glance.
- **Pro modules add cards, not dependencies.** On a Pro organization, Ticketing and Contracts may render their own card on the room page (a seating summary; rentals), from their own partials and only when the organization has that module. The room page offers a slot; it never reads those modules' data itself.

**Size: M** (the rename, room pages, the backfill). Build it first; nothing in ticketing changes yet.

### Ticketing's side of a room (Pro, in Ticketing → Settings → Rooms and seating)
- **`room_ticketing_settings`:** organization, `location_space_id` (unique), `seating_mode` (general/reserved/mixed, default general), `default_seat_chart_id`, `buyer_directions` (on the show page and the PDF ticket). Created lazily, like `TicketingProfile.for`.
- **Charts** (`seat_charts`) point at a room and are owned by Ticketing. Deleting a room is refused while a chart or listing uses it (ticketing's foreign keys restrict). The room model declares no association to them.
- **Capacity:** ticketing reads the room's "most people allowed" to cap a general admission show unless the production sets its own counts. Today's tier counts still win.

## 1. Seating: general admission, reserved or mixed

**The job:** a 200–2,000-seat room sells better seats for more and lets people choose. The box office needs house seats, accessible seats handled lawfully, and a door that tells ushers where people sit.

**How others do it:** Tessitura, Spektrix and AudienceView ship deep seat-map tools (graphical editors, price zones by performance, hold codes, best-available algorithms). Ticket Tailor and Eventbrite license or build simpler grid charts. Most small platforms license Seats.io.

**Recommendation: build our own.** Our rooms are rows, cabaret tables and standing areas, all of which a grid editor handles. Owning the seat rows keeps holds, the door, groups and subscriptions in our database, and avoids a second per-ticket charge on top of our 50¢. Curved rows and a free-draw background come later, only if a customer needs them.

### Three ways to sell, decided room → production → date
- **General admission:** sold by count, no chart.
- **Reserved:** every ticket is a seat.
- **Mixed:** a chart with standing areas sold by count and seated sections sold by seat. Example: a floor of 1,000 standing and 2,000 reserved seats above.

**The chain:**
- The room's ticketing settings (`room_ticketing_settings.seating_mode` and default chart).
- Then `production_ticketings.seating_mode` / `seat_chart_id`: nil means each room's default, the recommended setting.
- Then `ticket_listings.seating_mode` / `seat_chart_id`: nil means follow the production.
- The `effective_*` resolvers extend as they do today (listing → production → room).

A chart's kind is derived from its contents: all seats = reserved, any standing area = mixed. Mode and chart must agree, and the pickers filter to match.

**Changing one date after sales:**
- Allowed only if every sold seat exists on the new chart.
- Otherwise the page lists who must be moved, and the seat map opens to move them.
- Going to general admission keeps every ticket and drops seat numbers, after an email preview.

### Data model
- **`seat_charts`:** organization, `location_space_id` (drawn for that room; Ticketing owns it), name, status (draft/active/archived), `lock_version`. They live in Ticketing settings; the room never references them.
- **`seat_sections`:** chart, name, kind (`rows`/`tables`/`standing`), position, `standing_capacity` (standing only), `best_order` (center-out or front-back).
  - A standing section is a price zone sold by count.
  - Tickets gain `seat_section_id` alongside `seat_id`, and Inventory counts standing tickets against `standing_capacity` inside the same listing lock.
- **`seats`:** section, `row_label`, `number`, `label` ("C 14"), `x`, `y`, `kind` (standard/wheelchair/companion/restricted_view), `note`, `best_rank`, `killed` (boolean).
  - A seat that is on any live ticket can't be deleted, only killed for future dates.
- **`production_ticketings` and `ticket_listings`:** `seating_mode` (`general`/`reserved`/`mixed`) and `seat_chart_id`, nil = inherit. The chain starts at `room_ticketing_settings`; `location_spaces` gains nothing.
- **`ticket_tier_zones`:** a tier (the price zone) and its seats by section and rows, resolved to seat ids. Discount ticket types (Student, Senior) stay tiers flagged `discount_of_zone`, valid in chosen zones.
- **`ticket_seat_holds`:** `production_ticketing_id` or `ticket_listing_id`, name, kind (house/accessible/group/subscription/outside_sale/manual), `release_at`, `release_rule` (time / when the rest of the zone sells out), owner (polymorphic: a group booking or a subscription).
  - **`ticket_seat_hold_seats`:** hold, listing, seat. Unique on (listing, seat).
- **`tickets`:** gain `seat_id` and a denormalized `ticket_listing_id`.
  - A partial unique index on (`ticket_listing_id`, `seat_id`) where status is in (reserved, valid, checked_in) means **the database refuses a double sale**.
  - Stale reserved tickets from lapsed holds are voided inside `Inventory.reserve!` before inserting. The 10-minute scope alone isn't enough once the index exists.

### Inventory
`Inventory.for(listing)` branches on `seating_mode`.
- **Reserved:** capacity = live seats + standing capacity; taken = tickets with seats + held seats + outside sales.
- `remaining(tier:)` = free seats in that zone.
- `reserve!` keeps the listing row lock. Requests carry `seat_ids`, or `best_available: n`.
- **`Ticketing::BestAvailable`:** a contiguous block in one row of the zone, lowest `best_rank`. It never leaves a single empty seat when the setting is on. If there's no contiguous block, it falls back to the nearest seats with "not together" shown.

### Buyers
- The show page's ticket picker becomes a map for reserved shows: SVG from seat x,y, statuses from a cached JSON endpoint, pinch zoom, tap to pick.
- A Best available tab. Prices all-in on the legend.
- The hold clock and checkout are unchanged; checkout and the ticket page show seat labels.

### Managers
- **Ticketing → Settings → Rooms and seating:** each room's way of selling, its charts, the editor (add a section of rows, tables, standing; mark wheelchair, companion, restricted, kill), and buyer directions.
- **Production → Settings → Seating:** pick the chart, set zones and prices, set holds on every date.
- **A show's Seat map tab:** comp, hold, sell at the box office; click a sold seat to move or refund it. A move keeps the QR code and sends "Your seats changed".

### Accessible seating (ADA, 28 CFR 36.302(f))
- Accessible seats are sold at every price zone.
- They're held for people who need them and released only when the rest of their zone is sold out.
- A companion seat sells with them. Buyers attest at checkout.

### Door
- A scan shows section, row and seat, and wrong-date tickets say which date they are for.
- Door sales pick seats (Best available, or tap the map).
- Party check-in is unchanged.

### Refunds and exchanges
- A refund frees the seat (and the waitlist hears).
- `TicketOrderExchange` picks seats on the target date.
- The same-price-or-less rule is unchanged.

### Reports
- Sold by zone.
- A seat heat map across dates (which seats sell first).
- Holds released vs used.

### Outside sites
On a reserved show, a `TicketOutsideSale` count must take real seats. The manager picks them, as an `outside_sale` hold.

**Size: XL**, built in three parts:
- 1a. model, inventory, index, manager seat map (L);
- 1b. buyer map, best available, door (L);
- 1c. editor polish, tables, standing (M).

---

## 2. Season subscriptions and memberships

**The job:** sell the season up front (cash and commitment in the spring), keep subscribers in the same seats year after year, and reward regulars with prices and first access.

**How others do it:** Tessitura and Spektrix treat subscriptions as packages with seat retention and renewal windows, and memberships as constituent levels with benefits and priority windows. PatronManager does the same on Salesforce.

### 2a. Subscriptions: fixed seats, a season, renewal
**Model:** extend Round 7's `TicketPass` with kind `subscription`. It is a dated pass whose dates come in **series**.
- **`ticket_pass_series`:** pass, name ("Saturday night"), position.
- **`ticket_pass_series_shows`:** series, listing. Filled in from each production's dates by weekday and week of the run; editable.
- **Price per zone:** `ticket_pass_zone_prices` (pass, zone name, `price_cents`). Per-show shares by regular price, as `TicketTier.split` does today.
- **`ticket_subscriptions`:** the subscriber's standing record.
  - Columns: organization, pass, series, buyer name/email/phone, `follower_id`, `seat_ids` (the same labels on every date), quantity, status (active/renewal_open/renewed/released/canceled), `renewed_to_id`, `token`.
- **Buying:** one `TicketPurchase` with one order per show (exactly as dated passes work), each ticket on the same seat. Best available runs over the **intersection** of free seats across every date in the series. All dates in a series must share one chart; the editor enforces it.
- **Renewal:**
  - Making next season's pass with "renews from 2027 Season" creates a `subscription` seat hold on every date of each subscriber's series, `release_at` = the renewal close.
  - Renewal emails go out (14 and 3 days before close) with the token link.
  - Renewing checks out those held seats.
  - "Ask for better seats" is a request the box office works before the close.
  - Unrenewed holds release the next day; the waitlist and the public get them.
- **Perks:** free exchange to another date of the same production (an exchange-fee waiver flag on the order); extra tickets at the member price.
- **Money:** unchanged from dated passes. Each show's order settles into that show's advance sales and releases the day after it plays. 50¢ per show admitted.
- **Refunds:** reprice-what-they-keep (Round 7 D) applies as is.

### 2b. Memberships
- **`ticket_membership_levels`:** organization, name, `price_cents`, `period_months` (12), `discount_percent`, `presale_days`, `free_exchanges`, status.
- **`ticket_memberships`:** level, holder name/email, `follower_id`, `starts_on`, `ends_on`, status (pending/active/expired/canceled), token, money columns (like `TicketPassHolding`).
- **Buying:** a page at `/tickets/:org/members`. Checkout is a `TicketPurchase` with no show. The holding pattern is the same as a credit pass.
- **Proving membership** (buyers have no accounts):
  - "Enter your member email", then a 6-digit code by email, then a signed per-organization cookie for 30 days.
  - At checkout the discount applies as `discount_cents` (like a code; no stacking with codes).
- **Presale:** `ticket_listings` gain `members_on_sale_at` (derived: `on_sale_at` minus the level's `presale_days`, overridable). During the window, only verified members can start a checkout.
- **Money:** dues post as a new income account, **Membership dues**, at purchase (cash basis, like everything today).
  - The fee on a membership is decision D4.
  - If dues include benefits and the organization is a nonprofit, part may be a gift. That waits for donations (item 5).
- **No auto-renew charges in the first cut:** renewal reminders at 30 and 7 days, and a one-tap renew link.

**Size:** memberships **M**; subscriptions **L** (needs seating).

---

## 3. Group sales and holds

**The job:** schools and companies book 20–200 seats weeks ahead, pay by invoice (often by check or bank), name people late, and sometimes never pay.

**How others do it:** Tessitura and AudienceView run group sales as orders on hold with payment plans and invoices; Ticketmaster has group desks. Small platforms mostly email the box office.

### Data model
- **`ticket_group_bookings`:**
  - Who: organization, listing, name, contact name/email/phone.
  - Seats: `seat_count`, `comp_count` (chaperones), `price_cents` per seat.
  - Money and dates: `fee_mode` (default org: the invoice is a round number), `deposit_cents`, `due_on`, `release_on`, `names_due_on`.
  - State: status (draft/held/invoiced/part_paid/paid/ticketed/released/canceled), `token`, `ticket_order_id`.
- **Seats:**
  - Reserved show: a `ticket_seat_holds` row of kind `group` owned by the booking.
  - General admission: Inventory gains **quantity holds** (`ticket_quantity_holds`: listing, tier, quantity, owner), counted in `taken`.
  - Either way, Inventory is the only counter.
- **Invoice:** generalize Round 6's contract invoicing.
  - The numbering counter, `InvoiceDocument`, `InvoicePdf` and `ContractInvoiceDelivery`'s send, remind and receipt all become payable-agnostic.
  - A group's invoice is `INV-…` from the same sequence.
- **Payments:** `ticket_group_payments` (booking, amount, method card/bank/check/other, stripe ids, `received_at`).
  - Card or bank via a Checkout Session on the leader's page (like `/pay/contract/:token`).
  - Check: recorded by the box office ("Record a check"), books-only like door cash.

### Turning payment into tickets
When paid in full (or by the box office's "Issue tickets now" for trusted groups), one `TicketOrder` is made:
- channel `group`, `money_path` cocoscout (card/bank) or `external` (check);
- tickets on the held seats;
- `TicketOrderSettlement` posts money, books and Show Financials.

A deposit sits as a "Group deposits" liability until tickets issue. 50¢ per paid ticket; comps free.

### Release
`GroupHoldReleaseJob` runs daily:
- warns the leader and the managers 3 days before `release_on`;
- on the day, releases the seats, marks the booking released, and tells the waitlist.

### The leader's page (`/tickets/group/:token`)
- invoice and PDF;
- pay by card or bank;
- add names (paste a list, upload a spreadsheet);
- once paid, download all tickets as one PDF or email each person.

Unnamed tickets show at the door as "Lincoln Park HS guest".

### Refunds
- Per ticket through `TicketOrderRefund` (fewer students come).
- A deposit on a released booking is kept or refunded by the manager's choice, under the refund policy.

### Bank payments
Schools pay by bank. Ticket checkouts keep ACH off; group invoices would use a separate payment-method configuration, as payout funding does. Decision D5.

**Size: M** (general admission first), then seats when 1a lands.

---

## 7. Baseline

### 7a. PDF tickets (S)
- `TicketPdf` (Prawn, which is already in the bundle): one page per ticket, with the QR (rqrcode) and the seat.
- Attached by `TicketOrderConfirmationJob`; a download on the order page and the ticket page.
- A bulk PDF for groups, and a 2×5.5 in thermal layout for printers.
- Setting: Ticketing → Settings → Box office "Attach PDF tickets" (default on).

### 7b. Waitlist (M)
- **`ticket_waitlist_entries`:**
  - Who: listing, name, email, phone, quantity, preference (any/zone/together), position.
  - State: status (waiting/offered/bought/missed/removed), `offer_expires_at`, `offer_order_id`, token.
- **Joining:** only when the date is sold out (`Inventory#sold_out?`) and the production has the waitlist on (Settings → Sales).
- **Offers:**
  - `WaitlistOfferJob` runs on every seat-return event (refund, hold release, group release, subscription release, exchange, lapsed checkout) and every 5 minutes as a sweep.
  - Seats are held for the first entry whose party fits, as a pending `TicketOrder` with a **longer hold** (`expires_at` = offer window, default 30 minutes; `HOLD` becomes a per-order value).
  - The offer is sent by email (text only if we add an SMS provider).
  - A missed offer passes to the next person.
- **Manager:** a show's Waitlist tab with counts, the list, offers out, and "email the list about another date" (preview-before-send).

### 7c. Pricing rules (M)
- **`ticket_price_rules`:**
  - Scope: `production_ticketing`, position, enabled.
  - Condition: `condition` (sold_pct_at_least / days_out_at_most / sold_pct_below_by_days_out), `threshold`, `days`.
  - Change: target tier/zone or all, `change_kind` (amount/percent), `change_value`.
- Tiers gain `price_floor_cents` and `price_ceiling_cents`.
- **One function:** `TicketPricing.current_price_cents(listing, tier)`. The first matching rule wins (top to bottom), clamped to the floor and ceiling.
  - `ListingPayload`, the show page, checkout and the door all call it.
  - Tickets already store `price_cents` at hold time, so **a price never moves inside a checkout**.
- **Never repriced:** subscribers, groups, comps, passes; they don't read tier prices at sale time.
- **Never refunded:** a price going down never refunds earlier buyers.
- `TicketPriceChangeJob` logs each flip to `ticket_price_changes` for the date page and Reports.
- No algorithmic pricing; rules the manager writes, with a preview ("Right now").

### 7d. Door hardware
- **Scanners (S):** Bluetooth and USB scanners type the code like a keyboard. The Door gets an always-focused input that accepts a full `/tickets/v/<code>` URL or a bare code (already parsed by `TicketDoor#check_in`). The native apps forward hardware-keyboard input the same way. We publish a "tested scanners" list.
- **Printers (L):** Star (StarXpand SDK) and Epson (ePOS SDK) bridge components in iOS and Android. They print the thermal layout from 7a at a door sale or on check-in. Pairing lives in Settings → Door hardware.
- **Card readers:** Tap to Pay is live. A countertop reader (the payment provider's Terminal readers) comes later, on the same in-person rate, when a box office asks.

---

## Cross-cutting
- **Gate (D1):** all of this is Pro, in the Ticketing module, managers only (`PaidFeatureGate` already maps `manage/ticket*`). Group leaders, subscribers and members use token pages, as buyers do today.
- **Concurrency:**
  - The listing row lock plus the seat unique index plus `reserve!`'s void-stale-first step.
  - Multi-date reserves (subscriptions) lock listings in id order, as passes do.
  - Seat-map JSON is cached per listing and busted on any ticket or hold change.
- **Performance at 2,000 seats:**
  - The map payload is about 2,000 small entries (about 60 KB gzipped), statuses from one query per listing.
  - Best available is in-memory over one zone.
  - The lock is held for milliseconds.
  - An on-sale-rush queue is out of scope until a customer needs it.
- **Migrations:** all additive; general admission stays the default; no backfills. A pilot organization draws its chart first.
- **Books:** new accounts are Membership dues (income) and Group deposits (liability). Everything else uses existing accounts.
- **Emails (seeded templates):** seats changed; waitlist offer and missed; group invoice, reminder, release warning and tickets; subscription renewal invite and reminders; membership receipt and renewal reminder; member code.
- **Reports (Ticketing group):** zone sales and seat heat map; subscriptions and renewal rate; memberships; groups by state; waitlist take-up; price-rule changes.

## Sequencing
| Step | What | Size | Needs | Why here |
|---|---|---|---|---|
| 1 | PDF tickets | S | — | **Done 2026-10-29 (da676ed1)**; off by default, each organization turns it on |
| 1b | Locations and rooms (§0) | M | — | Organization-wide; seating builds on it |
| 2 | Waitlist (general admission) | M | — | Helps sold-out shows today |
| 3 | Groups (general admission) | M | 1; invoice generalization | Sellable now to schools |
| 4a | Seating: model, inventory, manager seat map | L | — | Foundation |
| 4b | Seating: buyer map, best available, door, exchanges | L | 4a | Seats go on sale |
| 4c | Seating: editor polish, tables, standing | M | 4a | Cabaret rooms |
| 5 | Pricing rules | M | — (zones after 4a) | Independent |
| 6 | Memberships and presale | M | — | Independent |
| 7 | Subscriptions and renewal | L | 4b, 6 | Fixed seats need seating |
| 8 | Scanners, then printers | S, then L | 1 | The native work batches with the next app release |

Steps 1, 2, 3, 5 and 6 can be sold as soon as each ships. Seating and subscriptions are the long pole.

## Decisions (Tim answered 2026-10-31)
- **D1. Tier:** all in Pro. "Enterprise" is a support and onboarding offer, never a feature gate.
- **D2. Seat map:** build our own editor and buyer map.
- **D3. Subscriptions:** pay in full; renewal by invitation. No auto-renew, no payment plans in the first cut.
- **D4. Fee on a membership:** 50¢ when a membership is bought or renewed, exactly like a ticket. Tim's rule, in one sentence: **every sale through our checkout costs the organization fifty cents.** Member tickets carry their own 50¢ each.
- **D5. Bank transfer on group invoices:** yes, $500 and up, through the separate bank-debit payment-method configuration; seats stay held until the transfer clears. (Tim confirmed.)
- **D6. Waitlist notices:** email only; texts when an SMS provider arrives. (Tim confirmed.)
- **D7. Member identity:** an emailed 6-digit code and a 30-day per-organization cookie; no account. (Tim: "emailed code for sure.") **Build the code flow as a buyer sign-in, not a one-off check:** the same code and cookie are the key to a **buyer hub** later (Tim, 10/31: a place where a person comes back to see their membership and the tickets they bought, instead of today's loose per-order pages). The hub itself is 1.6 (My tickets); 1.4 ships the members page showing the membership and its perks, and keeps the verified-email session reusable so 1.6 only adds pages behind it.

### Memberships are a menu (Tim, 2026-10-31)
A membership level is **defined by the organization from a menu of perks**, each on or off with its own setting; nothing is bundled in by default, and two organizations' memberships can differ entirely. The menu, first cut:
- a percentage off tickets (`discount_percent`);
- early access, N days before public on-sale (`presale_days`);
- free date exchanges (`free_exchanges`);
- **better seats:** best-available picks from the top zone, or from a members-only block of held seats (needs seating, step 4a);
- **free section upgrade:** one zone up at no charge, when on for the level (needs seating, step 4a);
- room for more later (a free drink, a guest ticket) as ordinary perk rows.
Model it as `ticket_membership_perks` (level, kind, settings jsonb) or typed columns per perk on the level; either way the level page is a checklist, and the checkout, the seat picker and the exchange flow each ask the level "do you grant X?".

## Risks
- **The editor grows forever.** Keep it to rows, tables and standing, with an x,y nudge; no free drawing.
- **ADA:** accessible-seat release rules and companion seats must be right on day one. Have a lawyer read the buyer attestation copy.
- **Dynamic pricing perception:** rules are visible to managers, prices stay all-in, nothing changes mid-checkout.
- **Membership dues and nonprofit gift rules:** wait for donations; no tax-receipt language until then.
- **Seat index vs. stale holds:** covered by voiding stale reservations inside the lock. Specs must race two checkouts for one seat.

## Won't do
- Allocations, consignment, outside box offices.
- Multi-venue tills and cash drawers.
- Donations (later).
- Algorithmic pricing.
- Resale or transfers marketplace.
- A licensed seat map.
- Auto-charging renewals (first cut).

## §Build log (branch `v1.4`, built 2026-10-31)

One line per step: the commit, and what was simplified against the plan above. Scanners and printers (step 8, native) are left out until Tap to Pay ships. Accessibility is the accessibility plan's §1, §2 and §4 (`~/.claude/plans/cocoscout-accessibility.md`).

- **PDF tickets** — da676ed1 (on main, 2026-10-29). Default off; the order page's download always works.
- **1b. Rooms rework** — 4722854e. Every location has a room; each room has a free page; Ticketing keeps its per-room seating in `room_ticketing_settings`.
- **2. Waitlist** — c259d7b9. By email only (D6).
- **3. Group sales** — c89e5029. Group bookings on invoices (1.3's), bank transfer at $500+ (D5). Simplified: no group deposits or group refunds; holds are per date only (no production-level holds); no per-person group ticket emails.
- **4a. Seating model, inventory, editor** — 9369040f. Charts drawn per room, zones per ticket type, the inventory counts seats, a date's seat map with holds. Simplified: no seat-map JSON cache (the payload is built per request).
- **4b. Buyer map, best available, door, moves, exchanges, accessible holds** — aee31ecd. Simplified: the door picks seats best-available only (no map at the door); accessible seats are kept until the rest of the zone is gone, then offered.
- **4c. Tables, standing room, editor polish** — 35ec2c83. Tables drawn as tables, standing sections sold beside the map, a date's chart kept once seats are sold, seating in the listing payload. (The 4b/4c request spec `seating_sales_spec.rb` landed empty in those commits and was restored in a58e73fc.)
- **5. Pricing rules** — 44fa2bf1. A ticket type's price moves as a date sells or draws near, within its floor and ceiling; first matching rule wins; every flip logged hourly (`ticket_price_changes` job). Simplified: rules apply from the production even on dates with their own prices; the change log shows on the Pricing tab only, not the public date page.
- **6. Memberships** — 18409a64. Levels are a menu of perks (discount, presale days, free exchanges, better seats, section upgrade, extras); bought on `/tickets/:org/members`, paid like a credit pass, 50¢ on each purchase and renewal (D4); members sign in with an emailed 6-digit code and a 30-day per-org cookie (D7, reusable `VerifiedBuyer`). Simplified: "better seats" is the members-only seat block only (no "top zone" variant); "free exchanges" is informational (CocoScout charges no exchange fee; buyer self-service swaps are 1.6); memberships carry no tax lines; the member discount never stacks with a code; no membership refund screen (cancel only); the member price shows without a fee breakdown.
- **7. Subscriptions and renewal** — a58e73fc. A pass of kind "subscription" keeps each buyer in the same seats at every date (one chart across the dates), picked on one map or best available across the season; renewal by invitation (D3): next season's pass "renews from" last season's, every subscriber's seats are held on the new dates until the close, an emailed Renew link, reminders 14 and 3 days before, holds let go at the close (`MembershipSweepJob`). Simplified: one pass per series (no series table); subscriber perks (free exchanges, member extras) not built; "different seats" is handled by replying to the renewal email; no partial renewals (same quantity as last season).
- **Accessibility profile and per-performance notes** — 0c42eabb. §1: `AccessFeatures::CATALOG` (19 features, five groups), `access_answers` on locations and rooms (rooms inherit, "same as the location" until changed), room-only facts (wheelchair spaces and where, stage access, floor), who to ask, `AccessProfile` summaries for guests and for performers and crew, screens on the location and room pages. §2: `show_access_services` with details and content notes on productions and shows, labels on public date rows. §4: the show page's one quiet "Accessibility" line and pink pop-up, the room's access guide at `/tickets/:org/access/:room` (linked from the confirmation email and the PDF), checkout's "Any access needs for your visit?" pop-up saved as `ticket_order_access_requests` and shown to the box office list and the door only (tonight's list, the scan result, the party row), purged 30 days after the show (`PurgeAccessRequestsJob`, daily). Simplified: no access photos; §3 (performers and crew: audition and call pages, private access needs) not built; general-admission held places by count not built (reserved charts hold wheelchair and companion seats as in 4b); no "access request received" notification; no chart-editor warning when wheelchair spaces don't match the room's count; no "interpreted / captioned / relaxed dates" filter on the embed widget.
- **Phone-width pass** — 61 pages the 1.4 request specs visit, rendered with the branch's Tailwind build at 375px: none wider than the screen; no fixes needed. (Seat maps are drawn by Stimulus and were not part of the static measure.)
- **Recurring jobs added:** `ticket_price_changes` (hourly), `membership_sweep` (daily, memberships and subscriptions), `purge_access_requests` (daily).
