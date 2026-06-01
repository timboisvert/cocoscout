# frozen_string_literal: true

module Mics
  class AlertsController < AuthedBaseController
    before_action :load_mic, only: [ :toggle ]

    def index
      @alerts = MicSignupAlert.where(user_id: current_user.id).includes(mic: :venue).order(:next_target_at)
    end

    def toggle
      alert = MicSignupAlert.find_by(user_id: current_user.id, mic_id: @mic.id)
      if alert
        alert.destroy!
      else
        alert = MicSignupAlert.create!(user_id: current_user.id, mic_id: @mic.id,
                                       channels: [ "email" ], lead_time_minutes: 5, active: true)
        alert.recompute_target!
      end
      redirect_back fallback_location: mics_detail_path(@mic.slug)
    end

    def destroy
      alert = MicSignupAlert.find_by!(id: params[:id], user_id: current_user.id)
      alert.destroy!
      redirect_to mics_alerts_path, notice: "Alert removed."
    end
  end
end
