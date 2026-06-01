# frozen_string_literal: true

module Mics
  class FavoritesController < AuthedBaseController
    before_action :load_mic, only: [ :toggle ]

    def index
      @favorites = MicFavorite.where(user_id: current_user.id).includes(mic: :venue).order(created_at: :desc)
    end

    def toggle
      existing = MicFavorite.find_by(user_id: current_user.id, mic_id: @mic.id)
      if existing
        existing.destroy!
      else
        MicFavorite.create!(user_id: current_user.id, mic_id: @mic.id)
      end
      redirect_back fallback_location: mics_detail_path(@mic.slug)
    end
  end
end
