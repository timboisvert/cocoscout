# frozen_string_literal: true

module Mics
  class ChallengesController < AuthedBaseController
    before_action :load_mic

    def new
      @challenge = MicChallenge.new
    end

    def create
      @challenge = @mic.mic_challenges.build(challenge_params)
      @challenge.challenger = current_user
      @challenge.target_user_id = @mic.lead_owner_user_id
      @challenge.status = :pending
      @challenge.save!

      Mics::NotificationService.notify_challenge(challenge: @challenge)
      redirect_to mics_detail_path(@mic.slug), notice: "Challenge filed. The current lead owner has 72 hours to respond."
    end

    private

    def challenge_params
      params.require(:mic_challenge).permit(:reason, evidence: [ :note, :url, :phone, :email ])
    end
  end
end
