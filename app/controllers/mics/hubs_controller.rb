# frozen_string_literal: true

# Hub editor queue: lets a CityHub editor see and approve pending mics
# and suggestions scoped to their city.
module Mics
  class HubsController < AuthedBaseController
    before_action :load_hub_and_authorize

    def queue
      @pending_mics = Mic.pending_moderation.joins(:venue)
                         .where(venues: { city: @hub.name, state: @hub.state })
      @pending_suggestions = MicSuggestion.status_pending.joins(mic: :venue)
                                          .where(venues: { city: @hub.name, state: @hub.state })
      @pending_claims = MicClaim.status_pending.joins(mic: :venue)
                                .where(venues: { city: @hub.name, state: @hub.state })
    end

    private

    def load_hub_and_authorize
      @hub = CityHub.find_by!(slug: params[:slug])
      head :forbidden unless authorized?
    rescue ActiveRecord::RecordNotFound
      render plain: "Not found", status: :not_found
    end

    def authorized?
      return false unless current_user
      return true if current_user.respond_to?(:superadmin?) && current_user.superadmin?
      @hub.editor?(current_user)
    end
  end
end
