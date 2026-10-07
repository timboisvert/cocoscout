# Apple Pay, Google Pay and bank payments at checkout

How wallets work on CocoScout's checkouts, what has to be switched on, and how
to check it. Written 2026-10-07.

## The short version

- **Our checkouts** (tickets, passes, courses) use Stripe's Payment Element on
  cocoscout.com pages. **Contract payments** use Stripe's own hosted page.
- **Apple Pay and Google Pay are cards.** They're a card stored on the phone or
  in the browser, charged and priced as a card (2.9% + 30¢, the same fee the
  buyer already covers). Money, refunds and disputes work exactly like cards.
- **No code is needed for them.** The Payment Element shows a wallet by itself
  when all four of these are true:
  1. the method is **on** in Stripe's payment method settings;
  2. the page's domain is **registered** with Stripe (cocoscout.com *and*
     www.cocoscout.com: `www` counts separately);
  3. the page is HTTPS;
  4. the buyer's device has it set up: Safari or an iPhone with a card in
     Apple Wallet for Apple Pay, Chrome or Android with a card saved to Google
     for Google Pay.
- **No Apple developer account, merchant ID, certificate or verification file.**
  Stripe does Apple's merchant validation once the domain is registered.
- **"Take a bank" means Link's Instant Bank Payments**, not ACH. The buyer
  picks Bank, logs into their bank through Link, and the payment is confirmed
  on the spot. It costs 2.6% + 30¢ (less than a card), settles on the card
  timeline, and Stripe guarantees it against bank returns. It comes with Link.
- **ACH Direct Debit is wrong for checkout.** It takes up to four business days
  to clear, so a ticket buyer's ten-minute hold runs out first, and while it's
  on, Link stops offering instant bank payments.
- **Klarna, Affirm and Afterpay cost about 6% + 30¢**, twice the fee the buyer
  covers; CocoScout would absorb the difference.

## Steps (Tim, in the live Stripe Dashboard)

1. **Settings → Payment methods** (the default configuration). On: Cards,
   Apple Pay, Google Pay, Link. Off: Klarna, Affirm, Afterpay/Clearpay, Cash
   App Pay, Amazon Pay, Crypto, ACH Direct Debit. Methods that need another
   currency (Bancontact, Pix, Kakao Pay...) never show for US dollars, so
   they can stay as they are.
2. **Settings → Payment method domains → Add a new domain**: `cocoscout.com`,
   then `www.cocoscout.com`. Registering in live mode registers them in the
   sandboxes too. Or run:
   `kamal app exec --primary 'bin/rails stripe:register_payment_domains'`
3. **Check** where everything stands (read-only):
   `kamal app exec --primary 'bin/rails stripe:wallets'`
   It lists the registered domains with their Apple Pay / Google Pay / Link
   status, what checkout offers now (and which methods to turn off and why),
   and how people paid over the last 30 days.
4. **Test with real money once**: on any on-sale date, add a hidden $1 ticket
   type with an unlock code, buy one on your iPhone with Apple Pay (and on an
   Android or Chrome with Google Pay), check the order, refund it from the
   order page, and remove the ticket type. Stripe keeps its ~35¢ fee.

## Where wallets won't show

- **Local development** (`localhost`): Apple Pay needs a registered HTTPS
  domain. Cards and Link work. (ngrok plus registering its domain works if it
  ever matters.)
- **The CocoScout iOS app**: Apple disables Apple Pay in an app's web view once
  the app injects JavaScript, and Hotwire Native always does. Cards work.
  Course checkout is the only payment page people reach in the app. Fixing it
  means native Apple Pay (Stripe's iOS SDK behind a bridge component) or
  handing checkout to Safari with a one-time sign-in link; a project for later.
- **The embed on a theater's own site**: the checkout overlay is an iframe on
  their domain. Wallets show there only if *their* domain is registered on
  our account too (Apple Pay also needs Safari 17+). Register with
  `kamal app exec --primary 'DOMAINS=example.com,www.example.com bin/rails stripe:register_payment_domains'`.
  The iframe already carries `allow="payment"`.
- **Stripe's hosted contract page** needs no registration: wallets follow the
  Dashboard switches.

## In the code

- Payment Element, deferred mode: `app/javascript/controllers/checkout_controller.js`
  (tickets, passes, courses). `elements.submit()` runs first in the Pay
  handler, which is what opens the Apple Pay / Google Pay sheet; amounts are
  kept current with `elements.update`.
- PaymentIntents use `automatic_payment_methods: { enabled: true }`
  (`ticket_checkouts_controller.rb`, `my/course_checkouts_controller.rb`,
  `ticket_pass_purchases_controller.rb`): the Dashboard decides the methods.
- Hosted contract checkout: `contract_payment_checkout_controller.rb`. The
  webhook settles it only once Stripe says it's paid, and handles
  `checkout.session.async_payment_succeeded` / `_failed`, so a bank debit is
  never credited or paid out before its money arrives. If ACH is ever turned
  on for contracts, add those two events to the webhook destination.
- `StripeWalletCheck` (`bin/rails stripe:wallets`, `stripe:register_payment_domains`).

## Later, if wanted

- **Express Checkout Element**: one-tap Apple Pay / Google Pay / Link buttons
  at the top of checkout instead of a tab inside the payment box. It needs the
  buyer's name and email taken from the wallet, so it's a checkout change, not
  a switch.
- **ACH for big contract payments** (0.8%, capped at $5) through a payment
  method rule that offers it only above an amount, now that the webhook
  waits for the money.
