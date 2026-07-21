# Course "settle & remit" + Organizations as Connect payees

## Goal

When a course finishes, CocoScout — which has already collected all the
registration money into its platform balance — settles everything in one motion:

1. **Instructors** are paid from the **held course funds** (Stripe transfers from
   the platform balance to their Connect accounts). They ride the **performer
   payout run** as `Person` payees; unpayable until they connect a bank.
2. **The organization keeps the remainder** (net revenue − instructor payments),
   remitted to the **org's own Stripe Connect account**.

Key constraint discovered: the performer run is normally **funded by the org's
ACH**; course money is **held by CocoScout for the org**. So course-sourced
payouts must be funded from the held platform balance, never a fresh org debit —
otherwise the org pays twice.

Decisions (from Tim): **nets & remits**; **onboard orgs to Stripe Connect** so
the org is a real payee on the same rail as performers.

## Stages

### Foundation 1 — Organization becomes a Connect payee  ← current
- Migration: add `stripe_account_id / stripe_account_status / payouts_enabled /
  stripe_account_synced_at` to `organizations` (mirror `AddStripeConnectToPayees`).
- `include StripeConnectable` in `Organization` (gives `can_receive_payouts?` etc.).
- Make `StripeConnectService` org-aware: `business_type: "company"` + company
  profile/prefill for an `Organization`; keep `individual` for Person/Contractor.
- `StripeConnectService.payee_for_account` also checks `Organization`.

### Foundation 2 — Org Connect onboarding UI
- A manage-side "Get paid to your bank" flow: create Express account + hosted
  onboarding link + return/refresh, status badge. Reuse `payee_onboarding`
  patterns. Webhook `account.updated` already syncs via `payee_for_account`.

### Stage B — A separate, **fund-free** course payout run
The money is already in CocoScout's platform balance, so a course run needs **no
funding step** — no ACH pull, no PaymentIntent. It just transfers held money out.
This is a distinct `PayoutBatch` kind that skips `fund!` entirely.

- New batch kind `"course"` in `PayoutBatch::KINDS`; `open_for(org, kind: "course")`
  is the single active course run. Items = **sum of contributions** (like staff
  runs, not performer net-settle) — no ledger-earning gymnastics needed.
- `CoursePayoutRunService.add_to_run!(course_offering_payout)`: one item per
  instructor line item (payee `Person`) + one item for the org remainder (payee
  `Organization`). Idempotent per source (`PayoutContribution.exists?(source:)`).
  Only add payees who `can_receive_payouts?`; the rest stay "needs bank".
- Execution: course-run processing transfers from the **platform balance** to
  each payee's Connect account (`Stripe::Transfer`, ideally `source_transaction`
  tied to the registration charges for fund tracing). No `fund!`, no ACH.

### Stage C — "Settle course" UX + reconciliation
- One "Settle course" action that runs Stage B and shows the unified result:
  instructors "In course payout run" / "Needs bank"; org remainder "Remitting
  $Y to your bank".
- `OrgPayout` becomes the record of the org transfer; reconcile the superadmin
  finances view (`owed_cents_for_course` → net − instructor payments = remitted).

## Settlement math (done)
`CoursePayoutSettlement` is the single source of truth for who gets paid what,
used by both the payout page and `CoursePayoutRunService`:
- **Contract course:** contractor gets their contractual share of net; instructor
  pay comes out of the CONTRACTOR's half; org keeps net − contractor_share.
- **No contract:** org keeps net − instructor pay (paying $0 = org keeps all).

## Traceability — what exists vs. gaps
The connective data mostly already exists; the course is the hub for both sides.
- **Money in:** `course_registrations` store `stripe_payment_intent_id`,
  `amount_cents`, `cocoscout_fee_cents`, `stripe_fee_cents`, `refunded_at`. So
  payments + both fees are already linked to the course.
- **Money out:** `course_offering_payout` → line items → `PayoutContribution`
  (polymorphic `source`, unique) → `PayoutBatchItem.stripe_transfer_id`. So a
  payout traces back to the course and (once executed) to the Stripe transfer.
- **Gaps to close for true end-to-end tracing:**
  1. No `stripe_refund_id` on `course_registrations` — we know a reg was refunded
     and when, but can't click through to the Stripe refund. Add the column +
     capture it on refund.
  2. Stamp `metadata: { course_offering_id, payout_id }` on Stripe charges and
     payout transfers so the Stripe dashboard mirrors CocoScout's linkage.
  3. Optional: a settled payout should snapshot exactly which registrations'
     revenue it covered (matters once multiple runs settle a course over time).
  4. A per-course "Money" view/presenter that assembles payments, refunds, fees,
     and payouts into one traceable statement (data exists; it's a reader). This
     is the course-scoped precursor to the deferred double-entry books.

## Execution (next) — fold traceability in
- `CoursePayoutRunExecutor`: for a `course` batch, transfer each item from the
  platform balance to the payee's Connect account, stamping course/payout
  metadata; store `stripe_transfer_id`; `mark_paid!` per item. No `fund!`.
- A **course-run page** in the Courses section (non-Pro) to view/trigger/track
  the run — the existing run pages live under `money/` (Pro-gated), so course
  runs need their own view.
- Add `stripe_refund_id` + charge/transfer metadata as part of this pass.

## Risks
- Org onboarding KYC (company vs individual) differs from performers.
- History/idempotency: mirror `PayoutContribution` source-uniqueness patterns.
- Platform-balance transfers must not exceed available held funds.
- Money movement: build + verify against the Stripe sandbox before enabling.
