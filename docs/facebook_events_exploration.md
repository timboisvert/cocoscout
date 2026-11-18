# Facebook events publishing: dropped (2026-11-18)

**Dropped (Tim, 2026-11-18): "Facebook isn't going to happen. We need to remove that. Facebook will not give us API access."** It was explored on 2026-11-04 as a possible part of V1.4. It is not part of V1.4 or of any later release, nothing was built, and it must never be listed as planned.

What was asked for: when a date is published to Ticketing, publish it to Facebook events too. Why it can't be done is below, kept so that nobody researches it again.

## What Meta allowed when this was looked into (2026-11-04)

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

## What is left for an organization
A Page admin can still create the event on Facebook by hand and paste the date's ticket link, which becomes the event's "Get tickets" button. CocoScout builds nothing for this.
