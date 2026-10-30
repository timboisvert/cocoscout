# Telling people when a show changes

Tim, 2026-10-30. When a show is canceled, taken away or moved, the people it
touches are told the same way, whatever the show is: our own production or a
contract's, cast or not. Before this, canceling was the only change that told
anyone, and it told only the cast (an optional box, recorded nowhere). Staff were
never told, and a moved show left its shifts at the old time.

## The two times

A contract night has a **booking** (when the room is held) and a **show time**
(`shows.date_and_time`, when it starts and what tickets say). They can differ.
Moving the show time affects the cast, the show's staff and ticket buyers.
Moving only the booking affects the staff on shifts made for the booking (setup
crew), nobody else.

## What counts as a change

| Change | Where it can happen | Recorded as |
|---|---|---|
| Canceled | Shows & Events cancel (one, this and future, all); a contract date that had money or tickets | `canceled` |
| Taken away | Shows & Events delete; a contract date removed (no money moved); the whole contract canceled | `removed` |
| Show time moved | A show's edit; a series reschedule; a contract date moved or retimed; the amend wizard | `moved` |
| Booking moved | A contract date's room time changed, show time not | `moved`, booking only |

The show records it itself (callbacks on `Show` and `SpaceRental`), so every
path above is covered, and any new one later, without each controller
remembering. Changes made in one request share a **batch**, so canceling a
series is one thing to tell people about, not ten. Shows in the past are left
alone, and so is a change that touches nobody.

## Who's affected

Read when the change happens and kept on the record, so a deleted show still
knows whom it had.

- **Cast:** everyone cast on the show, people and the members of cast groups.
  Contract shows usually have none; when they do, they're told too.
- **Staff:** everyone still on (not declined) a shift of
  - the show itself (a shift made for it, or merged to cover it), for any
    change to the show time, cancel or removal;
  - the booking, for a booking move or a removal;
  - the whole night (roles that aren't per show), only when the show was the
    last one left that night.
- **Ticket buyers:** unchanged for now: Ticketing's refund email on a cancel.
  A "time changed" email for buyers is the next step after this (see Later).
- **Contract people** (the contractor's side) aren't sent anything: they
  see their dates change on their own pages.

## Tell people

One page per batch (`/manage/show-changes/:batch`), opened right after a
cancel and linked from a banner after any other change:

1. **What changed**, date by date (was → now for a move).
2. **The shifts**: on a cancel or removal, "Take these shifts off the
   schedule" (the people come off, the shift stays as Not needed); on a move,
   "Move these shifts with the show" (by the same amount). Ticked by default,
   but nothing happens to a shift until the manager sends (Tim, 2026-10-29: no
   unscheduling behind his back).
3. **Cast** and **Staff**, each the bulk-send preview: everyone ticked, the
   draft above, editable. One message per person per batch, listing their
   dates.
4. **Send**, or **Not now** (Home keeps saying they haven't been told), or
   **Nobody needs telling** (closes it).

Copy comes from seeded templates: `show_canceled` (exists, cast), `show_moved`
(cast), `shift_canceled` and `shift_moved` (staff). Each notice sent is
recorded against the change (`show_change_notices`), whatever channel the
template uses, so "were they told?" has a real answer.

## Where it shows

- **Home:** a canceled show's staffing and cast chips become **Cast told** /
  **Cast not told · 6** and **Staff told** / **2 staff not told** (never
  "Needs Booth Tech" or "All cast"). A moved show with people not yet told says
  so the same way until they are. The show's pop-up lists who was and wasn't
  told, with **Tell them now**.
- **The contract page:** dates changed on the contract and not yet told get
  their own line with **Tell them**, beside the existing "Still to do from
  removed dates" list.
- **Shows canceled before this** have no record. A future one with cast or
  staff reads "not told", and Tell them now makes the record from the show as it
  stands.

## Build order

1. The record (`show_changes`, `show_change_notices`), the callbacks, the
   templates, and the send service.
2. The Tell people page, with the shift actions.
3. The cancel screen hands its cast notice to the Tell page (its own
   notify-cast switch goes); every other change gets the banner.
4. Home and the contract page.

## Later

- Ticket buyers told of a time change (a Ticketing template, sent from the
  same page).
