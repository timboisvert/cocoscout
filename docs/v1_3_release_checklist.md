# V1.3 release checklist

Books, replacing QuickBooks. Everything it needs to go out, in order. The
code is on branch `v1.3` (`docs/books_v1_3_plan.md` §10 is the log). Written
2026-11-10, when Tim said to get it ready: Tap to Pay (1.2) was live on
Android and in Apple's review.

## Done (2026-11-11)

Merged into main (18a0c193), deployed, and the backfill posted the same
evening: all 16 organizations at `trial balance: $0.00`, the books agreeing.
One repair followed in production: 15 corrections from before Nov 3 were
dated the day they were made, not the day they correct, which put $675 of
September and $300 of October into November; they were moved onto the dates
they correct. What follows is the checklist as it was worked.

## Where it stands (2026-11-10)

- `v1.3` has main merged in (through c4a8266a, 2026-11-11) and merges back
  into main with no conflicts: about 140 commits and 40 migrations.
- **Rehearsed on a fresh production copy, 2026-11-11.** It caught one
  thing: the migration that set each organization's Settle up start ran
  code that reads tables made by later migrations, and stopped on
  `tip_rules`. The switch now runs last
  (`SettleUpStartsForExistingOrganizations`). With that, all the pending
  migrations ran on real data, and the books dry run read `trial balance:
  $0.00` and `the books agree` for all 16 organizations, with no `FAILED`
  or `MISMATCH` line.
- Apple approved Tap to Pay (1.2) on 2026-11-11, which is what 1.3 was
  waiting for.
- The pre-deploy route check passes (it failed on `SettleUp`'s
  `money_entry_path`, a service method the check read as a route helper;
  it is `money_entry_href` now).
- Google Calendar is in the integrations catalog (2026-11-11) and ships
  switched off: until GOOGLE_CALENDAR_CLIENT_ID and
  GOOGLE_CALENDAR_CLIENT_SECRET are set, its page says it isn't set up.
- The full suite passes on it (5,676 examples, 0 failures, 2026-11-11).
- No app build is needed. Books is server only; the apps' page rules ship
  with the deploy.

## 1. Before merging (yours)

- [x] **Rehearse on a fresh copy of production** (done 2026-11-11, see
      above). To do it again: `bin/seed_dev_from_prod` from the main
      folder, which also runs the migrations, then on the `v1.3` worktree:

      ```bash
      bin/rails db:migrate
      ```

      ```bash
      bin/rails books:backfill
      ```

      The second is a dry run and keeps nothing. Every organization should
      read `trial balance: $0.00` and `checks: the books agree with the
      records behind them`. Stars & Garters should also read `paid by hand
      before the payout ledger: 386 payout lines, $14,267.11, to 97 people
      ... Nobody's balance moved` (the numbers will differ a little on a
      newer copy). Any `FAILED` or `MISMATCH` line stops the release.
- [ ] Look it over on localhost serving `v1.3`: Money → Books (the landing
      page, By show, Checks), Settle up for a recent day, Bank, an invoice
      and its page, Statements and a download, Taxes.

## 2. Merge and deploy (Claude merges and pushes on your word; you deploy)

- [ ] Merge `refs/heads/v1.3` into `main`, push.
- [ ] Deploy. It runs 40 migrations. The ones that move data:
      - `SettleUpStartsForExistingOrganizations` (the last one) starts
        every organization's Settle up on the first of the month and counts
        days already confirmed in Financials as settled (three days for
        Stars & Garters on the Nov 11 copy).
      - `MergeContractInvoicesIntoInvoices` copies every contract invoice
        into `invoices` (the old table is left in place, unused).
      - `AddDigestsIgnoredToUsers` counts the digests each person has
        already ignored, from the throttle they are on.
      - `StandardEmailButtons` restyles the button in eight stored email
        templates; words and links are untouched.
      - Six migrations seed notice and email templates.

## 3. Right after the deploy (yours, on production)

- [ ] The books backfill, in your `kamal console`, dry run first. Paste
      this as it is; it keeps nothing:

      ```ruby
      Rails.application.load_tasks if Rake::Task.tasks.empty?
      begin
        Rake::Task["books:backfill"].reenable
        Rake::Task["books:backfill"].invoke
      rescue SystemExit => e
        puts e.message
      end
      ```

      Read it as in step 1. Then keep it, with this one:

      ```ruby
      Rails.application.load_tasks if Rake::Task.tasks.empty?
      begin
        Rake::Task["books:backfill"].reenable
        Rake::Task["books:backfill"].invoke("post")
      rescue SystemExit => e
        puts e.message
      end
      ```

      It posts one organization at a time. One that fails is rolled back by
      itself and named in a `FAILED` line; send that line back and the block
      to run again for just that organization comes with the answer.
- [ ] Open Stars & Garters' Books → Checks. The five checks should agree.
      Financials vs Books will still list a few productions; see "Known
      differences" below.

## 4. What people notice on day one

- The unread digest stops for anyone who has ignored three in a row, until
  they come back. On the Nov 2 copy that was 251 of 1,052 people.
- Cover notices to managers and production teams (a decline, a cover shift
  filled or taken back, cover needed) are notifications only. Everything
  about a person's own shifts still emails as well.
- A manager no longer gets an email for each sale, door sale, comp or pass;
  those are notifications. A bare address still gets the email.
- Invoices that were emailed and set to remind do so by themselves, 9am.
- "Hours approved" is a notification that opens its own page.
- You and Andie get a notification if the nightly books check disagrees.

## 5. After it has settled

- [ ] The app email (`AppAnnouncement`), once you have looked at it:
      `AppAnnouncement.send_test!("you@example.com")`, then
      `AppAnnouncement.announce!(dry_run: true)`, then batches
      (`announce!(limit: 400, seen_since: 90.days.ago)`).
- [ ] Tap to Pay's launch email, now that Apple has approved 1.2
      (`ios/tap_to_pay.md`).

## Known differences that stay (Stars & Garters, Financials vs Books)

After the backfill, on the Nov 2 copy, five productions still differ this
year. Each is small and has a reason:

| Production | Difference | Why |
|---|---|---|
| Starlets | Financials $385.00 higher | $185.00 of guests' pay and $200.00 of advances |
| Stargazers Adventure Club | Financials $15.00 higher | a guest's pay |
| Laugh-Along, Live! | Books $75.00 higher ($50.00 last year) | people paid for a show that was then canceled; Financials leaves canceled shows out |
| A Random Memory | Financials $14.25 higher | a contract show; not yet explained |
| The Real Spacewives of Alderaan | Books $60.70 higher | a contract show; not yet explained |

- **Guests' pay never reaches the books** ($451.56 across five lines so
  far). A guest has no account, so there is no ledger row to post from. To
  fix after 1.3: post a guest's line straight to the books when it's marked
  paid, and withdraw it if the guest is later given an account.
- **Advances from before the payout ledger** ($200.00, eight lines): the
  books show what was paid at the show, not the advance that came first.
- **37 payout lines on contract shows** ($7,913.71) are left off on
  purpose: the contract's own payments already carry that money.

## After 1.3 (not in it)

- Drop the unused `contract_invoices` table.
- Guests' pay on the books (above).
- The course cancellation spec that failed once in three full runs
  ("Template 'course_cancelled_registrant' not found"): unexplained.
