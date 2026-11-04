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
13. Bank: files first, live later. A CSV or OFX statement import in 1.3; a live bank
    connection (Plaid) rides the integrations home in 1.5. [Yes]
14. Settle up replaces "Needs financials": the unit of work is a day, and a day with
    one thing in it is just that thing's worksheet. [Yes]
15. Square is the first register integration, optional, turned on per organization
    in Organization settings → Integrations, connected with Square's own sign-in
    (OAuth), never pasted keys. [Yes]
16. Register money reaches the books only when its day is settled, never straight
    from the pull. Tips are never split automatically; the day's worksheet asks. [Yes]
17. Tips go to payees through the payout run, or are marked paid in cash at close.
    No other rail. [Yes]

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
- Settle up (§9): `show_financials_controller.rb`, `_worksheet_modal.html.erb`,
  `money_financials_controller.rb`, `money_todo_service.rb`, `staff_time_entries`
  and shift assignments (who worked), `organizations_controller.rb` and its
  `section/:section` routes (the Integrations section).

## 8. Verification

- Specs per flow: exact entries for each record kind, bill and invoice state;
  idempotency and restatement; the lock refusing and redating; each new check.
- `books:backfill` dry run on a production copy: the restatement of outside money
  and the new CocoScout-bill entries, then the six checks clean.
- Static renders at 375px and desktop for every page in §4.
- The full suite under `TZ=UTC` before the merge to main.

## 9. Added 2026-10-31: settle up, Square, and the integrations home

Tim's additions after the first review (his words, condensed): the organization
makes money several ways, tickets and shows being one and the bar, on Square,
another; the dream is Square tied in by API, each organization turning on its own
integrations, pulled daily with callbacks; tips from the bar assigned to the people
who worked, on a worksheet that someone checks off, never automatically; and the
whole financial system reworked around "here's what you need to do", the way Home
does it: a daily settlement that consumes the day's worksheets, with each show
still having its own, collapsing to one when the day has one thing.

### 9.1 The bank: files first, live later

Import in 1.3, live connection in 1.5. The matching page (§5 D3) is the same
either way: a line from the bank, a match on the books, or a Record button. Built
on a statement file now, it loses nothing when the lines start arriving by
themselves. A live connection means Plaid: a per-account monthly fee, a
production-access review that takes weeks, and a second live integration to get
right in the same release as Square. Square is the one live integration 1.3 needs
to establish the pattern (an organization-level connection, a daily pull, callbacks,
a pull log, a Pull now button), and the bank rides that pattern in 1.5 next to
Eventbrite and Ticket Tailor.

### 9.2 Settle up: the day is the unit

Today each revenue show has a financials worksheet (ticket count, revenue, other
revenue, expenses, a data-confirmed check), and the Money hub lists "Needs
financials". That stays as the per-show piece. What changes:

- **A settlement day** (`SettlementDay`: organization, date, status open/settled,
  settled_at, settled_by) wraps everything with money that happened on one date:
  each revenue show (its existing `ShowFinancials`), classes that met, register
  sales from Square, door cash counted, tips, expenses dated that day. A day with
  one show is that show's worksheet with the day's name on it; nothing is added
  until there is something to add.
- **The day's worksheet** is one page, section by section, each with its own
  "Looks right" check: each show (tickets online, at the door, comps, adjustments:
  refunds, price fixes, outside tickets; products at the door; flat fee or outside
  revenue; expenses), the bar (Square's numbers, read-only, by category, with
  "doesn't look right?" to re-pull or correct by hand), tips (§9.3), door cash
  (expected from the door session vs counted, over or short explained), classes,
  and other expenses. **Mark the day settled** when every section is checked.
  Settling posts the day's outside money, register sales, fees, tax and tips to
  the books in one go (kind `settlement`); a settled day can be reopened, and the
  books restate by reversal as always.
- **Production settlements don't change.** Contract shares, the show payout, and
  payout runs still read `ShowFinancials`; the day confirms them, it doesn't
  replace them.
- **The to-do strip.** The Money hub's first thing is a `shared/_alert_panel` list:
  days to settle (with the oldest date), tips to split, bills due this week, bank
  lines to sort out, money overdue to you, payouts waiting. `MoneyTodoService`
  grows the new sections; Home gets one Money line ("4 days to settle up") and a
  show row's "Needs financials" chip becomes "Settle up".
- **Settle up** takes Financials' place as the first card on the hub; the
  per-production Financials pages stay as the record by production.

### 9.3 Square, and the integrations home

- **Where it lives:** Organization settings → Integrations, a new section next to
  Services. It is the organization's, not Money's, because 1.5's Eventbrite,
  Ticket Tailor and the bank join it. Money → Settings gets a line pointing there.
  Each integration is a card: Square (connect), Clover and Toast (on the roadmap),
  Eventbrite, Ticket Tailor and your bank (1.5).
- **Connecting:** "Connect with Square" sends the owner to Square's own sign-in
  (OAuth); we store the tokens encrypted (`Integration`: organization, provider,
  status, credentials, settings, connected_by, last_synced_at, last_error). No
  pasted keys on the page; a sandbox key field exists only for superadmins.
- **Square's page:** the locations on their Square account, each mapped to one of
  our locations (or "not ours", for a second business on the same account);
  Square's item categories mapped to our money-in categories (Bar, Food, Merch,
  Other); what comes in: sales by category, tips, sales tax collected, refunds,
  Square's fees, net deposits; the schedule: every morning for the day before,
  Square's webhooks during the night so a day is filling in before anyone looks,
  and Pull now; the pull log (when, how many orders, errors).
- **Data:** `RegisterDay` (integration, location, business date, by-category sums,
  tips, tax, refunds, fees, net, order count, pulled_at) is what the day's
  worksheet reads; raw orders are kept 90 days for a drill-down and then dropped.
  A Square business day follows the location's closing time (a 1 AM sale belongs to
  the night before), which is also how the door works.
- **Books:** nothing posts on pull. When the day is settled: register sales to
  income by category, Square's fees to Payment processing fees, sales tax collected
  to Sales tax set aside (the Sales tax page shows Square as a second source, with
  its own remittance line), refunds against income, tips to **Tips owed to staff**
  (what you owe), and the net to **On its way from Square**, cleared when the bank
  page matches the deposit.
- **Tips:** the day's worksheet shows the tip total and who worked, pre-filled from
  Staffing's shifts and hours that day; split evenly, by hours, or typed; each
  person's share goes to their next payout run (the one rail) or is marked "paid in
  cash at close" and comes out of door cash. Nothing is split until someone checks
  the section.
- **Other registers with APIs,** for the roadmap: Clover (REST API with OAuth,
  common in bars) next, then Toast (API through its partner program, restaurant
  heavy), Lightspeed, Shopify POS for merch. Stripe Terminal is already ours at the
  door. Each is one adapter behind the same `RegisterDay`.

### 9.4 Build order, revised

C0 → C1 → **C4 Settle up** (days, the worksheet, the to-do strip; before Square so
the bar has somewhere to land) → C2 → C3 → **G1 Integrations home + Square**
(connect, pull, RegisterDay, the worksheet's bar and tips sections, books on
settle) → D1 → D2 → D3 (file import) → E1 → E2 → E3 → F.

### 9.5 Screens added or changed (canvas row 7)

(See also 9.6 to 9.11, Tim's second round the same day, canvas row 8.)

- Money hub: the to-do strip at the top; Settle up is the first card (changed).
- Money → Settle up: the list of days, each with its pieces and state (new).
- A day's worksheet: Friday Oct 24 with two shows, the bar, tips, door cash (new).
- Organization settings → Integrations (new).
- Square's page: locations, categories, schedule, pull log (new).

### 9.6 When a day ends: smart days (Tim, 10/31, second round)

A theater's day doesn't end at midnight. Shows end at 11:30, the bar rings until
12:15, the staff clock out at 2; that's all Friday's money. So:

- **Money → Settings → Settle up** gets "When a day ends", **on by default: when
  things stop.** A day starts at 6 am and runs until two quiet hours after the last
  thing that happened: a ticket scanned or sold at the door, a bar order, a staff
  clock-out, a door session closed. Nothing before 6 am is ever tomorrow. The
  page explains it in those words, with the Friday example.
- **Off: at midnight.** Strict by calendar date in the organization's time zone, for
  anyone whose accountant wants it that way.
- The rule decides which day a Square order, a door sale, a cash count and a
  staff shift belong to, so a Square pull reads until the day actually ended.
  Square's own "night ends at" setting goes away; its page says "days follow your
  Settle up setting". Online ticket sales are unaffected: they count on show
  night either way.
- Stored as `organizations.settlement_day_mode` (`smart` / `calendar`) and
  `settlement_day_starts_at` (default 6:00). `SettlementDay.for(time)` is the one
  place that answers "which day is this?", and everything that files money by day
  calls it.

### 9.7 Reopening a settled day

A settled day can be reopened, changed and settled again: a share charged a
little less because someone did a great job, a count fixed later. Reopen asks
why (kept with the day). Nothing changes until something is edited and the day
is settled again; then the books restate by reversal (old entries reversed, new
ones dated the original day, both kept, as always). If a payout run already paid
out of that day, the difference rides the next run as an adjustment, up or down;
a contract share already paid becomes money owed one way or the other, on the
Owed to you page or as a bill. A reopened day shows on the to-do strip again.

### 9.8 Outside tickets are a worksheet, shared with Ticketing

Not one box. The outside-tickets line on a show opens a pop-up: each outside
source (Eventbrite, HotTix, named in Money settings) by each ticket type (14 VIP
for $630.00, 26 GA for $650.00). These are `TicketOutsideSale` rows (listing ×
tier × source), the same ones the show's ticketing page already shows and edits,
so a number typed while settling up appears in Ticketing and the other way
round. Each type's remaining seats shrink by its count, as today. The source's
total feeds the show's ticket line.

### 9.9 The day's page: pick any day

The day worksheet's header has the previous and next day on either side and the
shared month calendar (`shared/_month_calendar`) in the middle, opening on the
date; days with money in them are marked, settled ones ticked.

### 9.10 Integrations page sections

Registers and bars; Tickets sold elsewhere; Your bank (its own section). No
"already part of CocoScout" section.

### 9.11 Access by module (an extension of the organization team)

Today an organization's people are owners, managers, viewers or members, plus
production team managers on productions, Ticket Sales viewers, door access
grants, and (planned, E3) accountant seats. Tim wants to bring in a bookkeeper
without handing them contracts, mailing lists, courses and the rest.

- **One idea:** every grant is "this person, this module, this much": none, view,
  or manage. Money splits a little finer, because that's where it's needed:
  Settle up, Payouts, Bills and invoices, Books, Money settings. Productions keep
  their production team managers as they are.
- **Templates** fill the grid; the grants are what's stored, so a template is a
  starting point, not a role to maintain: **Owner** (everything, the organization
  itself), **Manager** (everything but the organization's own settings and billing,
  today's manager), **Bookkeeper** (all of Money: settle up, record, bills,
  invoices, Books; payouts to review but not send; view Staffing hours and
  Contracts), **Accountant** (view and download all of Money, change nothing;
  replaces E3's seat), **Box office** (Ticketing, the door, Products; view Shows),
  **Show scheduler** (Shows and events, Contracts, Casting; view Money's Settle up
  for their shows), **Education manager** (Courses and their contracts, Sign-ups;
  view Money for courses), **Marketing** (Mailing lists, Documents, the public
  pages). Custom is any grid.
- **Where:** Organization settings → People, which is the organization team page
  reimagined: a row per person with their template chip, and a sheet per person
  with the template picker and the grid. Ticket Sales viewers and door access
  grants become rows here with the Box office template; the accountant seat is
  the Accountant template. Invitations work as today (search first, create only
  when nobody is found).
- **Underneath:** `OrganizationRole` keeps `company_role` for owner/manager; a
  new `module_grants` (jsonb: module → none/view/manage) on the role, read by one
  helper (`can?(:manage, :books)`) that every module's gate and nav item calls.
  Pro modules stay owners-and-managers-only by default; a grant is how a
  non-manager gets in, which keeps [[pro-modules-managers-only]] true in spirit:
  the owner decides who sees what.
- **Sizing:** it touches every module's gating, so it is its own piece of work,
  best done first in 1.3 (before C0) because Books needs the bookkeeper and
  accountant templates and E3 collapses into it. Two to three days of plumbing,
  most of it replacing scattered `before_action`s with the one helper.

### 9.12 Decisions added in the second round

18. Smart days on by default: a day runs from 6 am until two quiet hours after
    the last thing that happened; "at midnight" is the switch. [Yes]
19. A settled day can be reopened with a reason; differences restate the books
    and ride the next payout run. [Yes]
20. Outside tickets are TicketOutsideSale rows, edited from either Ticketing or
    the day's worksheet. [Yes]
21. Access by module, with templates, replaces the accountant seat and absorbs
    Ticket Sales viewers and door grants; built first in 1.3. [Yes]
22. The Overview's money strip is four boxes: the CocoScout balance with the sales
    tax set-aside shown inside it ("$236.16 of that is set aside for sales tax you
    owe"), waiting on upcoming shows, owed to payees, bank. [Yes]

### 9.13 The bank file upload says what happens to the file (Tim, 10/31)

Where a statement file is uploaded (Books → Bank), the page makes it plain, in words
and not with lock clip art, that nothing is kept: the file travels over an
encrypted connection; CocoScout reads the transactions out of it once, in the
request, and deletes the file the moment they're in; the transactions kept are
date, amount and the bank's description only, never an account number or login;
CocoScout never asks for bank credentials to import. This sits as a short
"What happens to your file" panel beside the upload, with one line per promise and
a check mark per line, and the same words in the Integrations → Your bank section.
The code must match the words: the upload is read from the request body (or a
temporary file deleted in an `ensure`), never attached to anything.

### 9.14 Tips go to whoever was working (Tim, 2026-11-03; built the same day, §10 item 19)

At Stars & Garters the bartender on when a round rings up gets that round's
tip, two bartenders on at once split the rounds that came in while both were
on, and a bar back takes 15%. Those are the organization's rules, so they live
in settings, and the day's worksheet applies them.

- **Where:** Money → Settings → Tips. One switch, "Work out the split from who
  was working", off by default. Off, the day's tips section is what it is now:
  a split typed by hand, evenly or by hours. On, the worksheet opens already
  split, and anyone can still change it.
- **The rule, in the organization's words:** "Tips go to the people on the bar
  when the sale rang up." Its pieces:
  - *Who shares them:* each of Staffing's roles is in or out. A role that is in
    shares equally by the clock (Bartender) or takes a fixed cut off the top
    first (Bar back, 15%). Door and box office are out unless said so.
  - *By the clock:* every order has its time (Square's orders, and door sales
    the same), and Staffing knows who was on then: the clock-ins when there
    are any, else the scheduled shift. A bartender alone from 6 to 8 keeps the
    tips rung up from 6 to 8; from 8 to 10 two of them split what came in
    while both were on.
  - *Nobody on:* tips rung up when no sharer was clocked in or scheduled go to
    the pool and split evenly among the night's sharers; the worksheet says so
    ("$31 from 9 orders with nobody on the clock, split evenly").
- **Without Staffing** (the module off, or no shifts that day): the clock has
  nothing to read, so the section stays the by-hand split; the roles setting
  still says who is listed, in what order.
- **On the worksheet:** a row per person with the span they worked (6:00 to
  8:00 pm), their share, and a line saying how ("from 17 orders while on; plus
  a share of the pool"). Add a person and the span they worked; change anyone's
  span or share; each row still goes to the payout run or is paid in cash at
  close. Changing a span works the other shares out again; a typed share stays
  as typed and the rest adjust around it. "Looks right" checks the piece as it
  does today, and settling the day sends each share where it goes.
- **Data:** `TipRule` per organization (on or off, a share per role: equal or a
  percent, what to do with tips nobody was on for). A tip share row gains the
  span worked and whether it was worked out or typed. A register day keeps its
  tips by quarter hour (`tips_by_time`, jsonb), so the split reads from the day
  itself and never from raw orders, which go at 90 days.
- **Build order:** the settings page and `TipRule`; tips by time on the Square
  pull; the worksheet's computed split with spans; add a person and adjust;
  specs for a two-bartender night, a bar back, and a span with nobody on.
  After Tim's yes to this section.

## 10. Build log (2026-10-31)

Built in one pass on `v1.3`, in the plan's order; each phase is one commit.

1. **Access by module** (4e103c9d): templates and a None/View/Manage grid on Organization settings → People. The accountant seat (E3, "BooksViewer") collapsed into this: an Accountant template is a viewer of every money module.
2. **Books opens** (a6d2f746): the Overview, the hub card for every Pro manager, Financials vs Books on Checks.
3. **One category list** (df29a7c0): outside money to Bank, CocoScout bills on the organization's books.
4. **Settle up by day** (58263665): one worksheet per day, smart days, reopen with a reason.
5. **Record money by hand** (43c54246): in, out or moved, with the receipt; Books downloads the period.
6. **Integrations home and Square** (7f45ce88): connect, pull, the day's bar and tips; the books post on settle. Square's net goes to Bank (no "On its way from Square" account yet).
7. **Bills and invoices** (c13999f3): Money → Bills (overdue / this week / later; repeats), Send an invoice to anyone (`Invoice`, beside the older `ContractInvoice`), their pay page. Posting is remainder-based: the bill carries its unpaid amount in "Money you owe", each payment clears part of it. The "owed to you" reconciliation check is deferred: invoices and contract payments share the account.
8. **Bank statements** (4fdc5da8): CSV or OFX read once in the request and never stored; fingerprint dedupe; exact-day match vs ±5-day suggestion; Record it / Ignore / Reopen.
9. **Statements, closed months, Taxes** (05958ed4): P&L (one column or by production), balance sheet, cash flow; print, PDF, CSV, the whole ledger as CSV; lock through a month end (owner or superadmin unlocks). A restatement that lands in a closed month shifts to the first open day with a note in its memo, so closed months never change. Money documents (bills, receipts, W-9s, statements) are keyed under `organizations/{id}/…` in the one private bucket and served through `Manage::MoneyFilesController`, which checks the organization and the module before handing out a five-minute link.
10. **Who pays the tax on tickets other sites sold** (46a1dfd0, Tim's question 10/31): a choice per ticket source on Money settings → Ticket sources (none / they pay it / we owe it). A "we owe" line carves the tax out of what arrived at the ticket tax rate into Tax to pay the government; the Sales tax page shows it by source for the period (in the bank, not set aside), the Taxes page and the reconciliation count it. 1.5's Ticket Tailor and Eventbrite imports will read the same switch and true up these lines with each order's own tax.
12. **Where Settle up starts** (Tim, 2026-11-01): `organizations.settle_up_starts_on`. Days before it are history: never listed or counted, readable, never changed. The migration is the deploy's one-time switch (`SettleUpStart.convert_all!`): every existing organization starts on the first of the month the deploy runs in, and days since then already confirmed in Financials, with no door cash or register in them, are marked settled without posting anything. Owners move the date in Money settings → Settle up. Rehearse it by seeding dev from production (`bin/seed_dev_from_prod`, on main) before shipping.
11. **Phone-width pass**: every Books page rendered at 375px (static renders through the test stack, since the dev server is Tim's); one fix, the settle-up day calendar popover now spans the phone screen.
13. **Sections, not tabs; the check through today** (2026-11-02): Books is a landing page with the sections as cards (`shared/module_header`, the way Money has them) and a page per section under breadcrumbs (`/manage/money/books/accounts|entries|shows|checks`, `/statements`, `/taxes`, `/bank`); the settings tab strip is gone. Record money is a modal on every Books page. Financials vs Books compares through today, since a show still ahead has presales Financials count that the books hold until the day after. With main's 2026-11-02 fixes (contract money owed from the date it's for, rehearsals and service charges beside the settlement, the share rounded per settlement, the live contract over a cancelled one), Stars & Garters' this month and last month show no disagreements. The deploy-day backfill (`BooksBackfill.run!`, dry run first, then `dry_run: false`) was rehearsed on the dev copy of production the same day: 15 organizations, no mismatches, every trial balance zero; Stars & Garters' Bank went from −$31,400 (spending with no income beside it) to +$47,287 once outside ticket money moved to Bank, with $772 owed to you and $517.50 owed to contractors.

14. **Bank rebuilt** (2026-11-02, after Tim's first real statement: 1,256 lines to deal with, every description "DEBIT" or "CREDIT", 13 matched): the page is the transactions as the bank knows them, full width, a row per line with Yes/No, Record it or Ignore at the right, a month menu and in/out filters, 100 to a page, "Yes to all N suggestions"; bringing a statement in is a modal from the top-right button, with the statements already in (each removable). The upload only parses and saves the lines; `BankStatementMatchJob` matches them in the background (the page says so and refreshes itself) and sends a `bank_statement_ready` notification (new "Books and bank" group). The parser takes the most descriptive column (Chase's "Details" column lost to "Description"), reads a running Balance column into the closing and opening balances, and keeps two identical lines on a day as two. The matcher looks two weeks either side, scores by closeness, shared words between the bank's description and the entry (memo and counterparty) and kind hints (STRIPE, HOTTIX, COCOSCOUT), is sure only when the same day and alone or named and clearly ahead, and finds the one group of entries that adds up to a deposit (a ticket seller paying several shows at once; `journal_line_ids`). A line remembers a key of its description, so Record it starts from what was recorded for the same payee last time. Nothing bounces to another page: Yes, No, Ignore, Undo and the Record this line modal (the Record money form, filled from the row by `bank_record_controller.js`) answer with a Turbo Stream that swaps the row and moves the tiles and counts (`BankStatementStreams`, `BankStatementSummary`); a mistake comes back into the open modal. Newest first. **Bank rules** (`BankRule`, `BankRules`, the Rules button and a Rule link on every line): when the bank's description has a phrase in it (several, comma-separated, any counts) and the money goes the way the rule says, the line is recorded as a category and payee (for a production, optionally) or ignored; a rule runs over the lines waiting when made, changed or applied by hand (in the request up to 30 lines, else `BankRulesApplyJob` with a `bank_rules_applied` notification) and, with on_import on, over every statement brought in later after the matching. The rule form counts the lines waiting it fits as the phrase is typed, and each rule on the Rules page says how many it would catch now, with Apply (the Rules modal and the suggested rules it held were replaced by item 17 on 11/3). A line's row shows one button (Record it, or Yes for a suggestion); Ignore, No, Make a rule, Open and Undo sit in the shared ⋯ menu, which the row swap keeps right. In the Record money form, and in the rule form, the production and its date sit behind two switches (a rule can record to one date, `bank_rules.show_id`), and so does "Also run it on statements brought in later".
15. **Books starts with its categories** (2026-11-02, Tim's question about where bar stock goes): `/manage/money/books/setup` (`Manage::BooksSetupController`, `BooksCategorySetup`) asks what kind of organization this is (a venue, a performing company, a venue with its own company, a school or studio) and seven yes-or-no questions (drinks or snacks, merchandise, classes, paid staff, pay rent, rent the space out, nonprofit), and recommends the built-in categories those answers are for (`for:` in `config/money_categories.yml`; none means everyone; `always:` can't be dropped), each to keep or not, with the organization's own added on the same page. "These are my categories" stamps `organizations.books_categories_set_up_at/_by`, keeps the answers (`books_profile`), sets `books_nonprofit` from the nonprofit answer, and hides the ones said no to (`money_categories_hidden`, "spending:travel") from every picker, never from a row already in one. Until then every Books page sends a manager there (`BooksCategoriesGate`, on Books, Statements, Taxes, Bank, rules and Record money); someone who can only look isn't asked. The Money landing's Books card says "Start by setting up your categories" until it's done, and Money settings → Books lists what's offered and what isn't, with the setup page as the one place to change it. New built-in categories, each with its account: Bar purchases and Merchandise purchases (what's bought to sell; the tax summary's cost of goods line), Utilities, Repairs and maintenance, Accounting and legal, Bank fees, Instructor pay, Fundraising costs, and for income Memberships and Fundraising events. The organization factory stamps the setup, so the rest of the suite sees Books as it was.
16. **The category is picked from a sheet of our own** (2026-11-02, Tim couldn't tell Bar purchases from Food and drink in a plain menu): `shared/category_picker` (`category_picker_controller.js`) replaces the `<select>` on Record money, the bank rule form, Bills and Invoices. A button shows the choice with its line underneath; the sheet (pink header, "What is it for?" / "What kind of money is it?") lists every category the organization offers, alphabetical with Other last, each name over what goes in it, with a box to find one when the list is long. `MoneyCategories.spending_choices/income_choices` is the list; `spending_options/income_options` read the same order, so every menu agrees. The rule form keeps one picker per direction, the one not in use disabled; `bank_rule_controller` and `bank_record_controller` set it through the controller (`set(key)`). A category of the organization's own carries a description too (`ledger_accounts.description`): the setup page's "Add your own" rows take a name and what goes in it, and so does Money settings → Books.
17. **A year of bank lines, sorted with you** (2026-11-03, Tim's first full statement: 1,400 lines, and the suggested rules were weak): **payees** (`BankPayees`) read who a line is from or to the way the bank writes it: a bank draft's `ORIG CO NAME`, a payout from a payment provider (`IND ID:ST-`), a Zelle name without its reference, an online payment's payee, a card merchant before the reference, phone, store, state and date, plus transfers between your own accounts, checks, deposits, withdrawals and fees; spellings meet on their letters (THE HOME DEPOT and HOMEDEPOT.COM are one payee, 92 payees now cover 940 of Stars & Garters' 1,076 waiting lines where the old grouping made 243), and look-alikes (Timothy and Tim, Stripe and the organization's own payout name) are offered beside each other. **Rules is a page** (`/manage/money/books/bank/rules`): what rules are for, three tiles, "Sort what's waiting", the payees without a rule most lines first (Make a rule, filled in), and the rules with Apply, Edit and Remove; a rule has its own page (`/rules/new`, `/rules/:id/edit`, `bank_rule_controller.js`) with what it catches counted and listed as the phrase is typed, and how many done lines agree with it. **Sorting** (`/manage/money/books/bank/sort`, `BankSort`, `BankSortController`, `bank_sort_controller.js`; the bank page offers it from 50 lines waiting): part 1 is one payee a screen, most lines first, with what the bank calls it, how often, what it added up to, its spellings, its look-alikes to take on the same rule, three of the lines, and a guess when the kind gives it away (a provider is Tickets, a fee is Bank fees, a steady Zelle is Staff pay); record every time or ignore every time writes the rule and runs it over the payee's open lines (lines the matcher found something for are held for part 2), it varies dismisses the payee (`bank_rule_dismissals` keyed by payee), skip puts it off and the skipped come back once. Part 2 is one line a screen, newest first: the categories used most as chips, Ignore with a note (`bank_statement_lines.note`, shown in Dealt with), Yes to the match the matcher found, or Something else… on the category sheet, and any answer can become a rule for the payee. The pass is a `BankSortPass` per person (it started in the session cookie, which 70 skipped payees overflowed); Stop for now loses nothing. **Rules travel** (`BankRulesFile`): Export rules writes a JSON file of the organization's rules and Import rules reads one back, skipping rules already there and categories the organization doesn't offer, so a set built in dev goes to production. Mock-ups were approved first (Tim: "Yes, build it").

18. **Square, end to end on the sandbox** (2026-11-03): the first real round trip, from Tim's Developer Console application (named CocoScout, "All Square sellers", sandbox keys in the worktree's `.env` as `SQUARE_APPLICATION_ID`, `SQUARE_APPLICATION_SECRET`, `SQUARE_ENVIRONMENT=sandbox`, redirect URL `http://localhost:3000/manage/integrations/square/callback` on the app's OAuth page, Sandbox toggle). Two things about the sandbox itself: its authorize page answers a blank 400 unless the browser already holds a sandbox seller session (open the test account from the console first; production has no such rule), and the Application Secret is on the OAuth page where the Credentials page shows an access token, which is what got pasted first and what Square's bare "Not Authorized" meant. So Connect with Square now stops with that in plain words (644a3b2f, with the controller's request spec: connect, the state check, Square's error answer, a failed exchange, the mappings, Pull now, disconnect). The first night turned up three sync fixes (f840eefa): the sync built each day through the integration's `register_days` and the has_many autosaved every quiet day when the integration saved at the end of the pull; a refund comes back from Square as an order of its own (no lines, a return) and was counted as an order; and a register category whose name speaks for itself (Bar, Drinks, Merch, Snacks) now maps to ours until someone chooses. Verified for real: connect and the callback, the catalog and locations, a forced token refresh (expiry set two days out; the sandbox issued a new token and a new 30-day expiry), orders, tips, tax and a refund into a `RegisterDay` on Settle up. Square fills in a payment's processing fee a moment after the sale, so a pull seconds later reads no fee; the 5 am pull of the night before always has them. Data for development: `square:sandbox_orders NIGHT=friday` rings up a night on the sandbox, order by order, with the sandbox seller's own token (`SQUARE_SANDBOX_ACCESS_TOKEN`, the Credentials page one; it can write where the OAuth token is read only), a bar list from $3 candy to $16 cocktails, tips, tax and a refund or two, a Thursday or Sunday about $300 and a Friday or Saturday about $1,000; Square stamps every order with the moment it is paid, so a night rung up lands on today. `square:dev_register_days WEEKS=10` fills the past weeks' Thursdays to Sundays straight into register days (development only; the last 7 days stay clear because Pull now re-reads them). **For production, Tim's steps:** on the same Developer Console application, flip the toggle to Production and put the production Application ID and Application Secret in the server's credentials (`square.application_id`, `square.application_secret`; no `environment`), add `https://cocoscout.com/manage/integrations/square/callback` as a redirect URL on the OAuth page's Production tab, and under Webhooks (Production) subscribe `https://cocoscout.com/webhooks/square` to `order.updated`, `payment.updated` and `refund.updated` with API version 2026-01-22, then put that subscription's signature key in credentials as `square.webhook_signature_key`. The webhook cannot be exercised from localhost; its signature check has its request spec.

19. **Tips go to whoever was working** (2026-11-03, §9.14, on Tim's "Yes, build it"): `TipRule` per organization (Money → Settings → Tips: the one switch, off by default, and each Staffing role out, sharing equally by the clock, or a fixed percent off the top; `MoneySettingsController#update_tips`); the Square pull keeps each day's tips by quarter hour (`RegisterDay.tips_by_time`, keys UTC quarter starts, `{cents, orders}`; `SquareSync.quarter_key`; `square:dev_register_days` draws them for seeded nights); `TipSplit` works the day out (a quarter's tips to the equal-share people on, a percent role's cut off the top first and split among its people, nobody on → the pool, split evenly; a typed share stays and the rest scale around it; largest remainder so the rows add up to the register's tips); `SettleUp.workers` now carry spans with a role (a saved share's span when set by hand, else the logged hours, else the scheduled shift) and `Tips` knows `by_rule?`, `rows`, `pool`. The worksheet opens already split when the rule is on and the register has times and someone in a sharing role was on: a row per person with the span (time inputs), the share, how it was worked out ("From 32 orders while on, plus $20.00 from the pool."), the pool line, Add a person with a span and a sharing role, Off, Work it all out again; otherwise the by-hand split as before, with a line saying why. `tip_shares` gained `worked_from`, `worked_to`, `source` (computed/typed) and `house_role_id`. **Tim's pass the same evening:** the worksheet shows a summary to read (a row per person: span, share, how, where it goes; the pool line) with Looks right beside it, and every change happens in a Change the split modal (spans, shares, Take off, Add a person who worked, Work it all out again; by hand: evenly, by hours, as typed); with the rule on, only people in a sharing role appear anywhere, and Add a person offers staff qualified for one. And settling puts nothing on the payout run: each share waits on Pay People with the approved hours (`TipShare.waiting_for`, "Pull in tips" fills each person's tips-by-day worksheet, `tip_share_ids` tie them to the run's Tips line when the week's pay goes on; reopening a day takes a share back off a draft run). **Also:** the Settle up calendar's dots now say where a day stands (green settled, amber to settle, gray not over yet or history) with a legend, not just that it had money (Tim). **Tim's second pass, later that night:** the tips belong in the Square card, so the separate Tips section is gone: the register card ends with a "Tips, $X · who gets them" block (the rule's summary, a row per person, Change the split), and the card's one Looks right covers the tips too (it writes the split as it stands, so settling pays the rows; `check_register`). There is no pool any more: a stretch of time with nobody who shares on the bar is a question for the manager, asked by stretch rather than by order (`TipSplit::Stretch`: quarters with no equal-share person on join into one stretch while nobody was on in between; "Nobody on the bar 11:30 pm to 1 am: $23.00 from 9 orders"). The modal's "Nobody on the bar" block takes an answer per stretch, kept in `settlement_days.tips_unstaffed` by the stretch's first quarter: the house keeps it, split between everyone listed, or one person. Until each stretch is answered the register can't be checked, and the money stays with the house; what the house keeps posts on settling as `other_income` "Tips kept by the house" against `tips_owed`. Also from this pass: a saved share puts nobody on the list unless it's in a sharing role, a split the page suggested is never saved as typed (the first build had saved its even split as "typed in"), and saving by the rule drops the shares of anyone the rule leaves out. Specs: `tip_split_spec` (two bartenders, bar back, the stretch with nobody on and its three answers, typed, when it doesn't apply), `settlement_days_spec` "tips by the clock" (incl. the stretch flow and the refused check), `square_sync_spec`.

20. **Confirm marks, the ring, and paying people from the day** (2026-11-04, mocked first at https://claude.ai/artifact/9yvSRvoo2iQ3Rw8WvPjFSm, Tim: "I love all of this"; his pass the same afternoon folded in): "Looks right" meant "I confirm this", so each card ends in a round **confirm mark** (`settlement_days/_confirm_mark`: hollow, pink and lit once confirmed with the time beside it, amber-dashed and disabled while a question holds it with the reason under the word; it is an icon-only toggle, the one place a button isn't `shared/button`). The pinned bar is **one ring** (`show.html.erb`): a segment per piece of the day, pink once confirmed, amber while held, grey until then, the count in the middle and a check once every piece is; then the sentence (what's left, or the holds in words, or what settling puts on the books and the run) and Settle the day. The box keeps its shape whatever the day holds (Tim: no names under dots, just how far along we are). **Who gets paid** (`_pay_block`) sits under each show's money as one line, the people behind a click (`disclosure`; a card opens on `?open=<show id>` after Calculate or a choice on one of its lines): a cast show reads "$270.00 to 7 people · Clay Smith Productions" with how its lines stand ("5 on the run when the day settles, 2 held"); a contract show "$304.00 by contract to Stella Mahler · Paid Nov 1" with The contract; a production that pays nobody says so. **The Calculate step** (Tim: "I should always be able to calculate based on the numbers that are there"): `SettleUp.pay_for` says where the calculation stands (`Pay#calc`: `no_cast`, `needs_numbers`, `uncalculated`, `stale`, `locked`, `current`), the line says "not worked out yet; from the numbers as they stand, $114.99 to 3 people" with Calculate, or "the numbers changed since this was worked out Nov 4 at 11:00 am; as they stand now, $120.00 to 3 people" with Recalculate (`numbers_changed_since?` reads the financials, the cast and the outside sales against `calculated_at`; confirming restamps it so a confirm never reads as a change), and the mark waits on it ("Calculate the payout first", "The numbers changed; recalculate first"). `SettlementPayer.calculate!` runs the calculation keeping each line's choice (`show_payout_line_items.pay_choice`: run or hold; paid another way is the old `manually_paid`), never over lines paid or on a run (`locked`). Each line has a `<select>` (On the run when the day settles / Hold, not yet) and Paid another way (a modal: how, when, a note; Undo while it isn't on a run); "Change who's paid or how it's split" opens the show's payout page and comes back. **How the production pays**, asked on the day (`_calculation_modal`, `choose_calculation`): one of the organization's calculations for every show of the production from now on (`make_production_scheme!`) or just this one (the production then asks for each show: `productions.payout_calculation_mode` production/each_show, also on the Pay tab), or nobody is paid (`pays_performers` off); a new calculation goes through the wizard and comes back. **Settling puts the payouts on the run** (`SettlementPayer.stage!` after `SettlementPoster.post!`): every "on the run" line through `PerformerPayoutRunService` and every contract share due for the night through `ContractorPayoutRunService`, onto the organization's open draft; nothing rides it before (the show's payout page says "these go on the run when <day> is settled" instead of Add to payout run, the contract row says "Settles with Oct 30", and the Money hub's To pay leaves such shows out). **Reopening takes back** whatever is still on a draft (`unstage!`, through `PayoutRunRemoval`); paid lines stay. Hand edits to a show's money from the day (other revenue, expenses, outside sales) unconfirm it. Specs: `settlement_days_spec` "pays people" (asked how the production pays, each-show and nobody, calculate → confirm → hold one → settle → reopen, the numbers changing under a calculation, paid another way, the hub and the old pages). The spec found a real bug on the way: the dry-run payout built with `ShowPayout.new(show:)` hung off the show as an unsaved record, so the first calculation created line items on nothing. **Tim's second pass, that evening:** the whole "Who gets paid" line opens and closes the people (a click anywhere on it; the buttons on its right keep theirs, `disclosure#keep:stop`); a person's row is the amount, a chip only when it isn't simply on the run (Held, Paid another way · Cash, On the payout run), and the payout page's ⋮ menu (`show_payouts/_row_menu`, which now submits a form by id): Hold, not yet / Back on the run, Paid another way…, Change the amount…, Take off this show's payout; and **Who's paid and how** is a modal of its own (`_pay_modal`) in place of a trip to the show's payout page, which is on its way out like the financials page: the calculation with its rules in words (Use a different calculation opens the chooser, preselected; Back to the calculation drops a customization), pay this show differently (everyone the same amount, or each their own, the payout page's `save_override` with the fixed-pot check), the people with Take off, the cast not on the payout with an amount each, Add someone from the talent pool, and a link to the full page for act counts and advances. Those payout-page actions come back to the day with the card open (`return_to`), and every recalculation keeps each line's choice (`ShowPayout#keeping_pay_choices`); choosing a calculation for a show already worked out works it out again on the new one. **Tim's third pass, later that evening:** no stacked modals: Choose a different calculation hides the pay modal, opens the chooser, and the chooser brings the pay modal back when it's done or cancelled (`modal_controller` `data-modal-close-id`, a hidden `reopen` the chooser carries, `?modal=<id>` on the way back); the pay modal offers **three distinct ways** (use the calculation, with Choose a different calculation inside it; everyone the same amount; each their own amount, prefilled from the calculation); Take off is **Remove**; the nobody-is-paid choice is its own card in the chooser ("No performers are paid for <production>; its shows settle without a payout") and the show's card then carries the way back, **Set up a payout**, while the day isn't settled; the tips block with nobody on the clock is one slim line ("the house keeps them until someone was on") with Assign tips (Tim, 11/4), and the house's share is said once (the stretch line already says it; the footer line only when there's more). **Reopening asks** (Tim: "reopening is essentially unsettling it"): the reopen modal says what it undoes (the numbers come off the books and go back on, dated the day, on settling again), counts the day's payouts on the open draft with the choice to take them off so the pay can change (the default; `unstage!` now reports what came off, in the notice) or leave them on the run, and says what's already funded or sent stays. **The register card's source** (Tim, 11/4): the net line is "To your bank from Square" alone; when it was read is gone, the header no longer says "from Square" or "automatically pulled in" (just Not confirmed), and a grey band at the bottom of the box says the numbers are pulled in automatically from Square, which sends the money straight to the bank, with Manage Square integration as its link. The confirm mark has a pointer cursor; a show card waiting says "Automatically pulled in, not confirmed".

**Release order (Tim, 2026-10-31): V1.3 stays on `v1.3` until Tap to Pay (V1.2) is
approved by Apple and shipped. Tap to Pay goes next; Books must not get in its way.**

Left for Tim, after that: review on the v1.3 dev server; merge to main and deploy, running the migrations (`ticket_sources.tax_handling`, `bank_statement_imports`, `organizations.books_locked_*` and the earlier ones on the branch); confirm the S3 bucket's encryption at rest and access logging (Todo).
