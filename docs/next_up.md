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
- [x] App bar counts (Tim, 2026-10-30): the bell and envelope counts didn't show on iPhone (iOS 26 glass bar); now Apple's own badge, with room between the two (Android too). Needs an iPhone build (1.1.1) to reach phones.
- [x] Home, the night's staff (Tim, 2026-10-30): bartender and house staff no longer land on the first show; roles that aren't per show get their own row named after them, by start time, and a show counts only its per-show roles ("Needs Booth Tech" with Role Call on). 020b2ebe, not deployed.
- [x] Mark all read (Tim, 2026-10-30): Messages and Notifications update in place, counts too, instead of reloading the screen. Server only.
- [x] **Tap to Pay on iPhone (V1.2): sent to Apple 2026-10-19.** The reply to the Oct 12 email (Case-ID 22828656) went with the checklist; the four videos and a follow-up after. Apple's review takes a week or two.

## Soon

- [ ] Reports → Ticket Sales by Show: count other sites too, as Attendance does.
- [ ] V1.1 (was V2): production mode + new navigation on its own branch; never deployed until both app reviews pass. Carries the per-build path config and user-agent marker.
- [ ] V1.2 (was V1.1): Tap to Pay on iPhone, on main behind Debug builds; the Release build registers it once Apple grants the publishing entitlement.
- [ ] Books, stages B to F (`docs/accounting_books_plan.md`), one phase at a time.
- [x] The Door before it opens (Tim, 2026-10-23). Built on main the same day, as planned below; not deployed yet.
  The problem: the Door's page says "Nothing to work right now" and then lists
  what's coming later, and you can't tap what it lists. "Next for you" and
  "Later tonight" are text only. "Coming up" (organizations set to "always" only)
  does link, but each row opens that show's whole door, check-in included, days
  early, because `door#show` never checks whether the door is open. Web and the
  app load the same page, so what looked like a mobile difference is probably
  the organization's "Door in the app" setting.

  **The decision:** show everything coming up and let people open it. Until a
  show's door opens (the time set in Ticketing settings → Door), nobody scans or
  checks anyone in. Box office can still sell in person (cash, card, tap, comp)
  at presale prices, and nobody it sells to is checked in. No link to the
  online sales page: selling in person covers it.

  The build:
  1. **The list** (`door/index.html.erb`, `DoorController#index`): "Later
     tonight" and "Next for you" rows link to `door_path(listing)` like "Coming
     up", each saying when its door opens. Show "Coming up" for every
     organization, not just "always" (drop that condition on `@coming_up`). This
     undoes the 2026-10-18 call ("no list of coming dates"), so fix the
     controller comment too. Reword "Nothing to work right now" to something
     like "Nothing on right now".
  2. **One test for "ahead"**: `DoorTonight.phase(listing) == :before`. Leave
     `:after` (the door closed after the show) as it is today.
  3. **The door page ahead** (`door/show.html.erb`): a line at the top, "The door
     opens Fri at 6 PM. You can sell ahead now; check-in starts when it opens."
     No Scan tab. The list can be seen but rows don't check anyone in (no tap, no
     All), and no pass holders. Box office opens on Sell; everyone else on List.
     Hide the scanner bridge too, so the app doesn't offer its camera.
  4. **The server refuses check-in ahead**: `check_in`, `check_in_order` and
     `use_pass` return "The door opens at …" (JSON for the first two, a redirect
     alert for `use_pass`). `TicketPassCredits.use!(at_door: true)` checks the
     holder in, so ahead it must not run that way.
  5. **Presale prices**: ahead, the types on sale are the ones selling online
     right now (`tier.selling?`: no door-only types, sales windows respected),
     not `door_sellable?`. The products are the online ones (`product_offers`
     without `at_door`). That choice has to be made the same way in all of
     these: `DoorController#show` (`@tiers`, `@offers`),
     `TicketCheckout.requested_tiers` (card and tap come through `at_door:
     true`), `TicketCheckout` line ~153 (products by channel), `TicketDoor#sell`
     (today it takes any `available?` type), and `TicketDoor#counts[:left]`.
     Nothing on sale online yet? Say "Nothing's on sale for this date yet".
  6. **No check-in when selling ahead**:
     - Cash and comps: `TicketDoor#sell` makes tickets `"valid"`, not
       `"checked_in"`.
     - Card and tap: `TicketOrderSettlement.settle!` checks in every
       `DOOR_CARD_CHANNELS` order. Change it to check in only when the door is
       open at settle time, `"valid"` otherwise.
     - Then on the night, they're on the list by name to check in like
       everyone else.
  7. **Books**: `TicketDoor#post_cash_sale!` moves the sale straight to income
     ("the show is happening"). Ahead it isn't happening yet: the money still
     goes into the cash box (`door_cash`), but the sale stays in
     `advance_ticket_sales` / `advance_product_sales`. `TicketMoneyRelease`
     moves it to income the day after the show, as it does for online sales.
  8. **Words**:
     - The sell form's footnote ("Cash and comps are checked in as you record
       them") becomes, ahead: "Sold ahead: they're on the list to check in
       when the door opens."
     - The `sell` flash notices too ("Comped 2 and checked them in").
     - `door_sale` emails (TicketingAfterSaleJob) shouldn't say they're in.
  9. **Same requirements as presale** (Tim, 2026-10-23: it's presale and nobody's
     checked in, so ask what online checkout asks). Online
     (`TicketCheckoutsController#pay`) requires a name and a valid email (phone
     optional) and shows the age limit and the refund policy before paying.
     `door_card` skips all of that today (`at_door` in that action and in
     `ticket_checkouts/show.html.erb`). When selling ahead:
     - Card ("Scan to pay", on the buyer's own phone): the checkout page
       treats it as online. Name and email required, the age limit and the
       refund policy shown. So `at_door` there means "door card, door open",
       not just the `door_card` channel.
     - Cash, tap and comp (the door phone): the sell form requires name and
       email (phone optional) and shows the date's age limit and refund
       policy above the pay buttons. The server checks name and email too, in
       `TicketDoor#sell` and `TapToPay.start!`.
     - The order keeps the refund policy snapshot (`TicketCheckout.start!`
       already does this; `TicketDoor#sell` doesn't) and the buyer's email.
       They get the confirmation with their tickets, as an online buyer does
       (`TicketOrderConfirmationJob`). Today cash and comp orders never send
       it, and card and tap only send it when there's an email.
  10. **Specs**: `spec/services/ticket_door_spec.rb` (ahead sales are valid, at
      presale prices, books in advance) and `spec/services/door_tonight_spec.rb`.
      Add a door controller request spec for the refusals.

## Waiting on

- [ ] Apple's answer on Tap to Pay on iPhone. When it says yes: add the Tap to Pay entitlement back to `ios/CocoScout-Release.entitlements`, drop the `#if DEBUG` around TapToPayComponent's registration in `SceneDelegate.swift`, set the version to 1.2 with a new build number, Tim uploads and submits it, then `TapToPayLaunch.announce!` for Stars & Garters (dry run first).
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
