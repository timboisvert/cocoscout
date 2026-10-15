# Tap to Pay at the door

The buyer taps their card or phone on the door phone; Stripe Terminal
charges it in person. Ships after the App Store v1 — the server half is done
and idle until the app sends a tap; the iOS half needs a Mac build.

## Money

Same money path as every other sale: CocoScout's Stripe account, the
organization's balance credited its net (OrgCashEntry), our 50¢ and the
processing on the books (CocoScoutLedgerEntry), so the money check
(Stripe = Σ OrgCashEntry + Σ CocoScoutLedgerEntry) holds with nothing new.
The books take processing_cost from the real `stripe_fee_cents`, not the
quote, so a tap's lower fee lands correctly whatever we quoted.

Who pays the fees is the listing's `effective_fee_mode` (TicketingProfile
default, per-production and per-listing override), exactly as the door's
"Card or phone pay". Only the processing rate changes:

| | Online, card or phone pay | Tap to Pay |
|---|---|---|
| CocoScout | 50¢ a paid ticket | 50¢ a paid ticket |
| Stripe | 2.9% + 30¢ an order | 2.7% + 5¢ + 10¢ a Tap to Pay authorization = 2.7% + 15¢ |

`TicketPricing::IN_PERSON_PER_MILLE` / `IN_PERSON_FIXED_CENTS`; the rate is
from Stripe's pricing and Terminal pages (October 2026). A $20 ticket with
the buyer paying: $21.42 online, $21.22 tapped.

## Server (done)

- `TicketOrder` channel `door_tap` (checked in the moment it's paid, like
  `door_card`); `TicketPricing.quote(in_person: true)` through
  `TicketCheckout.price!` / `TicketPurchase#price!`.
- `TapToPay`: a Stripe Terminal Location per organization from its default
  venue's address (`organizations.stripe_terminal_location_id`), connection
  tokens, the sale (seats held via `TicketCheckout.start!`), the amount and
  metadata the app makes the PaymentIntent with (`payment_params`), and
  settlement checked against Stripe through `TicketOrderSettlement` (it must
  carry this order's id; a wrong amount is refunded). The
  `payment_intent.succeeded` webhook settles it too.
- The app makes the PaymentIntent, not the server: since Oct 2026 Stripe
  rejects `payment_method_types` on CocoScout's account, and payment method
  configurations can't include `card_present`. The Terminal SDK's
  `createPaymentIntent` still makes in-person intents (checked in the
  Simulator against test mode, 2026-10-13).
- Door: a "Tap to pay" button on the sell panel, in the app only;
  `/door/:listing/tap/:token` (the page the phone is held out on),
  `/door/:listing/tap/connection-token`, `/door/:listing/tap/:token/settle`;
  the card-sale status and cancel endpoints are shared.
- JS: `door_tap_controller.js` (asks the app, settles, watches the order)
  and `bridge/tap_to_pay_controller.js` (the bridge).

## iOS (needs a Mac)

- Add the `stripe-terminal-ios` Swift package (StripeTerminal).
- `Bridge/TapToPayComponent.swift` and `Door/TapToPayReader.swift` are
  written against Terminal iOS 4.x; check the API names against the version
  the package resolves to, then build.
- The entitlement `com.apple.developer.proximity-reader.payment.acceptance`
  is in CocoScout.entitlements; Apple has granted it on the App ID.
- Apple's "How to Tap" guide (done 2026-10-15, `Door/HowToTap.swift`): shown
  before the first tap on a phone, and again from "How to take a tap" on the
  tap page; iOS 17 gets a short guide of ours. Location and Bluetooth
  purpose strings are in Info.plist (build 5).
- Test with a Stripe test-mode Location and the SDK's simulated reader, then
  a real tap on a device.

## After this: V2

Once V1.1 (Tap to Pay) ships, the next app release is V2: production mode
on mobile web and in the app. The plan is locked in
`docs/production_mode_v2_plan.md`. Have V1.1 carry a per-build
path-configuration address and a user-agent version marker (see that plan's
release section), so V2 server changes can't reach V1 installs.
