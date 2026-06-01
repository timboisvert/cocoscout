# frozen_string_literal: true

# Hub captain surface: lets a CityHub editor see the state of their
# city, work the queue, and act on unclaimed mics.
module Mics
  class HubsController < AuthedBaseController
    before_action :load_hub_and_authorize

    def show
      @mics = Mic.in_hub(@hub).includes(:venue, :mic_producers).order(:name)
      @active_mics      = @mics.select { |m| m.status_active? && !m.pending }
      @unclaimed_mics   = @active_mics.reject(&:claimed?)
      @claimed_mics     = @active_mics.select(&:claimed?)
      @pending_mic_ct       = Mic.pending_moderation.in_hub(@hub).count
      @pending_suggestion_ct = MicSuggestion.status_pending.joins(mic: :venue)
                                            .where(venues: { city_hub_id: @hub.id }).count
      @pending_claim_ct      = MicClaim.status_pending.joins(mic: :venue)
                                       .where(venues: { city_hub_id: @hub.id }).count
      @pending_challenge_ct  = MicChallenge.status_pending.joins(mic: :venue)
                                           .where(venues: { city_hub_id: @hub.id }).count
      @recent_edits = MicEdit.joins(mic: :venue).where(venues: { city_hub_id: @hub.id })
                              .order(created_at: :desc).limit(15)
    end

    def queue
      # Use the hub rollup (venue.city_hub_id) so suburb mics show up too.
      @pending_mics        = Mic.pending_moderation.in_hub(@hub).order(created_at: :desc)
      @pending_suggestions = MicSuggestion.status_pending.joins(mic: :venue)
                                          .where(venues: { city_hub_id: @hub.id })
                                          .order(created_at: :desc)
      @pending_claims      = MicClaim.status_pending.joins(mic: :venue)
                                     .where(venues: { city_hub_id: @hub.id })
                                     .order(created_at: :desc)
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
