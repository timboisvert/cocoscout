# Next up

Tim's running list while the apps are in review (started 2026-10-19). Tick
things off here; the app roadmap itself stays in CLAUDE.md.

## Today

- [x] Deploy the weekend's batch (where a ticket type sells, box office page settings).
- [x] Burlioke: "Reserve a spot" $15 online only, "At the door" $20 door only.
- [x] Box office page: welcome line, wide image, layout.
- [x] Drop the old `contract_service_options` table (8be7344c).
- [x] Ticketing page: Coming up is Upcoming / Past, past dates newest first with their numbers (f4b91e4c).
- [ ] Contract people move: run the dry run in prod, read the table, then run it for real.
- [ ] Payee details: run the sync block in prod so people already set up get the heads-up when they're near $2,000.
- [ ] Show time drift: run the listing loop across every contract show; fix any that drifted.

## Soon

- [ ] Reports → Ticket Sales by Show: count other sites too, as Attendance does.
- [ ] V1.1 Tap to Pay on its own branch (and request Apple's Tap to Pay entitlement if not yet).
- [ ] V2 production mode + new navigation on its own branch; never deployed until both app reviews pass.
- [ ] Books, stages B to F (`docs/accounting_books_plan.md`), one phase at a time.

## Waiting on

- [ ] Apple: App Store Connect → CocoScout → 1.0 status.
- [ ] Google: Play Console → Publishing overview.

## Done this weekend (for the record)

Ticket visibility for staff, production teams and cast; comps rules; discount code sharing;
the Attendance roll-up; the Productions list as rows; the two-letter monogram; the Contract box;
where a ticket type sells; the box office page and its two layouts; the door redesign (Work the
door, organization chooser, tonight only, "checked in"); the amend chooser and discard/unsign;
a contract date's one clock; the single ticket page.
