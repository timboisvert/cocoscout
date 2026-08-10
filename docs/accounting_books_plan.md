# Accounting / "Real Books" Plan — Money as Books of Record

Status: **planned, not started.** Deferred until **after the new subscriptions launch.**
Written 2026-07-18 from a full code review of the money section. This is a large,
multi-phase build (it adds an accounting engine underneath the existing app), so it's
written to be picked up cold later. Nothing here is built yet.

## Thesis (read this first)

Let a **small theater / production-company owner on the Pro tier run their real books
inside CocoScout** — income and expenses in the thousands to low tens of thousands a
year — and get something **official, traceable, and eventually tax-ready**, *without*
turning into QuickBooks. No chart-of-accounts homework, no debits/credits in your face,
no "you must be an accountant to use this."

The tension: real accounting is double-entry and traceable; small owners find double-entry
overwhelming. The resolution is a **two-layer design**:

1. **A correct double-entry engine, hidden by default.** Every money event posts a
   balanced, immutable journal entry, so the books are real, official, and traceable, and
   taxes can sit on top. The owner never sees a debit, a credit, a journal entry, or a
   chart of accounts in day-to-day use.
2. **A simple CocoScout-native experience on top.** The owner sees plain language —
   *money in, money out, profit by show and production, "download your official summary"* —
   in the concepts they already use. The accounting is **derived automatically** from the
   shows / contracts / payouts they already manage. There is nothing new to "do."

### Confirmed product decisions (from the user)

- **Ambition:** real books of record (genuine double-entry), but **simplicity is
  non-negotiable** — it must keep the spirit of CocoScout and stay **tied to production
  economics** (shows, productions, contracts, payouts). Tax comes later, built on top of
  the traceable books.
- **Basis:** **cash by default, both available.** The owner sees cash-basis (income counts
  when paid, an expense counts when paid — "did it hit my account?"). The engine stores
  enough (a document date *and* a cash date on every entry) that an accountant can flip to
  accrual at tax time.
- **Visibility:** **simple UI by default + an optional "Books" view.** Owners see the
  simple experience; a toggle reveals real statements (P&L, balance sheet) and the ledger
  for those who want them or want to hand a CPA a login. That view must also stay un-scary.
- **Target user:** a small owner with a modest volume of income/expenses who wants
  something official and traceable, and later, help with taxes.
- **First feature layers requested:** **Bills / money you owe (AP)** and **Invoices /
  money owed to you (AR)** — but expressed in plain language, not as accountant subledgers.

---

## Part 1 — Current state (what exists today, accurately)

The money section is **show/production economics, not accounting.** Inventory from the
code review:

### Structure
- One top-level **"Money"** nav item (`app/helpers/navigation_helper.rb`), gated by paid
  plan → `manage_money_index_path`. No money sub-nav; sub-areas are surfaced as action
  cards on the hub (`app/views/manage/money/index.html.erb`): **Financials**, **Payouts**,
  **Contracts**. Payout Runs, Payout Schemes, Advances, and Contractors are reached
  contextually, not advertised.
- Controllers (all `app/controllers/manage/`): `money_controller` (hub),
  `money_financials_controller` (per-production drill-down), `money_payouts_controller`,
  `show_financials_controller`, `show_payouts_controller` (the big per-show worksheet),
  `payout_batches_controller` (Stripe Connect runs), `payout_schemes_controller`,
  `advances_controller`, `contractors_controller`, `contracts_controller` (largest source
  file), `contract_wizard_controller`, `contract_payments_controller`,
  `contract_documents_controller`, `course_offering_payouts_controller`,
  `production_expenses_controller`, `expense_items_controller`, and `reports_controller`.

### The "ledger" is single-entry / one-sided
- `app/models/payout_ledger_entry.rb` tracks only **what the org owes each payee** — a
  signed running balance per payee (`entry_type` earning +, advance/payout −), derived via
  `SUM(amount_cents)`, never cached. Polymorphic `payee` (Person/Contractor/Group) and
  `source`. Idempotent `post!` keyed on `(source, entry_type)`, plus `unpost!`.
- It is **not double-entry** — there is no offsetting cash/expense account, only the payee
  side. Balance queries live on `Organization#payout_balance_cents_for` /
  `#payout_balances_by_payee`.

### Money is siloed across ~10 models with mixed units
- **Cents:** `PayoutLedgerEntry`, `PayoutBatch` / `PayoutBatchItem` / `PayoutContribution`,
  course registrations.
- **Dollars (decimal):** `ContractPayment` (has `direction` incoming/outgoing, `status`,
  `amount`, `due_date`, `amount_tbd`), `ShowFinancials` (`ticket_count`, `ticket_revenue`,
  `flat_fee`, `other_revenue`, `expenses`), `ExpenseItem` (per-show, with receipts),
  `ProductionExpense` (spread across shows via `ProductionExpenseAllocation`).
- **There is no single money type and no unified transaction table.**

### Payout machinery (works; keep it)
- `ShowPayout` / `ShowPayoutLineItem` (per-show performer payouts; `sync_earning_ledger_entry!`
  / `sync_payout_ledger_entry!` are the ledger hooks), `PayoutBatch` (Stripe Connect run;
  statuses draft/funding/funded/processing/completed/failed/canceled; kinds
  performer/staff_pay), `PayoutBatchItem` (one payee's transfer; `mark_paid!` posts the
  payout ledger entry), `PayoutContribution` (composition detail). Services:
  `performer_payout_run_service`, `staff_pay_run_service`, `contractor_payout_run_service`,
  `advance_payout_service`, `payout_funding_service`, `payout_batch_service`,
  `scheduled_payout_service`.
- `PersonAdvance` / `AdvanceRecovery` (advances that net against future payouts).

### Reporting is on-the-fly and thin
- `app/services/financial_summary_service.rb` computes a **cash-basis, show-level
  Gross Profit / P&L** on every request (period selectable). It **hard-codes
  `net_income = gross_profit`** and explicitly does **not** track operating expenses. No
  balance sheet, no cash flow, no trial balance.
- There is no profitability summary view any more — `_profitability_summary.html.erb`
  rendered 4 KPI cards + a breakdown accordion but was never wired into a page, and was
  deleted in the dead-code sweep. Whatever replaces it starts from scratch.
- `Manage::ReportsController` is the only report hub: six fixed reports (Revenue by
  Production, Revenue Over Time, Course Revenue, Payouts Summary, Events Summary, Cast
  Participation) with **CSV export** (`report_to_csv`) and browser-print "PDF" (no
  server-side PDF engine).
- **Revenue is hand-keyed** per show (`ShowFinancials`); there is **no ticketing
  integration** (no Ticket Tailor / Eventbrite sync). The app already tracks "pending
  financials" counts because shows routinely lack entered data.

### Missing entirely (vs. QuickBooks)
Chart of accounts, journal entries, double-entry, invoices (AR docs), bills/vendors (AP),
aged receivables/payables, bank reconciliation, balance sheet, cash flow, period close,
1099/W-9, multi-currency, and any data visualizations.

---

## Part 2 — Target architecture (the hidden engine)

### Two layers
- **Engine layer (hidden):** double-entry general ledger — a real chart of accounts and
  balanced journal entries — that the owner never sees by default.
- **Experience layer (visible):** plain-language money views tied to shows/productions,
  plus an *optional* Books view that reveals the real statements/ledger.

### Engine primitives
- **One money type:** integer **cents** at the engine boundary. Normalize dollars→cents
  when posting; never post dollars. (Existing dollar-based models can keep their storage
  short-term; the posting layer normalizes.)
- **`Account` (chart of accounts), auto-seeded, hidden by default.** Columns:
  `organization`, `code`, `name`, `account_type` (asset/liability/equity/income/expense),
  `subtype`, `system` (protected, un-deletable) vs user-editable, `active`. Seed a sensible
  default set for a small theater org (see Phase 1 checklist). Seeding must be
  **idempotent + environment-aware** (per the project rule for template/seed changes).
- **`JournalEntry` + `JournalLine` (balanced, immutable).**
  - `JournalEntry`: `organization`, `entry_date` (earned/incurred), `cash_date` (when cash
    moved; nullable until paid), polymorphic `source`, `status` (draft/posted/void),
    `posted_at`, `memo`.
  - `JournalLine`: `journal_entry`, `account`, signed `amount_cents` (debit +, credit −),
    plus **dimensions** `production_id`, `show_id`, polymorphic `payee`.
  - **Invariant:** a posted entry's lines sum to zero (balanced). Posted entries are
    **immutable**; corrections are **reversing entries**, never edits. This immutability is
    what makes the books trustworthy for tax.
- **Dual dates = cash and accrual from one dataset.** Cash-basis reports recognize
  income/expense on `cash_date`; accrual on `entry_date`. This is how "cash by default,
  both available" falls out of a single engine — no second system.
- **`LedgerPosting` service:** `post!(source:, entry_date:, cash_date:, memo:, lines:)` —
  **idempotent per `source`** (re-posting restates, never duplicates), transactional,
  validates balance before commit. Directly mirror the idempotency of
  `PayoutLedgerEntry.post!` / `unpost!`.
- **`PayoutLedgerEntry` becomes a subledger** that reconciles to a "Payables to Performers"
  control account. Keep it — it drives payout-run math — and bridge it into the GL. Do not
  rip it out.

### Dimensions preserve the production-economics spine
Every journal line carries `production_id` / `show_id` / `payee` (and, if we adopt fund
accounting, `fund_id`). This is QuickBooks "classes/locations," and it's what lets the
simple views keep slicing profit **by show and by production** exactly like today, while
the accounting rides underneath.

---

## Part 3 — Phased roadmap with per-phase to-do checklists

Sequencing: **1 → 2 are invisible foundation**; **3 (simple view) and 4 (bills/invoices)
are the first things the owner feels** and deliver the value; **5 (optional Books) and 6
(tax)** follow once the books are trusted. Each phase is independently shippable.

### Phase 1 — The hidden engine (invisible plumbing, real books)

No owner-facing UI. Goal: CocoScout's books become real and traceable underneath.

- [ ] Add a money helper / convention doc: cents at the engine boundary; a `to_cents` /
      `from_cents` helper; decide on a `Money`-ish value object or plain integer cents.
- [ ] Migration + `Account` model: `organization`, `code`, `name`, `account_type`,
      `subtype`, `system` (bool), `active` (bool); indexes on `(organization_id, code)`
      unique, `(organization_id, account_type)`.
- [ ] `Account` validations + enum for `account_type`; scope `active`, `for_type`; guard
      against deleting `system` accounts.
- [ ] Migration + `JournalEntry` model: `organization`, `entry_date`, `cash_date`
      (nullable), polymorphic `source`, `status`, `posted_at`, `memo`; indexes on
      `(organization_id, entry_date)`, `(source_type, source_id)`, `status`.
- [ ] Migration + `JournalLine` model: `journal_entry`, `account`, `amount_cents`
      (signed), `production_id` (nullable), `show_id` (nullable), polymorphic `payee`
      (nullable); indexes for reporting on `account_id`, `production_id`, `show_id`.
- [ ] `JournalEntry` balanced validation (lines sum to zero) enforced on post.
- [ ] Immutability: prevent update/destroy of `posted` entries at the model level; provide
      a `reverse!` that posts an inverse entry.
- [ ] `LedgerPosting.post!(source:, entry_date:, cash_date:, memo:, lines:)` — idempotent
      per source (restate on re-post), transactional, balance-validated; and `unpost!` /
      `void!`. Mirror `PayoutLedgerEntry.post!`.
- [ ] Seed the default theater-org chart of accounts (idempotent, env-aware rake task):
      Assets — *Cash/Bank*, *Money Owed to You (A/R)*, *Advances Receivable*, *Undeposited
      Funds*; Liabilities — *Money You Owe (A/P)*, *Payables to Performers* (control);
      Equity — *Owner's Equity / Retained*; Income — *Ticket Income*, *Rental/Contract
      Income*, *Course Income*, *Other Income*; Expenses — *Venue*, *Production*,
      *Marketing*, *Talent/Performer Pay*, *Equipment*, *Stripe/Processing Fees*, *Other*.
- [ ] Hook default-CoA seeding into organization creation (new orgs get accounts; existing
      orgs backfilled by the rake task).
- [ ] Internal-only trial-balance check (rake task or dev view) proving debits == credits.
- [ ] Specs: `LedgerPosting` (balanced-or-raise, idempotent per source, reversing);
      `Account` (system-protection, uniqueness); trial balance on seeded+posted data;
      cash-vs-accrual totals derive correctly from `cash_date` vs `entry_date`.

### Phase 2 — Tie the engine to production economics (auto-post + backfill)

Goal: everything the owner already does auto-generates the books. Nothing new to do.

- [ ] Poster: ticket / flat-fee / other revenue from `ShowFinancials` → Cr income,
      Dr Cash/Undeposited, tagged production/show; `cash_date` from confirmation/receipt.
- [ ] Poster: show expenses (`ExpenseItem`) → Dr expense, Cr Cash/AP, tagged show.
- [ ] Poster: production expenses (`ProductionExpense` + allocations) → Dr expense, Cr
      Cash/AP, spread by allocation dimension.
- [ ] Poster: performer/staff/contractor payouts (`PayoutBatchItem#mark_paid!`,
      `ShowPayoutLineItem` earnings) → earnings accrue to Payables-to-Performers; payment
      Dr Payables / Cr Cash.
- [ ] Poster: advances (`PersonAdvance`) → Dr Advances Receivable, Cr Cash; recovery nets.
- [ ] Poster: course revenue + CocoScout fee (`CourseRegistration`, `OrgPayout`).
- [ ] Reconcile `PayoutLedgerEntry` to the Payables-to-Performers control account (bridge,
      don't remove); add a reconciliation check.
- [ ] Backfill migration: generate journal entries from existing historical records.
      **Must be idempotent, reversible, and reconciled to current balances before trusted.**
      (Hard constraint: do not lose or distort advance/payout history.)
- [ ] Make `FinancialSummaryService` a **reader/validator over the engine** (or assert it
      matches) rather than the source of truth.
- [ ] Specs: each poster asserts the exact balanced entry (accounts, signs, dimensions) +
      idempotency on re-post; backfill reconciles to pre-existing `PayoutLedgerEntry`
      balances with **no history drift**.

### Phase 3 — The simple money experience (what the owner sees)

Goal: the payoff of 1–2, in CocoScout language. Upgrade the money hub.

- [ ] Rework `money/index` to read from the engine, and build a fresh profitability
      summary to sit alongside it: **Money In / Money Out / Profit**, cash-basis default,
      sliceable by production and period.
- [ ] Keep **profit by show and by production** front and center; zero accounting jargon
      (no accounts, debits, journal entries in this view).
- [ ] "Download your official summary" — a clean, official, traceable statement (sets up
      the tax story) without exposing the machinery. (Reuse `report_to_csv`; add PDF later.)
- [ ] Add lightweight **charts/trends** (choose a small chart lib — none installed today).
- [ ] Request specs: hub shows plain-language totals, **no accounting vocabulary leaks**;
      numbers match the engine.

### Phase 4 — Money you owe / owed to you (bills & invoices, plainly)

Goal: AP + AR in CocoScout language — documents and reminders, not subledgers with aging.

- [ ] `Vendor` model (broader than `Contractor` — venues, utilities, suppliers); optional
      link from a Contractor/Person payee to a Vendor.
- [ ] `Bill` + `BillLine`: vendor, bill_date, due_date, lines (expense account + amount +
      production/show dimension), status (open/partial/paid/overdue/void), receipt
      attachments. Post Dr expense / Cr A/P on entry; Dr A/P / Cr Cash on pay.
- [ ] "Mark paid" on a bill can flow into the **existing payout rail** for contractor bills
      (reuse `ContractorPayoutRunService`) or plain paid-by-cash/check/Stripe.
- [ ] Unify the three expense mechanisms (`ExpenseItem`, `ProductionExpense`, ad-hoc
      contract outgoings) into one "expense / bill" concept posting to expense accounts.
- [ ] Owner-facing "what you owe" reminders (plain: "you owe $X, due Friday") — cash-basis:
      counts only when paid; outstanding shown as a reminder, not A/P aging.
- [ ] `Invoice` + `InvoiceLine`: customer (co-producer, renter, sponsor), issue/due date,
      lines (income account + amount + dimension), status (draft/sent/viewed/partial/
      paid/overdue/void), attachments. Post Dr A/R / Cr income on send; Dr Cash / Cr A/R on
      payment.
- [ ] Fold incoming `ContractPayment`s into invoices (keep the contract link); reuse
      `Contract#revenue_share_summary` / `suggested_amount_from_financials` for amounts.
- [ ] Owner-facing "who owes you" reminders (plain: "$X expected from Y by Z"), cash-basis.
- [ ] *(Optional, high value)* Stripe-hosted **invoice pay link** for inbound collection,
      reusing the existing Stripe integration.
- [ ] Specs: bill and invoice lifecycles (create → mark paid / send → paid) post correct
      entries and only affect the cash-basis total when paid; paying a contractor bill via
      the payout run still nets correctly on the payee subledger.

### Phase 5 — The optional "Books" view (for owners who want it, or their CPA)

Goal: reveal real accounting behind a toggle; off by default; kept un-scary.

- [ ] A gated "Accounting / Books" section (toggle or nav sub-item) — hidden unless enabled.
- [ ] **Income Statement (P&L)** from the engine, sliceable by production, with a
      **cash ⇄ accrual toggle** (uses `cash_date` vs `entry_date`).
- [ ] **Balance Sheet** (assets / liabilities / equity) — newly possible with double-entry.
- [ ] **Cash Flow Statement** (indirect).
- [ ] **Ledger / account register** + **journal** views for a CPA.
- [ ] **Accountant export**: journal/GL as CSV (and IIF/QBO if feasible) so a CPA can pull
      it into their tool.
- [ ] Server-side **PDF** statements (add a PDF engine — none exists; current PDF is browser
      print). Reuse `ReportsController` scaffolding.
- [ ] Bank/cash **reconciliation** (CSV import first, Plaid later) against the GL cash
      account; **Stripe payout reconciliation** using existing Stripe data.
- [ ] **Period close / lock date** so filed periods can't shift; adjusting entries;
      retained-earnings roll-forward.
- [ ] Specs: P&L from the engine matches `FinancialSummaryService` for a known dataset;
      Balance Sheet balances (A = L + E); reconciliation matching; period-lock enforcement.

### Phase 6 — Tax (the reason for the traceability)

Goal: built on the now-official books; deferred but designed toward from day one.

- [ ] **Tax-ready summary** (Schedule C-style income/expense rollup by category) to hand a
      preparer or file from.
- [ ] **W-9 collection** for contractors.
- [ ] **1099-NEC:** total each contractor across the year from the payee subledger; generate
      1099 data / export at year end.
- [ ] Eventual **tax estimation/management** on top of the categorized, traceable books.
- [ ] Specs: annual payee totals match the subledger; category rollups match the P&L.

---

## Part 4 — Cross-cutting concerns, risks, and open decisions

### Enforced simplicity (a feature, not a nicety)
The default experience **never** shows an account code, a debit/credit, or a journal entry.
Accounting vocabulary lives only in the optional Books view. Any PR that leaks it into the
default owner UI is wrong.

### Risks
- **Historical backfill (Phase 2) is the single riskiest step.** The user has repeatedly
  stressed **not losing advance/payout history** (there's real production history). The
  backfill must be idempotent, reversible, and reconciled to existing balances (especially
  `PayoutLedgerEntry`) before it's trusted.
- **Units:** the dollars-vs-cents split across models is a persistent footgun. Normalize at
  the posting boundary; consider migrating dollar models to cents over time.
- **Faithfulness:** owners must not see their numbers change when the engine goes live —
  engine-derived P&L must match today's `FinancialSummaryService` for the same data.

### Open decisions (resolve before/while building)
- **Nonprofit / fund accounting:** many theater orgs are 501(c)(3). A `fund` dimension +
  a **Statement of Activities** would be a real differentiator vs. generic QuickBooks. Not
  in the core plan yet — decide whether to add a fund dimension in Phase 1 (cheap now,
  expensive to retrofit) even if the UI comes later.
- **Automated ticket-revenue capture:** revenue is hand-keyed today, which is the root cause
  of incomplete financials. A ticketing integration (Ticket Tailor / Eventbrite) was
  deprioritized by the user but would materially improve data quality. Slot as an optional
  track feeding the Phase 2 revenue poster.
- **Inbound payments:** whether to push invoice collection through Stripe (Phase 4 optional)
  — turns A/R into actually-collected cash but adds scope.
- **Multi-currency:** out of scope; store `currency` but assume single-currency per org.

---

## Part 5 — Verification strategy (applies to every phase)

- **Engine:** `LedgerPosting` unit specs — balanced-or-raise, idempotent per source,
  reversing corrections. A seeded + posted dataset yields a balanced trial balance.
- **Basis:** the same dataset yields the correct **cash** total (recognized on `cash_date`)
  and **accrual** total (on `entry_date`) — proving "cash by default, both available."
- **Faithfulness:** engine-derived P&L matches `FinancialSummaryService` for a known
  dataset; backfill reconciles to existing `PayoutLedgerEntry` balances with no drift.
- **Owner experience:** money-hub request specs show plain-language Money In/Out/Profit with
  **no accounting jargon**; the Books view is absent unless toggled on.
- **AP/AR:** bill and invoice lifecycle specs post correct entries and only move the
  cash-basis total when paid.
- **Statements:** Balance Sheet balances (A = L + E); reconciliation and period-lock
  enforced.
- **Every phase:** RSpec (models/services/requests), RuboCop, ERB compile checks, and Stripe
  sandbox smoke tests for any money movement.

---

## Reference: key existing files to build on

- Ledger idempotency pattern: `app/models/payout_ledger_entry.rb`
  (`post!` / `unpost!`), balance queries in `app/models/organization.rb`.
- On-the-fly P&L to supersede/validate against: `app/services/financial_summary_service.rb`.
- Money-in/out raw material for AR/AP: `app/models/contract_payment.rb`,
  `app/models/contract.rb` (`revenue_share_summary`, `suggested_amount_from_financials`),
  `app/models/expense_item.rb`, `app/models/production_expense.rb`.
- Revenue capture today: `app/models/show_financials.rb`,
  `app/views/manage/show_financials/_worksheet_modal.html.erb`.
- Payout rail to reuse for paying bills: `app/services/contractor_payout_run_service.rb`,
  `app/models/payout_batch*.rb`.
- Report/export scaffold: `app/controllers/manage/reports_controller.rb` (`report_to_csv`).
- Expense taxonomy → account mapping: `config/expense_categories.yml`,
  `app/models/expense_categories.rb`.
- Money hub to upgrade: `app/controllers/manage/money_controller.rb`,
  `app/views/manage/money/index.html.erb`.
