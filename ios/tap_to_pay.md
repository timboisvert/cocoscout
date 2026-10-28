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
three videos. Apple's checklist: "a video recording from another iPhone is
best ... Otherwise, screen recording from the same device will suffice." Tim
has one iPhone, so all three are screen recordings on it.

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

Apple's Marketing Toolkit: done (Tim, 2026-10-19). The splash, the push and
the launch email use its Hero photo and copy unaltered.

### What's built (2026-10-19, commits 56bd44e2, 1a13445e, a7e7ee71)

Every Required item in v1.8 is built and was tried end to end in the
Simulator with Stripe's simulated reader: the splash, setting up from its
page (location, Apple's terms, progress, Apple's guide, "Try it out at the
door"), the getting-ready screen over a sale, a paid sale with its receipt
code, a canceled one, and a second sale on a warm reader with no reconnect.
It shows only in Debug builds (TapToPayComponent registers under `#if DEBUG`)
and only where an organization has Tap to Pay on iPhone switched on
(Ticketing settings → Door → Tap to Pay on iPhone → Manage; a superadmin
sees that card on every organization, and switching it on offers it there).

Who accepts Apple's terms: CocoScout takes every organization's payments on
one account, so Apple's terms are accepted once, by a CocoScout
administrator (`TapToPay.can_accept_terms?`, superadmins). Anyone else who
tries before that sees "An administrator needs to turn it on first" (3.8.1).

### Before filming (Tim)

1. Deploy main (done 10/19), and switch Tap to Pay on iPhone on for
   Stars & Garters (done 10/19).
2. Delete the CocoScout app from the iPhone. Apple: uninstalling is what
   makes the iPhone configure Tap to Pay from scratch, so the progress bar
   shows; it also brings back the one-time Tap to Pay on iPhone page.
3. Plug the iPhone into the Mac, open `ios/CocoScout.xcodeproj`, pick the
   iPhone at the top of the Xcode window, press Run. That build talks to
   cocoscout.com and is the only one with Tap to Pay until Apple says yes.
4. Film on a show day: Work the door appears only then.
5. Turn on Do Not Disturb. Screen Recording is in Control Center (add it in
   Settings → Control Center if it isn't there); recordings land in Photos.
6. Apple's terms are per merchant, and CocoScout is one merchant, so they
   may already be accepted from the Oct 15 test. If Set up in video 1 goes
   straight to the progress bar with no terms screen, they were. To show
   them, remove the merchant ID first: go to
   business.apple.com/taptopay/removeall, sign in with the Apple Account on
   the iPhone, choose "Remove all merchant IDs" and confirm (Apple's page
   "Remove a merchant ID in Apple Business", linked from page 10 of the
   PDF). It takes up to 15 minutes, and Tap to Pay on iPhone stays off on
   that account until the terms are accepted again in video 1. If the
   page lists no merchant IDs, the terms were never accepted.
7. Order: existing user, then new user, then checkout. Delete the app and
   run it from Xcode again before each of the first two.

### Video 1: Existing user (film first)

Apple's reply of Oct 27 (Case-ID 22828656): the videos must clearly show
Apple's own Terms and Conditions sheet being reviewed and accepted, ideally
right after the awareness page, and Apple's sheet only. Our first take
showed it, but filmed in the dark and scrolled past in seconds, and the
"Terms apply." disclaimer looked like terms of our own. So "Get started" on
the awareness page now starts setup at once (location, then Apple's terms),
and the disclaimer sheet is headed "About Tap to Pay on iPhone".

Before it: remove the merchant ID (step 6 above) and wait 15 minutes, or
Apple's terms won't show. Deploy main first: Get started needs the page's
`?setup=1`. Try a screen recording first; if Apple's sheets come out black,
have Andy film it in good light. Start recording at the app's welcome
screen.

1. Sign in as yourself.
2. The full-screen Tap to Pay on iPhone page appears. Tap
   "Get started with Tap to Pay on iPhone". Don't tap "Terms apply." in
   any video.
3. Allow location (Allow While Using App). Apple's account sheet, then
   Apple's Tap to Pay on iPhone Terms and Conditions: scroll through them
   slowly, then Agree. Watch the progress bar. Apple's guide opens on its
   own; close it. The page says Ready and offers "Try it out at the door".
4. Menu (the pink button, bottom right) → Work the door → tonight's show →
   Sell: the Tap to Pay on iPhone button, first among the ways to pay.
5. Menu → Settings (in the pink card) → Tap to Pay on iPhone → "See how":
   Apple's guide again, from Settings. Close it and stop recording.

This take no longer shows the door's button before the terms are
accepted. The Oct 19 take does, and Apple didn't object to it, so send
both: this one as "1 Existing user" (filmed 10/28, a screen recording:
Apple's terms come out clear in one), and "1b Existing user, before
setup", the first 31 seconds of the Oct 19 take (sign in, Not now, the
Sell button before the terms), cut from `not for Apple/1a existing user`.

The app's menu is the My pages only (Tim, 2026-10-19): Tap to Pay on
iPhone's setup lives on Settings, never as a menu tile.

### Video 2: New user

Same iPhone, a new person who will work the door.

1. Off camera, on cocoscout.com: Ticketing settings → Door → "Who can
   work the door", invite an address that has no CocoScout account and
   whose mail you can read on the iPhone (your Gmail with +door before the
   @ works), as "Check people in and sell tickets".
2. Delete the app, run it from Xcode again. Start recording at the
   welcome screen.
3. Open the invitation email in the Mail app and tap its link. It opens
   in the CocoScout app: choose a password, and the door opens. (If it
   opens in a browser instead, choose the password there, then open the
   app and sign in with the new address.)
4. The full-screen Tap to Pay on iPhone page appears: Get started.
5. Set up Tap to Pay on iPhone: allow location, the progress bar,
   configuration finishing, Apple's guide, Ready, "Try it out at the
   door". No terms screen: CocoScout accepted them in video 1, which the
   checklist comments say. Stop recording.
6. Menu → Sign out, and sign back in as yourself.

### Video 3: Checkout

1. Start recording. Menu → Work the door → tonight's show → Sell. Add
   one ticket.
2. Pause on the ways to pay, Tap to Pay on iPhone first.
3. Tap Tap to Pay on iPhone. If the iPhone is still getting ready, the
   "Getting Tap to Pay on iPhone ready" screen shows.
4. Hold your own card at the top of the iPhone. Apple's card screen may
   come out black in a screen recording; Apple protects it.
5. Paid, with "Scan for a receipt". Leave it on screen a few seconds, then
   Back to the door. Stop recording.
6. Refund that order on cocoscout.com: Ticketing → Orders → the order →
   Refund.

### Recording 4: Website setup (Mac)

Apple's guide: when onboarding happens on a website, "you must still
provide a video recording of that onboarding process". This shows how a
door person gets authorized. On the Mac, press Command-Shift-5, choose
Record Entire Screen, then Record.

1. On cocoscout.com as the Stars & Garters manager: Ticketing settings →
   Door.
2. The Tap to Pay on iPhone card (On) → Manage: show the modal (the switch,
   who can use it, setting up an iPhone, "Terms apply."), then Cancel.
3. "Who can work the door": invite a new address (boisvert+door2@gmail.com)
   as "Check people in and sell tickets", and send. Stop recording
   (the stop button in the menu bar). Withdraw that invitation afterwards.
4. Name the file "4 Website setup".

### The files

In `ios/apple_ttp/` (not committed): "1 Existing user", "2 New user",
"3 Checkout", "4 Website setup", and the filled checklist, "CocoScout
Checklist 1_8.numbers" (Apple's blank original is kept beside it). Before
sending, check the checklist's Info tab: Version 1.2, and "New" for
Existing or New app; change it to Existing if V1 is live in the App Store
by then.

### The reply to Apple

Reply to Apple's Oct 12 email (Case-ID 22828656) with the filled checklist
attached, and upload the four recordings the way that email says. A body
to start from:

> Hello, attached is CocoScout's completed App Review Requirements
> Checklist v1.8, with four recordings: existing user, new user, checkout,
> and the website setup.
> CocoScout is the box office for the performing-arts organizations that
> use it. Every organization's ticket sales go through CocoScout's own
> Stripe account, so CocoScout is the merchant, with one Merchant ID, and
> its administrators accept the Tap to Pay on iPhone terms once, in the app.
> The people who use Tap to Pay on iPhone are door staff an organization's
> managers invite by email from our website; they create their account in
> the app and set up Tap to Pay on iPhone there. Organizations sign up and
> open their box office on cocoscout.com, and nobody an organization hasn't
> authorized can take payments, so we ask for the exception for apps
> restricted to pre-authorized users (requirement 2.2).
> Thank you.

### Checklist answers (Apple's numbering, v1.8)

Info tab: App Name CocoScout. PSP Name Stripe. Existing app. Number of
devices: the smallest range. Distribution: Public.

General
- 1.1 iPhone XS and later: Done. The payment SDK checks the iPhone, and an older one is told it can't take Tap to Pay on iPhone.
- 1.2 Human Interface Guidelines: Done.
- 1.3 Marketing guidelines: Done. Apple's copy and Hero photo, unaltered; always "Tap to Pay on iPhone".
- 1.4 Old iOS: Done. "To take payments with Tap to Pay on iPhone, update iOS: Settings > General > Software Update."
- 1.5 and 5.6 Warm-up: Done. Once set up, the app connects in the background at launch and every time it comes back to the front.
- 1.6 Acceptance status from Apple: Done. The app asks Apple through the SDK each time and keeps no record of acceptance; if Apple says the terms aren't accepted, it shows Set up again.
- 1.7 Face ID or Touch ID login: Can improve. Sign-in uses iOS Password AutoFill, which unlocks with Face ID.
- Primary payment method items: Not applicable. Tap to Pay on iPhone is one of several ways to pay at the door.
- Regional: United States only. No PIN fallback, surcharging or IFR.

Onboarding merchants
- 2.1 to 2.3: Exception requested (see the reply). A door person's account takes about two minutes; setting up Tap to Pay on iPhone a minute or two.

Enabling Tap to Pay on iPhone
- 3.1 and 6.2 Splash: Done. Full screen, once per person on each iPhone, with Apple's Hero photo and copy.
- 3.2 and 6.3 Push: Done. At launch, a CocoScout message with a push carrying Apple's Value Proposition copy, to everyone who can sell at a door that has it.
- 3.3 Visible: Done. "Tap to Pay on iPhone" on Settings and first on the door's Sell screen.
- 3.4 End of onboarding: Done. Opening a box office says how to turn on Tap to Pay on iPhone, and Ticketing settings → Door has its card.
- 3.5 Accepting the terms: Done. "Set up Tap to Pay on iPhone" on its page, and the checkout button.
- 3.6 Outside checkout: Done. Settings → Tap to Pay on iPhone.
- 3.7 Trigger in checkout: Done. The door's button opens the terms when they aren't accepted.
- 3.8 Authorized party only: Done. Only CocoScout's administrators, because one merchant account serves every organization.
- 3.8.1 Message for others: Done. "An administrator needs to turn it on first."
- 3.9.1 Progress: Done. On its page and over a sale, with the percentage.

Educating merchants
- 4.1 ProximityReaderDiscovery on iOS 18 and later: Done. This covers 4.4, 4.6, 4.7 and 4.8.
- 4.2 After the terms: Done. Apple's guide opens as soon as setup finishes.
- 4.3 Later: Done. Settings → Tap to Pay on iPhone → "See how", and "How to take a tap" on the payment screen.
- Try it out: Done. The Ready panel invites them to try it at the door.
- PIN and fallback education: Not applicable in the United States.

Checking out
- 5.1 and 5.2 Button: Done. First among the ways to pay, and choosing Sell brings the tickets and the buttons to the top so nothing needs scrolling.
- 5.3 Never greyed out: Done.
- 5.4 and 5.5 Name and symbol: Done. "Tap to Pay on iPhone", with no symbol.
- 5.7 Initializing: Done. "Getting Tap to Pay on iPhone ready."
- 5.8 Processing: Done. Apple's screen.
- 5.9 Outcome: Done. Paid, not approved, or canceled.
- 5.10 Receipt: Done. A QR code on the result screen whether approved or not; the receipt names no card and no buyer.
- 5.12 Not approved while closed: Done. A notification that opens the door.
- Refunds: Referenced refunds, from the order page; no card tap.
- Schemes: Visa, Mastercard, American Express, Discover.
- Receipt methods: QR code.

Marketing
- 6.1 Launch email: Done. Apple's Launch email, to the people who can sell at a door that has Tap to Pay on iPhone. Send it with `TapToPayLaunch.announce!` once Apple approves (dry run first).
