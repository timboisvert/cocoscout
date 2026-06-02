# frozen_string_literal: true

# Superadmin moderation surface for the Mics Finder. Approve / reject /
# resolve queued items.
module Superadmin
  class MicsController < ApplicationController
    before_action :require_superadmin
    before_action :hide_sidebar

    # Mirrors the SuperadminController version — we render the same kind
    # of full-bleed page and don't want the My / Manage / Account
    # sidebars sneaking in for signed-in superadmins.
    def hide_sidebar
      @show_my_sidebar = false
      @show_manage_sidebar = false
      @show_manage_header_only = false
      @show_group_sidebar = false
      @show_account_sidebar = false
    end

    # Master search across every Mic in the system. Filters: q (name +
    # venue + city substring), status (active/pending/ended), claimed
    # (yes/no), hub_id. Capped at 200 results — superadmin can narrow
    # further with the search box.
    def index
      scope = Mic.includes(:venue, :mic_producers).references(:venues)

      if params[:q].present?
        q = "%#{params[:q].downcase}%"
        scope = scope.joins(:venue).where(
          "LOWER(mics.name) LIKE :q OR LOWER(venues.name) LIKE :q OR LOWER(venues.city) LIKE :q OR LOWER(mics.slug) LIKE :q",
          q: q
        )
      end

      case params[:status]
      when "pending"   then scope = scope.where(pending: true)
      when "ended"     then scope = scope.where(status: :ended)
      when "active"    then scope = scope.where(status: :active, pending: false)
      end

      case params[:claimed]
      when "yes" then scope = scope.where(id: MicProducer.select(:mic_id))
      when "no"  then scope = scope.where.not(id: MicProducer.select(:mic_id))
      end

      if params[:hub_id].present?
        scope = scope.joins(:venue).where(venues: { city_hub_id: params[:hub_id] })
      end

      @mics  = scope.order("mics.name ASC").limit(200)
      @total = scope.count
      @hubs  = CityHub.order(:name)

      # Counts strip — surfaces pending workload at a glance, links into
      # the queue page for actioning.
      @pending_mic_count        = Mic.pending_moderation.count
      @pending_claim_count      = MicClaim.status_pending.count
      @pending_challenge_count  = MicChallenge.status_pending.count
      @pending_suggestion_count = MicSuggestion.status_pending.count
    end

    def queue
      @pending_mics       = Mic.pending_moderation.includes(:venue).order(created_at: :desc)
      @pending_claims     = MicClaim.status_pending.includes(:mic, :claimant).order(created_at: :desc)
      @pending_challenges = MicChallenge.status_pending.includes(:mic, :challenger).order(created_at: :desc)
      @pending_suggestions = MicSuggestion.status_pending.includes(:mic).order(created_at: :desc)
      @draft_hubs         = CityHub.hub_draft.order(:name)
    end

    def approve_submission
      mic = Mic.find(params[:id])
      mic.update!(pending: false)
      mic.mic_edits.create!(editor_user_id: Current.user.id, source: :admin, field: "pending",
                             old_value: "true", new_value: "false", note: "Approved by superadmin")
      redirect_to mics_queue_path, notice: "Approved #{mic.name}."
    end

    def reject_submission
      mic = Mic.find(params[:id])
      reason = params[:reason].to_s.presence || "No reason given"
      mic.update!(status: :ended, pending: false)
      mic.mic_edits.create!(editor_user_id: Current.user.id, source: :admin, field: "status",
                             new_value: "ended", note: "Rejected: #{reason}")
      redirect_to mics_queue_path, notice: "Rejected #{mic.name}."
    end

    def approve_claim
      claim = MicClaim.find(params[:id])
      MicClaim.transaction do
        claim.update!(status: :approved, decided_at: Time.current, adjudicator: Current.user)
        claim.mic.mic_producers.find_or_create_by!(user_id: claim.claimant_user_id) do |mp|
          mp.role = claim.role
          mp.accepted_at = Time.current
        end
        if claim.role_producer?
          claim.mic.update!(lead_producer_user_id: claim.claimant_user_id, claimed_at: Time.current)
        end
        claim.mic.mic_edits.create!(editor_user_id: Current.user.id, source: :admin, field: "claim",
                                     new_value: "approved")
      end
      redirect_to mics_queue_path, notice: "Approved claim."
    end

    def reject_claim
      claim = MicClaim.find(params[:id])
      claim.update!(status: :rejected, decided_at: Time.current, adjudicator: Current.user,
                    reason: params[:reason])
      redirect_to mics_queue_path, notice: "Rejected claim."
    end

    def resolve_challenge
      challenge = MicChallenge.find(params[:id])
      outcome = params[:outcome].to_s
      MicChallenge.transaction do
        challenge.update!(status: outcome, decided_at: Time.current, adjudicator: Current.user)
        case outcome
        when "replaced"
          challenge.mic.mic_producers.where(user_id: challenge.target_user_id).destroy_all if challenge.target_user_id
          challenge.mic.mic_producers.find_or_create_by!(user_id: challenge.challenger_user_id) do |mp|
            mp.role = :producer
            mp.accepted_at = Time.current
          end
          challenge.mic.update!(lead_producer_user_id: challenge.challenger_user_id)
        when "co_produce"
          challenge.mic.mic_producers.find_or_create_by!(user_id: challenge.challenger_user_id) do |mp|
            mp.role = :co_producer
            mp.accepted_at = Time.current
          end
        end
      end
      redirect_to mics_queue_path, notice: "Challenge resolved (#{outcome})."
    end

    def approve_suggestion
      suggestion = MicSuggestion.find(params[:id])
      suggestion.update!(status: :approved, decided_at: Time.current, adjudicator: Current.user)
      suggestion.mic.mic_edits.create!(editor_user_id: Current.user.id, source: :suggestion,
                                        field: "suggestion", new_value: "approved",
                                        note: suggestion.note.to_s)
      redirect_to mics_queue_path, notice: "Suggestion approved."
    end

    def reject_suggestion
      suggestion = MicSuggestion.find(params[:id])
      suggestion.update!(status: :rejected, decided_at: Time.current, adjudicator: Current.user)
      redirect_to mics_queue_path, notice: "Suggestion rejected."
    end

    def promote_hub
      hub = CityHub.find(params[:id])
      hub.update!(status: :active)
      redirect_to mics_queue_path, notice: "Promoted #{hub.name} to active."
    end

    private

    def require_superadmin
      head :forbidden unless Current.user&.superadmin?
    end
  end
end
