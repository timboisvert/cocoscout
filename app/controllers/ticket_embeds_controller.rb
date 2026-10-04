# frozen_string_literal: true

# /tickets/embed.js — the one script a theater puts on its own website to sell
# tickets there:
#
#   <div data-cocoscout-tickets="starsandgarters"></div>
#   <script src="https://cocoscout.com/tickets/embed.js" async></script>
#
# Each such element becomes a frame of the box office (or of one show, with
# data-event="<show>"), sized to fit; data-view="button" makes a "Buy tickets"
# button that opens the show in an overlay instead. Buying happens inside the
# frame, start to finish.
class TicketEmbedsController < ApplicationController
  allow_unauthenticated_access
  # Rails refuses JavaScript requested by another site's <script> tag (its
  # cross-origin script protection). Being loaded by other sites is this
  # script's whole job, and it carries nothing private.
  skip_forgery_protection

  def script
    expires_in 1.hour, public: true
    render template: "ticket_embeds/script", formats: :js, content_type: "text/javascript", layout: false
  end
end
