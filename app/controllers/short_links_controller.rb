# frozen_string_literal: true

# cocoscout.com/t/CODE: the short link. Counts the visit, remembers which link
# brought the visitor (the cs_via cookie, read when an order starts), and
# sends them wherever the code points today. /t/CODE/oct-10 preselects a date
# on a production's page.
class ShortLinksController < ApplicationController
  allow_unauthenticated_access
  layout "ticketing"

  COOKIE = "cs_via"
  BOT_AGENTS = /bot|crawl|spider|slurp|facebookexternalhit|preview|fetch|curl|wget|headless/i

  def show
    link = ShortLink.lookup(params[:code])
    return render(:gone, status: :not_found) if link.nil? || link.target.nil?

    link.record_click! unless request.head? || request.user_agent.to_s.match?(BOT_AGENTS)
    cookies[COOKIE] = { value: link.code, expires: 30.days.from_now, httponly: true, same_site: :lax }
    redirect_to link.destination_path(params[:date]), status: :found
  end
end
