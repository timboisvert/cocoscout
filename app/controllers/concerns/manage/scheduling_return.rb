# frozen_string_literal: true

module Manage
  # Where an action on the staffing scheduling page sends the manager back to.
  #
  # It has to be the *identical* URL they were already on. Turbo only morphs a
  # page — patching the changed nodes in place and leaving scroll position and
  # open state alone — when a form redirects to exactly the current href
  # (Turbo's Navigator#getDefaultAction). Any difference makes it an ordinary
  # visit: full re-render, scrolled back to the top of the week. That's why
  # there's no "#day-..." anchor here any more; the anchor both broke the match
  # and forced a jump of its own.
  #
  # The referer carries week_start and anything else on the query string, and
  # url_from returns nil for an off-host or missing referer, so the fallback
  # only kicks in for a direct/scriptless request.
  module SchedulingReturn
    extend ActiveSupport::Concern

    private

    def scheduling_return_url
      url_from(request.referer) || manage_staffing_scheduling_url
    end
  end
end
