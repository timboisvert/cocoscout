# Follower email pricing: options for Tim

Written 2026-10-28. This is a decision for Tim; nothing is built yet.

Today `FollowerEmailAllowance` gives each Pro organization 500 follower emails a
month (one email to one follower counts as one) and stops there. Tim wants an
allowance with paid emails above it, starting on Mailgun's Basic 10k plan.

## What Mailgun charges

From Tim's figures and Mailgun's pricing page on 2026-10-28:

| Plan | Per month | Included | Over the included volume | Sending domains |
|---|---|---|---|---|
| Basic 10k | $15 | 10,000 | $1.80 per 1,000 (Basic does allow going over) | **1** |
| Foundation 50k | $35 | 50,000 | $1.30 per 1,000 | 1,000 |
| Foundation 100k | $75 (Tim's figure) | 100,000 | about $1.10–1.30 per 1,000 | 1,000 |

Mailgun's page lists the overage rates as "from" prices. The 100k tier shows up
there as Scale at $90, so check the exact plan name and price when buying.
Mailgun bills overage itself and gives no way to cap it, so any cap has to be
ours.

## Two facts that shape every option

**1. Basic means follower email goes out from cocoscout.com.** Transactional mail
(sign-in, tickets, receipts, contracts) already uses Basic's one domain,
`cocoscout.com` (`config/environments/production.rb`). The code assumes a
second domain: `FollowerMailer` sends from `news@FOLLOWERS_MAIL_DOMAIN`, and
production won't send to followers until that is set. On Basic, the only way
to send is to set it to `cocoscout.com`. Here is what that risks:

- **Mailgun keeps its suppression lists per domain.** If a ticket buyer marks
  one organization's newsletter as spam, Mailgun puts that address on
  cocoscout.com's complaint list. From then on it silently drops their sign-in
  codes and ticket confirmations, until someone removes the address in
  Mailgun by hand. This is the concrete harm, and it starts with the first
  complaint.
- **Reputation.** Followers sign up through a checkout box that is ticked by
  default, so some will forget they did and mark the mail as spam. Gmail and
  Yahoo want complaints under 0.3% for each sending domain. One careless
  organization's complaints would count against the domain that carries
  everyone's sign-in mail.
- **What a second domain doesn't fix.** All mail still shares one Mailgun
  account, and on these plans it goes out from Mailgun's shared IP addresses,
  so Mailgun could still suspend the whole account over bad lists. The
  platform-wide suppression already built into the webhook (bounces and
  complaints are never emailed again) is the guard there, on either plan.

The second domain costs $20 a month more (Foundation 50k at $35 instead of Basic
at $15). That is one Pro monthly subscription.

**2. Room in each plan.** Transactional mail peaks around 1,500 a month today.
I plan on 3,000 to leave room for ticketing to grow. That leaves about 7,000
for followers on Basic (14 organizations at 500 each, 7 at 1,000) and about
47,000 on Foundation 50k (47 organizations at 1,000). Once total mail passes
about 21,000 a month, Foundation 50k costs less than Basic plus overage
($15 + 11,000 × $1.80 per 1,000 ≈ $35).

## What other tools give

- **Eventbrite:** 250 marketing emails a day free, about 7,500 a month. Paid
  plans by daily volume start around $15 a month for 2,000 a day.
- **Ticket Tailor:** broadcasts to ticket buyers are free, with no published
  monthly cap. They are meant for announcements, not marketing.
- **Mailchimp:** the free plan is about 250 contacts and 500 emails a month.
  Essentials is about $13 a month for 500 contacts and 5,000 emails, roughly
  $2.60 per 1,000.
- **Kit:** free with unlimited sends up to 10,000 people on the list. Paid plans
  are about $33–39 a month and up.
- **Buttondown:** free for the first 100 people, then about $9 a month near 1,000
  and $29 near 5,000. It prices by list size, not by sends.

So 500 a month is stingy next to Eventbrite and Kit. An organization with 1,000
followers could send them one email. A per-email price above about $3 per 1,000
costs more than Mailchimp. Mailgun's cost to us is $0.70 per 1,000 inside
Foundation 50k ($35 / 50,000) and $1.30–1.80 per 1,000 past either plan, so
$2 per 1,000 still makes money.

## The options

In every option the allowance is per Pro organization per calendar month, the
same for monthly ($20) and annual ($200) Pro, and resets on the 1st. Emails
above it are billed per email on a third Stripe meter, in the same calendar
month, on the monthly usage subscription that already carries the $5 staff and
$3 performer fees (`StaffMeterService.ensure_staffing_subscription!`), so
annual Pro organizations are billed the same way. A safety cap stays as a hard
stop above the allowance (see below).

The costs below are CocoScout's whole Mailgun bill, with 3,000 transactional
emails, when every Pro organization sends exactly its free allowance (no
overage income). For comparison, transactional mail alone costs $15 on Basic.

### Option A: Basic, shared domain, 500 free, $3 per 1,000 over

| Pro organizations | Follower emails | Mailgun bill | What followers add |
|---|---|---|---|
| 5 | 2,500 | $15 (Basic) | $0 |
| 20 | 10,000 | $20.40 (Basic + 3,000 over) | $5.40 |
| 50 | 25,000 | $47.40 on Basic, or $35 after moving up | $32.40 / $20 |

Safety cap: 5,000 a month per organization. Cheapest at the start, but it
carries the suppression and reputation risk to sign-in and ticket mail
described above. At about 35 organizations it costs more than Foundation
anyway.

### Option B (recommended): Foundation 50k, news.cocoscout.com, 1,000 free, $2 per 1,000 over

| Pro organizations | Follower emails | Mailgun bill | What followers add |
|---|---|---|---|
| 5 | 5,000 | $35 | $20 |
| 20 | 20,000 | $35 | $20 |
| 50 | 50,000 | $38.90 (Foundation 50k + 3,000 over) | $23.90 |

Safety cap: 20,000 a month per organization, which CocoScout can raise for an
organization that asks. It keeps follower mail on its own domain as the code
already expects, and the bill stays flat up to about 47 organizations. Above
the allowance, an organization pays $2 for each 1,000 more. Our cost there is
$0.70–1.30, so $2 covers it.

### Option C: Foundation 50k, news.cocoscout.com, 2,500 free, $2 per 1,000 over

| Pro organizations | Follower emails | Mailgun bill | What followers add |
|---|---|---|---|
| 5 | 12,500 | $35 | $20 |
| 20 | 50,000 | $38.90 | $23.90 |
| 50 | 125,000 | about $111 (Foundation 100k + about 28,000 over) | about $96 |

Safety cap: 25,000 a month per organization. This is the most generous option,
close to Mailchimp Essentials and enough for two emails a month to a list of
1,000. At 50 organizations it costs about 11% of Pro income ($1,000 a month),
against about 4% for Option B, and it would rarely earn overage.

## Recommendation: Option B

Move to Foundation 50k rather than Basic, and give each Pro organization 1,000
follower emails a month, with $2 per 1,000 above that. The extra $20 a month
keeps a newsletter complaint from cutting off a buyer's ticket emails and
sign-in codes. That risk is the one that would hurt CocoScout most, and the
code is already built around a separate domain. With 1,000 a month, an
organization can send a newsletter to a typical list without paying more, and
an organization with a big list pays a small, predictable amount.

Keep a hard stop as a safety cap, not as the limit people normally reach:
20,000 a month per organization (the allowance plus up to $38 of extra
emails). It guards against an organization sending to a huge list by mistake
and against a surprise bill, and CocoScout can raise it on request. A send that
would cross it waits, as sends do today at 500.

### If Tim picks B, what changes later (not built)

- `FollowerEmailAllowance::INCLUDED_PER_MONTH` becomes 1,000. A safety cap
  constant (20,000) takes over the hard stop. `over` becomes the metered
  amount.
- A Stripe meter and a metered price at $0.002 per email are added to
  `SubscriptionPlan.staffing_subscription_items`, with a `FollowerEmailMeterService`
  modeled on `StaffMeterService` (only `bills_usage?` organizations,
  stable identifiers).
- The Pricing page and the usage fees modal say "1,000 follower emails a month
  included, then $2 per 1,000", next to Pro at $20 a month or $200 a year.
- Release checklist §2b: buy Foundation 50k (not Basic), and the 500 note
  becomes the new numbers.
