# Next up

Tim's running list while the apps are in review (started 2026-10-19). Tick
things off here; the app roadmap itself stays in CLAUDE.md.

## Today

- [x] Deploy the weekend's batch (where a ticket type sells, box office page settings).
- [x] Burlioke: "Reserve a spot" $15 online only, "At the door" $20 door only.
- [x] Box office page: welcome line, wide image, layout.
- [x] Drop the old `contract_service_options` table (8be7344c).
- [x] Ticketing page: Coming up is Upcoming / Past, past dates newest first with their numbers (f4b91e4c).
- [ ] Contract people move: the dry run found nothing on active contracts; run the diagnostic block, then the move.
- [x] Payee details: synced 104 payees, 91 have details coming due; the heads-up shows on My → Payments once someone's been paid $2,000.
- [ ] Show time drift: 55 shows sit 11 to 60 minutes before their booking's event time (list in the 2026-10-19 chat); decide which clock is right per production, then run the fix block.
- [ ] **SEND APPLE THE TAP TO PAY PACKAGE.** Reply to Apple's Oct 12 email (Case-ID 22828656) with the three videos and the checklist (`ios/tap_to_pay.md`). Tap to Pay (V1.2) can't ship until Apple answers, and Apple's review takes a week or two.

## Soon

- [ ] Reports → Ticket Sales by Show: count other sites too, as Attendance does.
- [ ] V1.1 (was V2): production mode + new navigation on its own branch; never deployed until both app reviews pass. Carries the per-build path config and user-agent marker.
- [ ] V1.2 (was V1.1): Tap to Pay on its own branch; ships when Apple grants the publishing entitlement.
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
