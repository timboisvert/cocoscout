# Step-through QA — everything from August 6

Ten features and six fixes. Suite is green at **2,295 examples**.

Work through it top to bottom: the money-correctness fixes come first because
they're the ones that were actively costing you, and a couple of later checks
build on setup from earlier ones.

---

## Before you start

**Deploy first.** Nine migrations, one of which backfills contract versions.

```bash
kamal deploy
```

**Then one manual step in Stripe** — this is the only thing a deploy can't do
for you. In the Stripe dashboard, open your **live** Connect webhook endpoint
and add the event **`payout.failed`**. Nothing in section 4 works without it,
because that's the only signal Stripe gives when a payee's bank rejects a
deposit. While you're there, confirm `account.updated` is still listed — section
5's instant path uses it.

**Optional, whenever you want the two new roles:**

```bash
kamal app exec -p -q --reuse "bin/rails house_roles:seed_flat_roles[YOUR_ORG_ID]"
```

---

## 1. The bug that started it: amending no longer invents payments

**What was wrong:** you amended a contract to cancel one date and got a second
payment for June 4 — a show that had already happened, sold tickets, and been
paid $63. It showed up beside the paid one marked "2 months overdue."

**Check it:**

1. Open a contract with at least one **paid** payment on a past date.
2. Amend Contract → Change the deal → walk through to Confirm → Apply.
3. Look at the payment schedule.

**Expect:** the paid payment is still there, alone. No duplicate, no phantom
"overdue" row. Dates that have already been settled are closed — nothing is
ever created for them again.

Also worth confirming while you're there: if you'd flipped a payment to "Deduct
from payout" by hand, or set an amount manually, or issued a pay link, all of
those survive the amendment now. They used to be wiped.

---

## 2. Contract 107's booth-tech charges

**What was wrong:** six separate $50 "they pay us" rows next to two weekly
settlements, reading like six invoices to chase — when they're one deduction
against each week.

**Check it:** open `/manage/contracts/107`.

**Expect:**
- Two settlement rows, each reading **"Ticket revenue less $750.00 fee and $150.00 services"**.
- Under each, a disclosure: *"3 charges deducted from this payment"* — click it to see the individual dates.
- No standalone $50 rows.

Then open **Money → Incoming**. The booth-tech charges should **not** be listed
there any more. They net out automatically, so nobody invoices or chases them,
and having them in the collect list was inflating "owed to us" with money that
never arrives as a payment.

---

## 3. Changing dates vs changing the deal

**Check it:** open any active contract with dates and click **Amend Contract**.

**Expect** a chooser — "Change the dates" or "Change the deal" — rather than
being dropped straight into the wizard.

### Change the dates

Pick it. You get one row per booked date with Keep / Move / Remove.

Try each:

- **Remove a future date.** It disappears along with its still-pending payments. Nothing else on the contract moves.
- **Remove a date that's already been paid.** The row warns you first ("Already settled — removing this cancels the date and leaves the money alone"), and the button says **Cancel** rather than Remove. Afterwards the show is marked cancelled, still exists, and the paid payment is untouched. The confirmation says so.
- **Move a date.** Pick a new date and time. Afterwards, open the show: it's the same show, with its **cast and staffing still attached**, and its pending payment has moved to the new date.
- **Leave one on Keep.** It should be completely untouched.

### Cancelling a show directly

Cancel a contract-governed show from the show page (this is the door you
actually reached for the other night).

**Expect:** the confirmation now reads *"...and 1 pending contract payment
dropped with it."* Before, cancelling left the payment behind entirely. A
**paid** payment is never dropped — try that too.

---

## 4. A payout the bank sends back

This one needs Stripe's test tooling or patience; the specs cover the logic, but
if you want to see it end to end you can trigger `payout.failed` from the Stripe
CLI against a connected account.

**What to look for when it fires:**
- The payout run item goes to **returned** — a new state, distinct from "failed" (which means the transfer never happened at all).
- The ledger keeps the original payout entry **and** adds a `reversal` beside it. The payment happened and then came back; both halves belong on the record. It doesn't just delete the entry like it used to.
- Anything that read "paid" because of that run — a show payout line, an advance, a contract payment — goes back to owed.
- A run that said "completed" reopens to partially paid.
- The payee gets a message asking them to check their bank details; you get one saying the money's back and still owed.

**The honest limitation:** Stripe reports an amount and an account, not our
payment id, and one Stripe payout can bundle several of our transfers. We act
automatically only when exactly one unreturned payment matches that amount. If
it's ambiguous we notify the payee and log it rather than guessing — a wrong
guess corrupts your books.

---

## 5. Parked payouts pay themselves

**Check the UI now, without waiting for anything:** open a payout run that's
**partially paid** with someone still waiting on a bank.

**Expect** on both panels:
- The amber one: *"You don't have to do anything — we pay each person automatically as soon as they connect a bank"* followed by **"Next automatic attempt tomorrow at 6:15am — or the moment they connect, whichever comes first."**
- The pink one: the same next-attempt line, phrased for whether anyone's ready yet.
- **Money → Payouts:** the run's row now reads *"$X waiting on people's bank info · retrying tomorrow 6:15am"*.

**To see it actually fire:** have a parked person finish connecting a bank. The
`account.updated` webhook pays them within seconds — you don't wait for the
morning sweep. You'll get a message naming who was paid and how much, because
money moving unattended should leave a trail.

The 6:15am daily job is the floor, not the mechanism. It runs just after your
scheduled payouts at 6am so anyone parked on a run created that morning gets a
same-day look.

---

## 6. Pull in approved hours

**Check it:** approve some hours for two or three people on the timesheets page,
then open **Pay People**.

**Expect** a banner above the grid: *"3 people have approved hours waiting —
12.5h in total"* with a **Pull in approved hours** button.

Click it. Everyone's listed with their hours and what it comes to, all checked,
with All / None. Confirm.

**Expect** every one of those people's Hours cells to fill in, with the totals
matching what you'd have got clicking through each person's modal one at a time
— because that's literally what it does under the hood. It ticks the entries
inside each person's own modal, so the two paths can't disagree.

Worth confirming: hours you'd already added by hand to someone survive the pull
(it ticks, it doesn't replace), and **pending** hours are never offered —
approving stays a deliberate act on the timesheets screen.

---

## 7. Flat-rate roles

**Check it:** Staffing → Roles → Add role.

**Expect** a **How it's paid** dropdown: *By the hour* or *Flat rate for the
shift*. Choosing flat swaps the hourly field for **"Flat rate per shift"** with
a `/night` suffix. Make one — Security at $50.

**Expect** the role list to show **$50.00/night** in purple next to it.

Now assign someone to a Security shift, have hours logged against it, and:

- **Timesheets:** the row reads `$50.00/night → $50.00` rather than a rate × hours calculation.
- **Pay People:** their Hours modal prices that entry at $50 regardless of the hours on it. The grid total agrees with the server.
- **Employee agreement:** Schedule 1 lists "Security — $50.00/night".

The rule to sanity-check: **flat pays once per night.** Log the same security
shift as two separate stints on one date and it's still $50. Two different
nights pay $50 each.

---

## 8. Message a show's cast and crew

**Check it:** Messages → compose → **Show cast** → pick a production → pick a
show that has staffing assigned.

**Expect** a new **Who should get this?** choice: *Cast only* or *Cast and crew*.

Pick cast and crew. A list appears — one row per shift, the role and time on
top, the assigned people's names underneath in small text, everyone ticked, with
All / None.

Send it and check the recipients: cast plus the ticked crew, and anyone who's on
both (performs and works the door) appears **once**.

A show with nobody staffed doesn't offer the choice at all — there'd only be one
answer.

---

## 9. Contract versions, re-signature and appendixes

The biggest piece, and worth walking properly.

### Appendixes

On a contract you're preparing for signature, add an appendix (Tech Rider) with
some text.

**Expect** it at the **end of the document, above the signature block**, headed
**"Appendix A — Tech Rider"**. Add a second and it becomes Appendix B.

### Signing cuts v1

Sign as the org, send, and sign as the counterparty in a private window.

**Expect:** the contract shows executed, and the PDF downloads with the appendix
text in it.

### Amending asks the question

Amend the contract → Change the deal → Confirm.

**Expect** a new block: **"Does this change need a new signature?"** with the two
options explained.

- **Answer Yes.** You land on the wizard's Sign step. The contract's terms are live immediately, but it's now **v2 awaiting signature** — and critically, **v1's PDF still downloads unchanged**.
- **Answer No.** It applies at once, recorded as v2, and the PDF carries v1's signatures forward **with a note saying it was applied as an internal correction**. The signatures are never copied — that would be forging a signature over text nobody signed.

### The things that used to be broken

- **Version history** panel on the contract page listing every version, what changed, who applied it, and a PDF link per version.
- **The old signing link.** After cutting v2, reload the v1 link in your private window. You get *"This contract has been updated"* with a pointer to contact you — not a 404, and definitely not a chance to sign a superseded document.
- **Amending while a signature is outstanding is blocked** — you're told to revoke it first, because the counterparty may be mid-read.
- Editing an appendix **after** signing cannot change the signed document. The text is baked into the version snapshot.

---

## 10. Smaller fixes from earlier today

Quick ones to confirm in passing:

- **Amend financials no longer jams.** Adjust financials on an amendment and click through to Ticketing or Services. The "invalid form control with name='' is not focusable" error is gone.
- **Staffing → Settings → Notifications.** Pick managers; when a staffer says they can't make a shift, they get a message with the role, the time, the person's note and a link to that day.
- **New contract services default to "Taken out of their payout."**
- **Scheduling stays put.** Assign someone to a shift on `/manage/staffing/scheduling` — the page updates in place, no reload, no jump to the top.
- **Role Call** (the show-coverage feature, now named). Staffing → Settings → Role Call. With it on, hover a show chip on scheduling for the branded block; click for the panel with per-role covered/not-covered, and per-role "Not needed here" to excuse individual roles.
- **Show popover** shows show time, call time and **Space booked** (the room's window on the contract).
- **Recurring monthly-by-weekday series.** Show wizard → recurring → "Monthly (e.g. 2nd Friday)". This raised a 500 for three months and nobody had tried it. It now creates the series with the right time on every date.

---

## One thing left for you

The phantom payments the old code already created are still sitting in
production — the fix stops new ones, it doesn't clean up the old. The console
snippet for that is in the chat; it's read-only until you flip `DRY = false`,
and it refuses to touch anything paid or already in a payout run.
