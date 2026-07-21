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

## Risks
- Org onboarding KYC (company vs individual) differs from performers.
- History/idempotency: mirror `PayoutContribution` source-uniqueness patterns.
- Platform-balance transfers must not exceed available held funds — trace to the
  registration charges via `source_transaction` where possible.
