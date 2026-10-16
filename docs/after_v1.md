# After V1: the list

Work Tim has decided on, to start once the iOS app's V1 is submitted
(2026-10-15). Not the app roadmap (that's in CLAUDE.md): these are fixes
that came up while finishing V1.

## 1. Sign-up question answers (build it properly)

**Done 2026-10-16.** Answers belong to the registration (`answers` gains
`sign_up_registration_id`; each answer has exactly one owner), saved by
`SignUpAnswers` from `submit_form` and the queue, required ones checked on
the page and again on the server, before anyone is registered. Producers see
them folded under each name on the roster and the assign queue, and a line
each on the printed list. The `CUSTOM_QUESTIONS` switch is gone. Building it
turned up three older bugs on the same path, fixed with it: a guest's name
never reached the server, guests were allowed no sign-ups at all, and on a
form that doesn't require signing in, someone signed in was treated as a
guest (and the roster crashed on a guest's sign-up).

Custom questions on sign-up forms are switched off
(`SignUpForm::CUSTOM_QUESTIONS = false`, 2026-10-15). The sign-up page showed
them, but nothing saved what people typed: the questions sat outside the
submitted form, and `SignUpRegistration` has no answers (see the TODO in
`app/models/sign_up_registration.rb`). Only the demo organization had
questions, so no real answers were lost.

To build:
- Store answers for a registration (the `answers` table, made polymorphic, as
  the TODO describes), for members and guests.
- Put the questions inside the sign-up form (`my/sign_ups/form.html.erb`) and
  save them in `My::SignUpsController#submit_form`, required ones enforced.
- Show each person's answers to producers next to their sign-up (the roster
  and the printed list).
- Then set `CUSTOM_QUESTIONS` back to true (it brings back the Questions tab).

## 2. Payee details asked once, up front

**Done 2026-10-16 (e1e3b528).** After it deploys, a console block marks who
already has details coming due (`people.payout_details_due`).

Stripe wants date of birth and the last four of the SSN from each person
CocoScout pays once they've been paid $3,000; the app only asks for what's
due now, so their pay would pause then. 129 accounts were flagged on
2026-10-15; nobody was near $3,000 (highest about $1,400).

- Sign-up for getting paid asks for everything at the start: change
  `collection_options` in `StripeConnectService#onboarding_link` to collect
  `eventually_due`.
- People already set up: a quiet heads-up on My Payments once they've been
  paid about $2,000, with a button to add the two details. No emails.
- Copy never says "Stripe": "our payment provider" (Tim).

## 3. Door messages that say "Stripe"

**Done 2026-10-16 (46c41f92).**

Reword for door staff, per the same rule: "Stripe hasn't confirmed the
payment yet", "Stripe took $X, not this sale's total", "Stripe couldn't start
that sale" (`app/services/tap_to_pay.rb`, `app/controllers/door_controller.rb`)
and "Confirming with Stripe…" (`door_tap_controller.js`).

## 4. "Sold elsewhere" modal on mobile

**Done 2026-10-16 (76a37e99).**

The Sold elsewhere modal on a show's ticketing page
(`manage/ticket_listings/_outside_sales_modal.html.erb`, with
`_outside_sales_row`) is unusable on a phone (Tim, 2026-10-15). Rebuild it
phone-first: one row per line that stacks instead of a cramped grid, inputs
at 16px so iPhone doesn't zoom, the save button always reachable.

## 5. Downloading the ticketing QR code on mobile web

**Done 2026-10-16 (164bd9fc).**

The QR modal's Download (`shared/_qr_modal.html.erb` →
`qr_code_controller.js#download`) clicks a link to a PNG data URL. On a
phone nobody can tell where the file went (iPhone files it in Files →
Downloads, or opens it as a page). On phones, offer the phone's share sheet
with the image (Web Share API with a file: "Save Image", AirDrop, Messages),
and fall back to opening the image with "press and hold to save". Desktop
keeps the plain download. In the app, the same share sheet.

## 6. Services a show needs (contracts, productions and staffing)

The biggest gap (Tim): knowing which shows need our services. Some shows'
contracts say they need a booth tech; shows we produce ourselves (about
half) never say, so at staffing time nobody can tell which shows need
security, a videographer or a booth tech.

Make services first-class on the production (and each show), whatever
created it:
- A production (or a single show) lists the services it needs: e.g.
  security, videographer, booth tech.
- Contracts fill that in: a contract's services (today
  `ContractServiceOption` and the contract's `draft_data["services"]`,
  priced, per event or once) set the services on the shows it books. A
  production made without a contract picks them directly.
- Staffing reads them: each service maps to the house roles that provide
  it (`HouseRole`: Tech, Security…), so the staffing pages show which shows
  still need someone for a service, and scheduling can create those shifts.
- Creating a contract starts from the services already chosen.

Needs a design pass with Tim first (the service ↔ house role mapping, per
show vs per production, pricing for in-house shows).

## 7. "Paid" when the money is still on its way

**Done 2026-10-15 (670db423, 9ee668c7), with 8.** Words: waiting for approval →
approved → on its way → deposited. Needs `payout.created` and `payout.paid` on
the connected-accounts webhook, and the one-time deposit backfill after deploy.

We tell people "paid" the day CocoScout sends the money, days before it
reaches their bank. Fae (staff) asked when they'd actually get paid: the
date in CocoScout is "days before payment", it would help budgeting to know
when to expect it, and "you've paid but I've not had payment received, so
it feels a little aaaa to see 0 owed". Tim: don't get it there faster;
stop giving the impression it's already arrived.

- Find every place that tells someone they've been paid or are being paid
  (My Payments, My Shifts' getting-paid card, payout emails and messages
  from ContentTemplates, the payout run timeline, contract payments) and
  reword by stage: approved → sent, on its way (arrives about <date>) →
  in your bank.
- The arrival date can be real: the payment provider reports each payout
  to the person's bank with an expected arrival date, and says when it has
  landed (Connect payout events). Show "Arrives about Oct 14" and then
  "In your bank Oct 14". Never name the provider (rule 2's).

## 8. The getting-paid card on My Shifts

**Done 2026-10-15 (670db423): direction A from the mockups.**

Mockups for 7 and 8 (2026-10-15, three directions, waiting on Tim's pick):
https://claude.ai/artifact/MBkyRtw5j498PHGKC1NV9n

`my/shifts/_getting_paid.html.erb` (Fae's screenshot, 2026-10-15) reads
wrong in every part:
- "Owed for staffing hours $0.00" right after a payout that hasn't arrived
  says they're owed nothing. Show money on its way separately from money
  still owed.
- "Estimated from 0 unpaid hours · 0h pending, 0h approved. Tips and
  extras are added at pay time." is too technical. Say it the way a person
  would ("3 hours waiting for approval"), or say nothing when it's all zero.
- "Recently paid … paid Oct 11" for each day worked: use the stages from 7
  ("on its way", "in your bank Oct 14").
- The green "Bank connected — you're set up to get paid. Manage" bar looks
  bad on a phone; restyle it with the house alert style, not green.
