# Stripe in development

CocoScout takes money three ways, and they need different keys.

| Flow | How it pays | Keys it needs |
|---|---|---|
| Courses | Stripe's hosted Checkout page (a redirect) | secret key |
| Contract payments | Stripe's hosted Checkout page | secret key |
| **Tickets** | Stripe's Payment Element on our own page | secret key **and publishable key** |

If the ticket checkout page says "Card payments aren't available right now",
the publishable key is missing. Signed in as a superadmin (or in development)
the page says so in so many words.

## Keys

`.env` (read by dotenv at boot; restart the server after editing it):

```
STRIPE_SECRET_KEY=sk_test_…          # the sandbox secret key
STRIPE_PUBLISHABLE_KEY=pk_test_…     # the sandbox publishable key, same account
STRIPE_WEBHOOK_SECRET=whsec_…        # only needed to exercise the webhook path
```

Both Stripe keys must come from the **same** sandbox account; a publishable key
from another account makes `confirmPayment` fail in the browser. In production
the same values live in credentials (`stripe.secret_key`,
`stripe.publishable_key`, `stripe.webhook_secret`); `config/initializers/stripe.rb`
and `TicketingHelper#stripe_publishable_key` read ENV first, then credentials.

## Buying a ticket on localhost

1. Add `STRIPE_PUBLISHABLE_KEY` to `.env` and restart `bin/dev`. `bin/dev` also
   runs `bin/jobs`, which the confirmation email needs (it opens in
   letter_opener).
2. Open a date that's on sale. A superadmin can buy even while the org's
   ticketing is switched off.
3. On the checkout page wait at least three seconds before paying (the
   bot-pace rule, `TicketCheckoutsController::MIN_SECONDS_TO_PAY`), then pay with
   `4242 4242 4242 4242`, any future date, any CVC.
4. The "done" page settles the order itself (`TicketOrderSettlement.settle!`),
   so **no webhook is needed**. The same is true of courses (the success page
   creates the registration).
5. Refund from the manager's order page: `TicketOrderRefund` calls Stripe
   inline. After a show's money has been released, a refund bigger than the
   available balance is refused on purpose.

Things to know:

- Rate limits run in development too (`config/initializers/rack_attack.rb`):
  20 `/pay` requests an hour per IP. Heavy testing gets a 429; wait, or flush
  Redis.
- Apple Pay never shows on `localhost`; it needs a registered HTTPS domain
  (a production chore). Cards and Link work; Google Pay appears in Chrome with
  a saved card.

## Exercising the webhook path (optional)

```
stripe listen --forward-to localhost:3000/webhooks/stripe
```

Put the `whsec_…` it prints in `STRIPE_WEBHOOK_SECRET`. Tickets settle on
`payment_intent.succeeded` (metadata type `ticket_order`), courses on
`checkout.session.completed`. Both handlers are idempotent, so a payment that
also settled on the done page is left alone.
