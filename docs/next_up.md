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
- [ ] Impersonate Dan Feltey and Andy Nash and look at what they see (My → Payments, My Contracts, Ticket Sales), after today's email from our payment provider.
- [ ] Tap to Pay on Android: get ready (see "Tap to Pay on Android" below).
- [ ] **Tap to Pay on iPhone (V1.2): Apple's publishing approval.** In order:
  1. [x] Tim: Apple's checklist and guide into `ios/apple_ttp/` (done 10/19).
  2. [x] Tim: Apple's Marketing Toolkit into `ios/apple_ttp/` (done 10/19).
  3. [x] Claude: build what Apple requires, on main behind Debug builds and a per-organization switch, and write the shot lists and checklist answers (done 10/19, in `ios/tap_to_pay.md`).
  4. [ ] Tim: deploy main, switch Tap to Pay on iPhone on for Stars & Garters (Ticketing settings → Door → Manage), and run the app on your iPhone from Xcode.
  5. [ ] Tim: film the three videos with a second phone, in this order: existing user, new user, checkout ("Before filming" and the shot lists in `ios/tap_to_pay.md`).
  6. [ ] Tim: fill Apple's checklist from the answers in `ios/tap_to_pay.md` and reply to the Oct 12 email (Case-ID 22828656) with the videos, the checklist and the exception request (the reply is drafted there too). Apple's review takes a week or two from then.

## Soon

- [ ] Reports → Ticket Sales by Show: count other sites too, as Attendance does.
- [ ] V1.1 (was V2): production mode + new navigation on its own branch; never deployed until both app reviews pass. Carries the per-build path config and user-agent marker.
- [ ] V1.2 (was V1.1): Tap to Pay on iPhone, on main behind Debug builds; the Release build registers it once Apple grants the publishing entitlement.
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

## Tap to Pay on Android

No approval from Google or the payment provider: it ships with a normal Play review, so it can go out before Tap to Pay on iPhone.

- The app adds the payment provider's Terminal SDK with its Tap to Pay module (`stripeterminal-taptopay` and `stripeterminal-core` 6.0.0) and the `MODIFY_AUDIO_SETTINGS` permission. The server side (connection tokens, the location, settling the sale) is the one already built for iPhone.
- Phones: Android 13 or later, NFC, not rooted, Google Play installed, a security update from the last 12 months, and **Developer options turned off**. That last one means testing can't be over a USB cable: install test builds from a Play internal testing track. No emulator.
- Most recent Pixels and Samsung Galaxy phones qualify. Tim needs one such phone to test on.
