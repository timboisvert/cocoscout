# Contract people: contractors live on My, not the Production Dashboard

Decided with Tim, 2026-10-17. Status: **plan agreed, not started.** The
viewer-proofing of the Production Dashboard (commit 5493242f and the
hide-buttons sweep after it) stays: it's for in-house production teams.

## The problem

Two different relationships were using one door.

- **In-house co-producers** (Clay Smith on an in-house production): they
  run the show with us. The Production Dashboard is theirs: shows, casting,
  sign-ups, messages. Production team *managers* change things, *viewers*
  look.
- **Contractors** (Carded, who have their own CocoScout organization; Dan
  Feltey, who produces three dates under contract): the contract is the
  relationship. We rent them the room and sell their tickets; they get a
  share. They should see their contract, their dates, their sales, their
  comps, what they get, and nothing of ours.

The contract wizard's Team step (2026-10-16) put contractors on the
production team. That hands them the Production Dashboard, and with it the
organization's **Contacts, Messages, Documents, availability grid and
sign-ups**, which are organization-wide. No amount of viewer-proofing fixes
that: the content itself isn't theirs. Since 5493242f the Team step adds
viewers only, which narrows the hole without closing it.

## The model

- **Contractor** stays the one party to the contract: signs it, gets paid
  (Stripe rail, bank setup, 1099), reports sales on a they-sell deal. One
  `Contractor.person`, as today. Nothing here changes.
- **Contract people** (new): the people the contractor brings, with the
  *contractor's visibility* and no more. They are not contract
  administrators and never become one by being added. Several per
  contract. The contractor's own person counts as one, always.
- A contract person is **never** given a `ProductionPermission` by a
  contract. The production team is set by the organization on the
  production's Team tab, for in-house teams only.

Everything a contract person sees is on **My**. They never enter the
Production Dashboard for that production (they may still have one for
their own organization, as Carded does).

## What they see on My

Already there, keyed off `contractors.person_id` today; widen each to
"any person on the contract":

| Today | Where | Change |
|---|---|---|
| My Contracts: the contract, dates, payments, documents | `My::ContractsController#my_contracts` | widen to contract people |
| Ticket Sales: their dates at the Everything level, and the daily sales email | `TicketSalesAccess.contract_show_ids`, `listings_for` (the daily email uses it) | widen to contract people |
| Dashboard: active contracts | `my/dashboard_controller.rb:422` | widen |
| Who sees sales, on the manage side | `TicketSalesAccess.contracts_for`, `Manage::TicketSalesViewersController` | list the contract people, not just the contractor |

Stays the contractor's alone (it's about being paid, not about seeing):
signing (`Contract` out-for-signature lookup), payments and the payments
summary (`My::PaymentsController`, `MyPaymentsSummary`), bank setup,
reporting sales.

New:

1. **Contracted dates in My shows & events.** A new source for the list,
   next to talent pools, sign-ups and assignments: the shows of every
   active contract the person is on (`contract.contract_shows`). Each row
   is marked as **theirs by contract** and looks different at a glance from
   "you're cast in this": no cast panel, no "Can't make it". When someone is
   both (Dan performs in other shows), the two kinds of row sit in the same
   list, told apart by the marker. "Can't make it" shows only for a date
   they're *cast* in, never for one they produce.
2. **The date page reads the deal.** The Contract box from the event page
   (`contract_date_picture`) rendered on `my/shows/show`, in the second
   person: your share, Services (opens), **You get** $30.00, when. Services
   are the ones they contracted for, read-only. The contractor's payments
   link stays on My Contracts; the box here is the reminder.
3. **Who's coming, and comps.** On the date page and on My Ticket Sales:
   who's coming by name (already Everything level), and **Give comps**,
   since Dan should give comps for his own show. `comp_allowance` grows
   from "production team manager at Everything" to "that, or a contract
   person on this date", under the same comp rules (box office comp
   settings, per-date limits, no comps once the date has started). The
   comps form moves to a shared partial used by `manage/production_sales`
   and `my/ticket_sales`.
4. **Money stays with the payee, and the page says so.** A contract person
   who isn't the contractor sees the amounts but no bank, no "set up
   payouts", no payment links. One line where those would be: "Payments go
   to <contractor name>." Otherwise someone on Carded's side will look for
   "their" bank.

## Setting them up

- **The wizard's Team step becomes "Who's on this contract".** Same
  search-first invite flow (invite-search, create-new-person only after a
  search finds nobody), no role choice. Staged in `draft_data["people"]`
  (user id or email, plus name). The contractor's signer is suggested first,
  as today. Activation (`Contract#apply_draft_team!` → rename
  `apply_draft_people!`) creates `ContractPerson` rows instead of
  production permissions.
- **Amend** gets the same step, so people can be added to or dropped from
  a live contract.
- **People without an account**: a `TeamInvitation` already carries an
  optional `production_id`, `invitation_role` and `person_id`; add a
  nullable `contract_id` and accept it the same way, creating the
  `ContractPerson` on accept instead of a `ProductionPermission`. One
  invitation model, two things it can grant.
- **Dropping someone** removes their `ContractPerson`; nothing else of
  theirs is touched (they may still be a performer with us).

## Data

```
contract_people
  contract_id   bigint, null: false, fk
  person_id     bigint, null: false, fk
  added_by_id   bigint, null: true (users)
  created_at / updated_at
  unique index [contract_id, person_id]
```

`Contract has_many :contract_people; has_many :people, through:`.
`Contract.visible_to(user)`: contracts where the contractor's person or a
contract person is one of `user.people`, not draft/cancelled. Every
widened lookup above goes through it.

## Moving the existing ones

Contractors are on production teams today (Carded's people; Dan on three
productions). One console block, **after Tim looks at the list**: for each
active contract with a production, every `ProductionPermission` on that
production whose user's person is the contractor or was staged in
`draft_data["team"]` becomes a `ContractPerson` and the permission is
dropped (the orphaned "member" organization role goes with it, as
`ProductionPermission#remove_orphaned_org_role` already does). Anyone else
on those teams (an in-house co-producer) stays. Dry run first, printed as a
table of who moves and who stays.

## Not in this

- No change to the production team roles or to the viewer-proofing.
- No casting, running order or sign-ups for contract shows: contract shows
  don't use them (Tim, 2026-10-17). They see the services they contracted
  for and that's all of ours they touch.
- The door: a contract person working their own door is a separate
  question (the Door bar is the organization's today).
- Production mode V2 (`docs/production_mode_v2_plan.md`, locked): still for
  in-house teams; contract people aren't its audience. Add one line there
  saying so when this ships; no other change.

## Order of work

1. `ContractPerson`, `Contract.visible_to`, widen the four lookups
   (My Contracts, sales access, dashboard, who-sees-sales). Specs: a contract
   person sees exactly what the contractor sees, minus payments.
2. Wizard step "Who's on this contract" + Amend + invitations by email;
   activation creates contract people, never permissions. Retire the Team
   step's permission path.
3. My shows & events: contract dates as a source, the marker, the date
   page's Contract box in the second person, "Payments go to …".
4. Comps and who's coming on My (shared comps partial, `comp_allowance`
   widened).
5. Migration console block, dry run, then move Carded and Dan over with Tim
   watching.
6. The one-line note in the V2 plan.

Each step lands on main on its own; Tim deploys.
