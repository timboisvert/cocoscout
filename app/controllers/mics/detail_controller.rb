# frozen_string_literal: true

# Individual mic detail page + per-mic ICS export.
module Mics
  class DetailController < BaseController
    before_action :load_mic

    def show
      # Pull a few months ahead so the calendar view has something to
      # show. View toggles between "calendar" (default) and "list" via
      # a single query param; we don't refetch.
      @next_occurrences = @mic.next_occurrences(limit: 16)
      @signup_info = @mic.signup_info
      @upcoming_view = params[:view] == "list" ? "list" : "calendar"
    end

    def calendar
      send_data MicIcsBuilder.for_mic(@mic, occurrences: @mic.next_occurrences(limit: 16)),
                type: "text/calendar",
                disposition: "attachment",
                filename: "#{@mic.slug}.ics"
    end

    private

    def load_mic
      @mic = Mic.find_by!(slug: params[:slug].to_s.downcase)
    rescue ActiveRecord::RecordNotFound
      render plain: "Not found", status: :not_found
    end
  end
end
