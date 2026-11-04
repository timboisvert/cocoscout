# Eventbrite: list our shows there and keep the seats in step

Plan, 2026-11-04. Not built. Tim's model (11/4): the integration belongs to the organization, like Square. Listing is switched on in ticketing, at three levels. Both sites sell from one pool of seats, and CocoScout keeps the two counts in step.

Research behind this: Eventbrite's API is self-serve and can create, picture, ticket and publish an event. Its API terms (§3.6(9)) bar use in "a product or service that competes" with Eventbrite and let them revoke access at any time. That risk is accepted or not by Tim; nothing below removes it.

## 1. Where it lives

| Level | Where | What you choose |
|---|---|---|
| Organization | Organization settings → Integrations → Eventbrite | Connect or disconnect the organization's Eventbrite account. Shows the account name, when we last heard from Eventbrite, and any error. |
| Ticketing | Ticketing settings → Eventbrite (a new section) | "List our shows on Eventbrite": on or off for everything. The last-seats number (§3). |
| Production | The production's ticketing → Sales | Follow ticketing settings, always list, or never list this production's shows. The production's Eventbrite image. |
| Show | The show's Tickets tab | Follow the production, list this show, or don't list this show. The show's own Eventbrite image, if it has one. |

The nearest answer wins: the show's choice, else the production's, else ticketing settings. So a production that is off can still list one show, and a production that is on can leave one show out.

Stored as: `Integration` with provider `eventbrite` (tokens encrypted, as Square), the organization-wide switch and last-seats number in its `settings`, and a nullable `eventbrite` choice on `production_ticketings` and `ticket_listings` (empty means "follow the level above").

## 2. What gets sent

Each show on sale becomes its own Eventbrite event. A date that qualifies is created there when it goes on sale here, with nobody clicking anything.

- **Sent:** title, start and end, the venue (each location is created once on Eventbrite and remembered), the description, the image, each public ticket type with its price and sale dates, the age note and refund policy text.
- **Not sent:** hidden and code-locked ticket types, comps, discount codes, member and pass prices, bundles, products, the waitlist, group bookings.
- **Later changes are sent too:** a new time, room, title, description, price (including 1.4's pricing rules) or image updates the Eventbrite event. Pausing or closing sales here stops sales there. Cancelling the show cancels the Eventbrite event.
- **Turning a switch off** on a show that already sold tickets there stops further sales there and keeps the event, so its buyers still have their tickets. With no sales, the event is removed.

**Image.** Eventbrite needs 2:1. Our wide image is 16:9 and we never crop. The production's ticketing Sales section gets an "Eventbrite image" (2:1, 2160×1080 suggested), and a show can have its own. With neither, we send the wide image set on a plain 2:1 background, so a listing never waits on artwork.

## 3. One pool of seats

Both sites sell every seat. Neither gets an allotment.

- For each ticket type, Eventbrite is told: what Eventbrite has sold of it, plus what is left here. Buyers on both sites see the same number left.
- **A sale here** (or a cart holding seats) lowers the number on Eventbrite within a few seconds.
- **A sale there** is recorded here as an Eventbrite sale on that show and ticket type (the existing `TicketOutsideSale` rows that `Ticketing::Inventory` already subtracts). The number left here drops at once.
- **When the last seat goes**, Eventbrite shows Sold out. A refund on either side opens the seat on both.
- **The last seats.** Two people can buy the same last seat on the two sites in the same few seconds. To close that gap, when only a few seats are left (default 2, set in ticketing settings, 0 allowed) Eventbrite shows Sold out and the last seats sell only here, where the count is exact.
- **If it still oversells**, the show's ticketing page and Home say so ("1 more ticket sold on Eventbrite than there are seats") for a manager to sort out. Nothing is cancelled automatically.

**Shows sold by the seat.** Eventbrite sells a count, not a seat. For a seated show it sells by price zone, and when the order arrives CocoScout gives it the best seats left in that zone, holds them, emails the buyer their seats, and shows them at the door. This is the last phase (§6).

## 4. Hearing about every sale

Three layers, so a sale there never goes unseen:

1. **Eventbrite tells us at once.** On connect we register for order placed, order updated, order refunded, attendee updated, event updated and ticket type updated. The notice only says which order; we then read the order itself.
2. **A check every five minutes** reads each live event's orders changed since the last check and corrects anything a notice missed.
3. **A daily count** compares Eventbrite's totals per show with ours and flags any difference.

For each order we keep: Eventbrite's order number, the buyer's name and email, ticket types and counts, what the buyer paid, Eventbrite's fees, tax, each ticket's barcode, and whether it was refunded.

The Eventbrite page in Integrations shows when we last heard from them and each show's count there. If the connection breaks (the account is disconnected on Eventbrite's side), managers get an alert at once, because we can no longer lower the numbers there.

## 5. Door and money

- **Door.** Eventbrite buyers are on the CocoScout door list, marked Eventbrite, and their Eventbrite barcodes scan in our scanner. Same mechanism as the 1.5 import ("upcoming tickets that still scan at our door").
- **Money.** Buyers there pay Eventbrite, and Eventbrite pays the organization. The sales land on the show's financials under the Eventbrite ticket source with that source's tax handling, as hand-typed outside sales do today, and flow to Books the same way. No CocoScout ticket fee is charged on them (as today for outside sales).

## 6. Build order

1. **Connect and list.** The Eventbrite integration, the three switches, creating, updating and cancelling events, the image.
2. **Sales and seats.** Notices, the five-minute check, recording orders and refunds, pushing seat counts, the last-seats rule, the oversold flag.
3. **Door.** Eventbrite buyers on the door list; their barcodes scan.
4. **Seated shows.** Best-seat assignment for Eventbrite orders.

Each step ships with request specs against a stubbed Eventbrite. Before it is switched on for real shows, one private test event on Tim's Eventbrite account goes through the whole loop.

## 7. Only Tim can do

1. **Create the API key** on the Eventbrite account's API keys page. It asks for an application name and a redirect address: `https://cocoscout.com/integrations/eventbrite/callback`. The key and secret go in 1Password and the server's environment, never the repo.
2. **Decide on the competing-products clause.**

## 8. To confirm while building

Read from the docs but not yet tried, or not read at all:

- Lowering and raising a ticket type's quantity after sales have started.
- How the event's capacity and the ticket types' quantities interact.
- Registering notices through the API rather than Eventbrite's dashboard.
- What cancelling an event through the API does to its buyers' refunds.
- Whether who pays Eventbrite's fee can be set per event through the API.
- That barcodes come with the attendee record.
- 1,000 calls an hour per account: seat-count pushes are bundled (one per show every few seconds at most) to stay under it on a busy on-sale.

Sources: Eventbrite Platform docs (create-events, image-upload, authentication, webhooks, ticket-classes) and the API Terms of Use (updated 2025-05-30).
