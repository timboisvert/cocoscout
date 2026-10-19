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

## Where this sits: V1.2 (renamed 2026-10-19)

Tap to Pay is V1.2. The redesign, production mode and the new navigation
(`docs/production_mode_v2_plan.md`), is V1.1 and goes first; it carries the
per-build path-configuration address (`AppConfig.swift`) and the user-agent
version marker (the Release section), so its server changes can't reach V1
installs. Tap to Pay ships whenever Apple grants the publishing entitlement
below, before or after V1.1.

## Apple's publishing review (guide and checklist v1.8, Oct 2026)

Apple's guide and checklist are in `ios/apple_ttp/` (not committed: they're
Apple's). To get the publishing entitlement, reply to the Oct 12 email from
ttpoientitlements@apple.com (Case-ID 22828656) with the filled checklist and
three videos, **each filmed with a second phone** (the checklist says so for
all three; Apple's Tap to Pay screens don't show in a screen recording):

1. **New user.** Our merchant onboarding happens on the web, so v1.8 wants a
   video of that: an organization signs up on cocoscout.com, opens its box
   office, then Tap to Pay is introduced to it, its Terms and Conditions
   accepted, the guide shown, the progress indicator while the phone
   configures, and configuration finishing. With the video, ask for the
   exception for apps whose merchants are authorized outside the app (2.1–2.3).
2. **Existing user.** The Tap to Pay button visible before the terms are
   accepted; the awareness splash; accepting the terms (every path: Settings,
   checkout); the guide after the terms; the guide again from Settings; the
   progress indicator if configuration is still running.
3. **Checkout.** Pick tickets, the payment options, the Tap to Pay on iPhone
   button, the initializing screen if it takes over 300 ms, a successful tap,
   the receipt.

Only Tim can do: request Apple's Marketing Toolkit (the form at
https://forms.appleservices.apple/form/5e784e28b4e6, linked from the
checklist's 6.1–6.3 rows). The awareness splash, the push and the launch
email must use its assets and copy; we may not make our own.

Met already: 1.1 (iPhone XS+ via the SDK), 1.6 (acceptance status from the
SDK), 3.7 (trigger in checkout), 4.1 and 4.5–4.7 (Apple's How to Tap guide),
5.1 (Tap to Pay first), 5.8 and 5.9 (processing and outcome), US needs no
PIN fallback, surcharging or IFR.

To build (Required in v1.8):
- 1.4 a clear "update iOS" message for the SDK's OS-version error.
- 1.5 and 5.6 warm up Tap to Pay at launch and on foreground, so the screen opens within a second.
- 3.1, 3.2, 3.3 (6.2, 6.3) the awareness moment for eligible users: a full-screen splash once with Apple's Hero banner, and a push with Apple's copy.
- 3.4 at the end of a new organization's onboarding (opening the box office on the web), say how to turn on Tap to Pay in the app.
- 3.5 a clear action to accept Apple's Terms and Conditions (Apple's own screen, opened by the SDK).
- 3.6 and 4.3 a Tap to Pay section in the app's settings: turn it on, and the guide.
- 3.8 and 3.8.1 only an authorized person accepts the terms (an organization's manager); anyone else sees "ask your organization's manager to turn on Tap to Pay on iPhone".
- 3.9.1 and 5.7 the configuration progress indicator and an "initializing" screen while the reader prepares.
- 4.2 the guide right after the terms are accepted, never before.
- 5.3 the button never greyed out; tapped before the terms are accepted, it opens them.
- 5.4 and 5.5 the button says "Tap to Pay on iPhone", with only the `wave.3.right.circle` symbol if any.
- 5.10 a digital receipt on the result screen, approved or declined: a QR code to the order, or email.
- 5.12 a notification when a payment isn't approved after the app was closed.
- 6.1 a launch email to eligible users, from Apple's Launch template.
- No "Stripe" in the processing copy.

Open question for the build: CocoScout takes payments on one account, so
Apple's terms may be accepted once for every organization (terms are per
merchant ID). Check how the SDK's merchant display name and location map to
Apple's merchant ID before deciding who sees the terms.
