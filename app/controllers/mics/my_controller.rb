# frozen_string_literal: true

# /mics/my — the single signed-in landing for mic regulars and producers.
# Top: mics this user manages. Bottom: mics this user has favorited. Each
# row has a one-click alert subscribe/unsubscribe toggle.
module Mics
  class MyController < AuthedBaseController
    def index
      @managed_mics  = Mic.joins(:mic_producers)
                          .where(mic_producers: { user_id: current_user.id })
                          .includes(:venue).distinct
      @favorite_mics = Mic.joins(:mic_favorites)
                          .where(mic_favorites: { user_id: current_user.id })
                          .includes(:venue).distinct
    end
  end
end
