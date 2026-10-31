# CocoScout Books (V1.3): the plan, reviewed (2026-10-31)

Branch `v1.3`, worktree `.claude/worktrees/v1.3`, cut from main at 5dde7886. The
Books rollout was planned on 2026-10-02 ("Books: the deep plan" in
`~/.claude/plans/cocoscout-ticketing-and-books.md`) as stages 0 to G. Stages 0, A,
B and G shipped with ticketing in October. V1.3 is the rest: C, D, E and F, plus bills
and invoices. This document is that plan, re-read against everything that landed
since, and is the one to build from. Mocks of every Books screen, new and existing:
https://claude.ai/artifact/H7WuPkA7dfhEMWVdRFvext

## 1. What Books is, and where it lives

- **The name.** CocoScout Books is the sub-product, next to CocoScout Ticketing and
  CocoScout Staffing, on the pricing page and in the partner one-pager. Inside the
  app, **Money stays the navigation item**, as Tim asked: Money is the module,
  Books is its record. The hub keeps answering "what needs me?" (financials to
  enter, payees to pay, money to collect, and now bills to pay); Books answers "what
  happened, in dollars". Bills and invoices are things to do, so they sit on the
  Money hub beside Payouts and Incoming Payments, not inside Books, even though
  marketing calls the whole thing Books.
- **Plain words, always.** No debit, credit, journal, ledger, A/R or A/P on any page
  an organization sees. "When it moved" and "When earned" are the two ways to count.
  "Money you have / Money you owe / Income / Spending" are the groups.
- **Who sees it.** Today Books is superadmin-only (`BooksController`,
  `ensure_user_is_superadmin`) and the hub hides the card. V1.3 opens it to every
  Pro owner and manager, the same gate as the rest of Money (`feature: :money`), with
  no per-organization switch. An accountant gets a read-only login (stage E).

## 2. What already exists (so nothing is built twice)

**The engine (stage A, Oct 2–5).** `LedgerAccount`, `JournalEntry`, `JournalLine`
(show, production, payee and `fund_id` on every line), `LedgerPosting.post!`
idempotent per (source, kind) with restatement by reversal, `ChartOfAccounts` (33
system accounts, created on first use), `BooksReport` (groups, entries, by show,
trial balance), `BooksReconciliation` (balance, owed to payees, tax), the nightly
check, `books:backfill`.

**Every money flow already posts (stage B, Oct 5).** `BooksPoster` turns every
`OrgCashEntry` and `PayoutLedgerEntry` row into an entry; ticketing posts itself
(sales, refunds, recognition when the show happens, exchanges, disputes, passes,
products, gift certificates used, withdrawals, top-ups); `BooksOutsidePoster` posts
what people type into Show Financials (ticket sales elsewhere, other revenue, flat
fees, expenses by category), production expenses, and contract money that moved
outside CocoScout; `SalesTaxRemittance` posts tax paid (Oct 12).

**One balance for all money (stage G, Oct 25).** Every Pro organization keeps
tickets, course and contract money in its CocoScout balance (99770475); pooling
outlasts Pro with a daily sweep. `CocoScoutBalance.summary` gives available,
settling, upcoming, tax set aside.

**Invoices, half built (Round 6, Oct 5).** `ContractInvoice` numbers (SG-0012) per
organization, `InvoiceDocument` + `InvoicePdf` render the pay page and the PDF from
one object, receipts go out when paid, "Send invoice" by hand from Incoming
Payments. It only knows contract payments. The 1.4 plan's group sales expect a
payable-agnostic `Invoice` from 1.3.

**CocoScout's own books (Round 5).** `CocoScoutLedgerEntry`, `BillingInvoice` (what
Stripe billed the organization for Pro and usage), `OrgStatement` (a monthly PDF per
organization), the Stripe check on superadmin Finances. None of it is the
organization's books, but `BillingInvoice` is a bill the organization paid, and
today it never reaches their books.

**Pages.** Money hub (to-do sections, `MoneyTodoService`), Books (Accounts, Entries,
By show, Checks, on a phone since V1.1), the balance page under Books, Incoming
Payments (window filter, forecast bars, list), Sales tax (Ticketing), Staffing →
Taxes (W-9s, 1099s, `OrganizationTaxSetting` with EIN and legal name), Reports
(fixed CSV reports), Money settings (offline methods, notifications, ticket
sources), the print layout, `line_chart_controller`.

## 3. What changed since the plan was written, and what it means for 1.3

1. **Books isn't empty any more.** The deep plan assumed stage C would be the first
   thing anyone saw. Stage B and G shipped first, so every organization that sells
   anything already has full books. C is now a presentation job over real data:
   lower risk, and the Overview can be checked against the hub's numbers on day one.
2. **Three expense category lists disagree.** `config/expense_categories.yml` has
   nine (venue, tech, marketing, supplies, travel, food, staff, licensing, other);
   `ExpenseItem::CATEGORIES` has five (venue, production, marketing, talent, other);
   `ProductionExpense::CATEGORIES` has nine others (equipment, costumes, props,
   insurance…). `BooksOutsidePoster::CATEGORY_ACCOUNTS` maps only five, so tech,
   supplies, travel, food, licensing and insurance all land in "Other expenses". 1.3
   makes one list, each category an account, and lets an organization add its own.
3. **"Money owed to you" is wrong today.** Outside ticket sales, other revenue and
   flat fees typed into Show Financials post as Money owed to you / income, and
   nothing ever clears them: Ticket Tailor pays the organization, nobody records it,
   the receivable grows forever. 1.3 posts that money straight to Bank on the show's
   date (it's cash the organization got, just not through us), restates history
   with the backfill, and keeps "Money owed to you" for invoices and contract
   payments only, where a paid-by-hand record clears it.
4. **Gift certificates (Oct 30).** Sold by hand, so "Gift certificates outstanding"
   runs negative; the chart's comment says 1.3 records the sale. "Record money in"
   with the category Gift certificate does.
5. **CocoScout's bills.** Pro and usage charges (`BillingInvoice`, paid) are the
   organization's own spending and belong in their books: Software and
   subscriptions / Bank, posted from the same row CocoScout's ledger posts from.
6. **Door cash.** Cash sales sit in "Door cash" until someone deposits it. "Move
   money between your accounts" (Door cash → Bank) is the third kind of record.
7. **Sales tax set aside (Oct 12)** means the balance page already shows one kind of
   "money you can't spend". The "all your money" strip reuses that language.
8. **Contract settlement rework (Oct 16–17)** fixed who the money belongs to on a
   contract night; the books follow those rules through `Contract#settled_revenue`.
   Nothing to redo, but every Books number by show must come from the same source.
9. **Payout run notices (Oct 27) and the V1.1 phone pass** set the bar: every new
   page in 1.3 gets its phone layout (cards instead of tables) in the same commit.
10. **The pricing page and upgrade modal** will name CocoScout Books once it's open;
    `PRO_INCLUDES` and `FEATURE_DETAILS` get a line.

## 4. The screens (every Books screen, mocked)

Money hub (changed), then under Money → Books: Overview (new), Balance (existing),
Accounts (existing), Entries (changed), By show (existing), Checks (changed),
Record money in / out / moved (new, one sheet with three tabs), a recorded entry's
page (new), Bank (new), Statements (new: profit and loss, balance sheet, cash
flow), Taxes (new), accountant access and period lock (new). On the Money hub: Bills
(new) and a bill's page (new), Incoming Payments (changed: invoices to anyone, "Send
an invoice", one list of everything owed to you), a new invoice form (new). Money
settings → Books (new tab). Two phone screens (Overview, Record money out).

## 5. The build, in order

Each step is its own commits on `v1.3`, specs per flow, the related suite green under
`TZ=UTC`, `main` merged in often.

**C0. Books opens, as a section with real pages.**
- Drop `ensure_user_is_superadmin`; the hub card shows for every Pro manager.
- Books becomes a module page: `/manage/money/books` is the Overview; Accounts,
  Entries, By show, Checks keep their tab URLs. The intro says what Books is and
  isn't. Balance stays at `/manage/money/books/balance`.
- **Overview:** the "all your money" strip (CocoScout balance available, waiting on
  upcoming shows, set aside for tax, owed to performers and staff, bank per your
  books), then Money in / Money out / What's left for a period with a production
  filter and the When it moved / When earned switch, a line of money in and out by
  week (`line_chart`), income by kind and spending by category, and what's left by
  production. Reads only from the engine (`BooksReport` grows `overview(period:,
  production:, basis:)`).
- **Checks** gains "Financials vs Books": for each production, the hub's gross
  revenue and direct costs against the engine's income and spending for the same
  period, listed only where they differ. Two numbers never disagree silently.
- Pricing page, `PRO_INCLUDES`, `FEATURE_DETAILS`, the nav's active list.

**C1. One category list; the money still missing.**
- `config/money_categories.yml`: income kinds (Tickets, Products, Courses, Rental
  and contract, Sponsorship, Donation, Grant, Bar and concessions, Merchandise,
  Gift certificate, Other) and spending categories (Venue, Performer pay, Staff pay,
  Contractors, Production, Tech and equipment, Supplies, Marketing, Travel, Food and
  drink, Licensing and rights, Insurance, Software and subscriptions, Ticketing and
  card fees, Other), each mapped to a chart key; new accounts added to
  `ChartOfAccounts::SYSTEM`. `ExpenseItem`, Show Financials' expense details and
  `ProductionExpense` all pick from it (old values map across).
- An organization's own categories are non-system `LedgerAccount`s under income or
  spending (Money settings → Books → Categories).
- Outside ticket money, other revenue and flat fees post to Bank, not Money owed to
  you; `books:backfill` restates every organization.
- `BillingInvoice` paid → Software and subscriptions / Bank in the organization's
  books (kind `cocoscout_bill`), with the backfill.

**C2. Record money in, out, or moved.**
- `MoneyRecord`: `organization`, `kind` (in / out / move), `on` (date),
  `amount_cents`, `category_key` or `ledger_account_id`, `counterparty`
  (free text), `show`, `production`, `via` (bank / cash / card / other) for in and
  out, `from_account` and `to_account` (bank, door cash, CocoScout balance is never
  a choice: that's a withdrawal) for a move, `memo`, `receipt` (ActiveStorage, PDF
  or image, 10 MB, as `ExpenseItem` does), `recorded_by`. Posts through
  `LedgerPosting` (kind `recorded`): in = via account ↑ / income category ↑; out =
  category ↑ / via account ↓; move = to ↑ / from ↓. Entry date and cash date both
  `on`. Editing restates, removing reverses; a locked period refuses both (E2).
- One sheet, three tabs (tabs controller, `url: false`), opened from Books'
  top-menu links and from the Overview's empty state. Phone: full-screen sheet.
- Entries shows them as "Recorded by hand · Sponsorship · Lincoln Park Bank" with a
  receipt mark; a recorded entry's page shows the receipt, the entry's lines in
  plain words, Edit and Remove (pink modal).
- Gift certificate sales: category Gift certificate posts to Gift certificates
  outstanding.

**C3. Downloads.** Overview as CSV for the period (one row per entry, with show,
production, category, when it moved, when earned); the Statements page (E1) adds
PDFs. No machinery exposed: "Download this period".

**D1. Bills.**
- `Bill`: `vendor_name`, `vendor_email`, `amount_cents`, `due_on`, `issued_on`,
  `category_key`, `show`, `production`, `memo`, `attachment`, `repeats` (none /
  monthly / yearly, the next one made when this is paid), `status` (open / paid /
  void); `BillPayment`: `on`, `amount_cents`, `via`, `memo`. Part payments allowed.
- Posts: created → category ↑ / Money you owe ↑ (entry date = issued, cash date
  nil); paid → Money you owe ↓ / via account ↓ (cash date = paid). Cash basis sees a
  bill only when paid; accrual on issue.
- Pages: Money → Bills (open, overdue, paid; by due date or production; a month
  forecast like Incoming's), a bill's page with Mark paid (modal: date, amount, how),
  Add a bill (sheet). The hub gains a **Bills due** section after To pay.
- No paying a vendor from the CocoScout balance in 1.3: people who get paid are
  payees on the run already; a vendor is paid from the bank and recorded here.
- `BooksReconciliation` gains: Money you owe = Σ open bills' unpaid cents.

**D2. Invoices to anyone.**
- `ContractInvoice` generalizes to `Invoice` (`payable` polymorphic: a
  `ContractPayment` today, a 1.4 group hold tomorrow, or nothing: a standalone
  invoice with its own `InvoiceLine`s, `bill_to` name/email/address, `due_on`,
  `category_key`, `show`, `production`, `memo`). Numbers keep the organization's
  sequence and prefix; `InvoiceDocument`, `InvoicePdf`, the pay page, send, remind
  and receipt become payable-agnostic (what the 1.4 plan asks for).
- Paying: card on the pay page lands in the CocoScout balance exactly as a contract
  payment collected online does today; bank transfer through the payout-funding
  payment-method configuration for $500 and up (1.4 decision D5, built here);
  "Record a check" by hand (Bank ↑ / Money owed to you ↓).
- Posts: issued → Money owed to you ↑ / income category ↑ (cash date nil); paid →
  cash date set and the cash side posted from the existing rows. Contract
  payments due but unpaid post the same way, so accrual books finally carry them.
- Pages: Incoming Payments keeps its name and becomes one list of everything owed
  to you (contract payments and invoices, a Kind column), "Send an invoice" in its
  top menu, the invoice form (to whom, lines, due date, how they can pay, a note),
  an invoice's page (the existing payment page, generalized).
- `BooksReconciliation` gains: Money owed to you = Σ open invoices and unpaid
  contract payments.

**D3. Bank statement import.**
- `BankStatementImport` (file, account: Bank, period, opening and closing balance
  if the file has them) and `BankStatementLine` (on, amount_cents, description,
  state: matched / suggested / recorded / ignored, `journal_line_id`,
  `money_record_id`). CSV only; the common bank column layouts are detected
  (date, description, amount, or debit and credit columns).
- Matching: amount and a date window against Bank-account lines (withdrawals
  landing, run debits, bill payments, recorded entries, CocoScout bills). Unmatched
  lines get "Record it" (prefilled Record money in/out) or "Ignore" (a transfer
  between the organization's own accounts, a personal charge).
- The page shows the statement's closing balance against the books' Bank balance
  on that date and the lines still to deal with. Plaid is 1.5 (integrations).

**E1. Statements.**
- `BooksStatements`: profit and loss (period, basis, optional by-production
  columns), balance sheet (as of a date), cash flow (opening cash across Bank, Door
  cash and CocoScout balance; in; out; closing). Nonprofit words when the setting is
  on (Statement of activities, Net assets, Change in net assets).
- Page: Money → Books → Statements: the three, each with a print view (print
  layout), a PDF (prawn, `PdfHelpers`) and a CSV; "The whole ledger" CSV (every
  line: date, when it moved, account, amount, show, production, payee, memo, source).

**E2. Period lock.**
- `organizations.books_locked_through` (a date). `LedgerPosting` refuses a new
  entry dated on or before it (`BooksLocked`); a restatement or reversal of an
  entry inside the lock posts on the first open day instead of the original date
  (adjusting entries as reversals only). Every poster already goes through
  `LedgerPosting`, so one place enforces it. Record / Bills / Invoices forms say why
  a date is refused.
- The lock is set on the Statements page ("Lock the books through September 2026",
  pink modal), undone there by an owner.

**E3. Accountant access.**
- `BooksViewer` (organization, user or invited email, granted_by, revoked_at), the
  `TicketSalesViewer` pattern: invited by email from Money settings → Books, signs
  in or makes an account, sees Money → Books only (Overview, Accounts, Entries, By
  show, Checks, Statements, Taxes, downloads), read-only, no balance actions, no
  payees' bank details.

**F. Taxes.**
- Money → Books → Taxes, one year at a time: a Schedule C-style summary (gross
  receipts by kind; contract labor = performer and contractor pay, with the 1099
  total beside it; wages = staff pay; rent = venue; advertising; supplies; licenses;
  insurance; software; fees; other), the 990-EZ grouping when nonprofit; sales tax
  collected, paid and still set aside (from `TicketTaxReport` and remittances);
  1099s issued (from Staffing → Taxes); CocoScout fees paid. CSV and PDF. Nothing is
  filed from here.

**Phone pass** over every page above, as V1.1 did for Books (cards, the sheet
full-screen, the strip stacked). **Backfill and checks** before 1.3 merges: the
restatements of C1 run on production with a dry run first; the three existing checks
and the three new ones (Financials vs Books, Money you owe, Money owed to you) must
be clean on every organization.

## 6. Decisions (my default in brackets; Tim can change any)

1. Books opens to every Pro owner and manager when 1.3 ships, no per-organization
   switch. [Yes]
2. Money stays the nav item; "CocoScout Books" is the product name on the pricing
   page and partner pages. [Yes]
3. Outside ticket money, other revenue and flat fees count as in the bank on the
   show date; "Money owed to you" is only invoices and contract payments. [Yes]
4. One category list, every category an account, organizations can add their own.
   The three lists today disagree. [Yes]
5. Bills are recorded as paid from the bank, card, check or cash; no paying vendors
   from the CocoScout balance in 1.3. [Yes]
6. Invoices to anyone: card on the pay page into the balance, bank transfer at $500
   and up through the payout-funding configuration, checks recorded by hand. [Yes]
7. Nonprofit words (Statement of activities, Net assets) in 1.3; restricted funds
   UI later (the `fund_id` column waits). [Yes]
8. A locked period's corrections post on the first open day. [Yes]
9. Accountant access is a read-only login by email, like Ticket Sales viewers. [Yes]
10. Bank: CSV import in 1.3, Plaid in 1.5. [Yes]
11. Fiscal year starts in January unless the organization says otherwise (Money
    settings → Books). [Yes]
12. CocoScout's Pro and usage bills post to the organization's books as Software and
    subscriptions. [Yes]

## 7. Critical files

- Engine: `app/services/ledger_posting.rb`, `chart_of_accounts.rb`, `books_poster.rb`,
  `books_outside_poster.rb`, `books_reconciliation.rb`, `books_report.rb`,
  `books_backfill.rb`; models `ledger_account.rb`, `journal_entry.rb`, `journal_line.rb`.
- Pages: `app/controllers/manage/books_controller.rb`, `money_controller.rb`,
  `money_incoming_controller.rb`, `money_settings_controller.rb`; views under
  `manage/books`, `manage/money`, `manage/money_incoming`, `manage/ticket_balance`.
- Invoices: `contract_invoice.rb`, `invoice_document.rb`, `invoice_pdf.rb`,
  `contract_invoice_delivery.rb`, `contract_payment_collection.rb`.
- Money: `cocoscout_balance.rb`, `org_cash_entry.rb`, `payout_ledger_entry.rb`,
  `billing_invoice.rb`, `sales_tax_remittance.rb`, `money_todo_service.rb`,
  `financial_summary_service.rb`.
- Categories: `config/expense_categories.yml`, `expense_categories.rb`,
  `expense_item.rb`, `production_expense.rb`.
- Gating: `navigation_helper.rb`, `paid_feature_gate.rb`, the pricing page.

## 8. Verification

- Specs per flow: exact entries for each record kind, bill and invoice state;
  idempotency and restatement; the lock refusing and redating; each new check.
- `books:backfill` dry run on a production copy: the restatement of outside money
  and the new CocoScout-bill entries, then the six checks clean.
- Static renders at 375px and desktop for every page in §4.
- The full suite under `TZ=UTC` before the merge to main.
