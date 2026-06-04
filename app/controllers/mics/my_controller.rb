# frozen_string_literal: true

# /mics/my — the single signed-in landing for mic regulars and producers.
# Top: mics this user manages. Bottom: mics this user has favorited. Each
# row has a one-click alert subscribe/unsubscribe toggle.
module Mics
  class MyController < AuthedBaseController
    def index
      @managed_mics  = Mic.joins(:mic_owners)
                          .where(mic_owners: { user_id: current_user.id })
                          .includes(:venue).distinct
      @favorite_mics = Mic.joins(:mic_favorites)
                          .where(mic_favorites: { user_id: current_user.id })
                          .includes(:venue).distinct

      @favorites_view = params[:view] == "list" ? "list" : "calendar"

      # Pre-compute upcoming occurrences across every favorite. We group
      # by date for the calendar render and keep a flat sorted list for
      # the list render.
      @fav_occurrences = []
      @favorite_mics.each do |m|
        m.next_occurrences(limit: 12).each do |occ|
          @fav_occurrences << { date: occ[:starts_at].to_date,
                                starts_at: occ[:starts_at],
                                mic: m,
                                mic_status: occ[:mic_status] }
        end
      end
      @fav_occurrences.sort_by! { |o| [ o[:starts_at], o[:mic].name.to_s.downcase ] }
      @fav_by_date = @fav_occurrences.group_by { |o| o[:date] }
    end
  end
end
