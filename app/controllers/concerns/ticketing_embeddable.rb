# frozen_string_literal: true

# Lets the public ticketing pages run inside a theater's own website (the
# /tickets/embed.js widget). In embed mode (?embed=1, kept on every link, form and
# redirect through to the buyer's tickets) a page uses the bare embed layout
# and may be framed by any site. Outside embed mode nothing changes: Rails'
# usual same-origin framing rule stands.
module TicketingEmbeddable
  extend ActiveSupport::Concern

  included do
    layout -> { embed? ? "ticketing_embed" : "ticketing" }
    after_action :allow_framing, if: :embed?
    helper_method :embed?, :embed_params
  end

  private

  def embed?
    params[:embed] == "1"
  end

  def embed_params
    embed? ? { embed: "1" } : {}
  end

  def allow_framing
    response.headers.delete("X-Frame-Options")
    response.headers["Content-Security-Policy"] = "frame-ancestors *"
  end
end
