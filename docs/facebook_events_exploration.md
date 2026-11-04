# Facebook events from Ticketing: exploration (2026-11-04, for V1.4)

Tim's ask: when a date is published to Ticketing, it should also be publishable to Facebook events.

## What Meta allows today

- **The public Graph API cannot create events.** The Event reference (v27.0) says "Access to Events on Users and Pages is only available to Facebook Marketing Partners", and creating, updating and deleting are all "You can't perform this operation on this endpoint". The permissions reference has no permission that creates a Page event (`pages_events` is conversion logging, not events).
  https://developers.facebook.com/docs/graph-api/reference/event/
- **The one way in is the Official Events API**, a partner program for ticketing companies. Eventbrite, Ticketmaster, Humanitix and Billetto use it. Its documentation page exists but shows nothing to a signed-out visitor, so the application steps and criteria are not verified here.
  https://developers.facebook.com/docs/pages/official-events/
  https://www.theticketingbusiness.com/2021/03/ticketing-platform-billetto-integrates-facebook-events-api/
- **What partners get** (Humanitix's help article, April 2025; Eventbrite's "Add to Facebook"): the organizer connects a Facebook account, picks a Page they administer, and one button creates a public Page event from the ticketing event's image, description, time and place, with a "Get tickets" link back to the ticket page. Updates are pushed by hand ("Update event"), removal is done from the ticketing side, events go on Pages only (never groups or profiles), and an existing Facebook event cannot be linked. Humanitix's page also records an open fault where Pages do not appear and they "are reliant on a resolution from Facebook".
  https://help.humanitix.com/en/articles/8897156-share-your-event-on-facebook
  https://www.eventbrite.com/help/en-us/articles/586796/how-to-publish-your-eventbrite-event-to-facebook-and-sell-tickets/
- **By hand, anyone can do it**: a Page admin creates the event on Facebook and pastes a ticket link, which becomes the event's "Get tickets" button.
- **Open APIs nearby** (ordinary app review, no partner program): posting to a Page's feed (`pages_manage_posts`), Instagram "upcoming events" (`instagram_manage_upcoming_events`: read, create and update upcoming events on Instagram professional accounts), and the Meta Pixel / Conversions API that Meta's own help lists as the Eventbrite and Ticketmaster "partner integrations".
  https://developers.facebook.com/docs/permissions/

## Three ways to build it

### A. The real thing: Official Events API (clock is Meta's)
CocoScout becomes a Meta events partner. Then:
- Organization settings → Integrations gains **Facebook** beside Square (`Integration`, provider "facebook", the Page token in its encrypted credentials; same connect / callback / disconnect shape as Square).
- A date's ticketing page gets **Publish to Facebook**; a production can turn on "publish each date as it goes on sale". The event is built from `Ticketing::ListingPayload` (title, description, start and end, venue and address), the 16:9 wide image as the cover, and `ticket_uri` set to the date's ticket page through a short link so sales from Facebook are counted.
- The Facebook event id is kept on the listing. A show that moves or is canceled (the one-clock show change flow) updates or cancels the Facebook event; closing sales leaves it alone.
- A production with many dates can be one Facebook event with several times (the Event object has `event_times`) or one event per date; to decide when the docs are readable.
- Needs from Meta: a Meta app in CocoScout's business portfolio, business verification, app review for the Page permissions, and acceptance into the Official Events program. Unknown how long, and whether a ticketing company of our size is accepted.

### B. Works now, no Meta approval: assisted publishing
- An **Add to Facebook** panel on the date's (and production's) ticketing page: the title, description, date and time, place and the tracked ticket link each with a Copy button, the cover image downloadable at Facebook's event size (1920 × 1005), and a button that opens Facebook's create-event page.
- The manager pastes the Facebook event's address back; we keep it on the listing, show "On Facebook" with the link on the date's manage page, and count sales that arrive through the ticket link.
- When the show's time or place changes, or it's canceled, the show-change flow adds "Update your Facebook event" with the link.
- About a day of work. Everything it stores (the event address, the tracked link) is what A needs later, so A replaces the panel's steps with one button.

### C. Open-API extras (ordinary Meta app review, weeks not months)
- **Announce on the Page**: when a date goes on sale, post the ticket link to the organization's Page feed (the ticket page's share tags already give it a card).
- **Instagram upcoming event** for the date, on the organization's Instagram professional account. Seen in the permissions reference only; not explored further.
- **Meta Pixel and Conversions API per organization**, so an organization's Facebook and Instagram ads can be measured against ticket sales.

## Recommendation
1. Build **B** in 1.4. It delivers "publish to Facebook" for every organization now.
2. Start **A**'s clock now: only Tim can apply (see below). Build A when Meta says yes; it slots into Integrations beside Square and replaces B's manual steps.
3. Treat **C** as 1.5 (Integrations) unless Tim wants the Page announcement sooner; it needs the same Meta app and review as A's first steps.

## Only Tim can do
- Create (or pick) the Meta developer app under CocoScout's business portfolio and complete business verification.
- Signed in at developers.facebook.com, open the Official Events API page and follow its access request; if it shows nothing, ask through Meta's developer support or a Meta partner manager for Official Events API access for a ticketing platform.

## Not verified
- The Official Events API's current fields, limits, eligibility and whether new partners are being accepted (docs are behind sign-in).
- Whether Facebook's create-event page accepts pre-filled fields (assumed no; B uses copy buttons).
