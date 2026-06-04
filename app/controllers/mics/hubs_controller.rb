# frozen_string_literal: true

# Hub captain surface: lets a CityHub editor see the state of their
# city, work the queue, and act on unclaimed mics.
module Mics
  class HubsController < AuthedBaseController
    before_action :load_hub_and_authorize

    def show
      # ── Mic list (searchable, sortable) — scoped to this hub. %>
      scope = Mic.in_hub(@hub).includes(:venue, :mic_owners).references(:venues)

      if params[:q].present?
        q = "%#{params[:q].downcase}%"
        scope = scope.joins(:venue).where(
          "LOWER(mics.name) LIKE :q OR LOWER(venues.name) LIKE :q OR LOWER(venues.city) LIKE :q OR LOWER(mics.slug) LIKE :q",
          q: q
        )
      end

      @sort = %w[name created_desc].include?(params[:sort]) ? params[:sort] : "name"
      scope = @sort == "created_desc" ? scope.order(created_at: :desc) : scope.order("mics.name ASC")

      @mics_total = scope.count
      @mics_all   = scope.limit(200)

      # Split for the "Unclaimed / Claimed" rendering when no search is
      # active. With a search active we just show the search results.
      if params[:q].blank?
        @active_mics    = @mics_all.select { |m| m.active? && !m.pending && !m.paused? }
        @unclaimed_mics = @active_mics.reject(&:claimed?)
        @claimed_mics   = @active_mics.select(&:claimed?)
      end

      # ── Pending queue scoped to this hub %>
      @pending_mics = Mic.pending_moderation.in_hub(@hub)
                          .includes(venue: :city_hub, mic_edits: :editor)
                          .order(created_at: :desc).limit(20)
      @pending_claims = MicClaim.status_pending.joins(mic: :venue)
                                  .where(venues: { city_hub_id: @hub.id })
                                  .includes(:claimant, mic: :venue)
                                  .order(created_at: :desc).limit(20)
      @pending_challenges = MicChallenge.status_pending.joins(mic: :venue)
                                          .where(venues: { city_hub_id: @hub.id })
                                          .includes(:challenger, :target, mic: :venue)
                                          .order(created_at: :desc).limit(20)
      @pending_suggestions = MicSuggestion.status_pending.joins(mic: :venue)
                                            .where(venues: { city_hub_id: @hub.id })
                                            .includes(:submitter, mic: :venue)
                                            .order(created_at: :desc).limit(20)

      @pending_mic_ct        = @pending_mics.size
      @pending_claim_ct      = @pending_claims.size
      @pending_challenge_ct  = @pending_challenges.size
      @pending_suggestion_ct = @pending_suggestions.size

      @recent_edits = MicEdit.joins(mic: :venue).where(venues: { city_hub_id: @hub.id })
                              .order(created_at: :desc).limit(15)
    end

    # The standalone queue page is folded into the captain dashboard
    # (#show). Keep the URL alive as a permanent redirect so any
    # in-app links / bookmarks don't break.
    def queue
      redirect_to mics_captain_hub_path(@hub.slug, anchor: "submissions"), status: :moved_permanently
    end

    # ── Moderation actions (captain-side mirrors of the superadmin
    # moderation endpoints, scoped to the captain's hub). Each verifies
    # the affected record belongs to a Mic whose venue rolls up to this
    # hub before acting, so captains can't operate cross-hub.

    def approve_submission
      mic = scoped_mic!
      mic.update!(pending: false)
      mic.mic_edits.create!(editor_user_id: current_user.id, source: :admin, field: "pending",
                             old_value: "true", new_value: "false", note: "Approved by hub captain")
      redirect_to mics_captain_hub_path(@hub.slug, anchor: "queue-top"), notice: "Approved #{mic.name}."
    end

    def reject_submission
      mic = scoped_mic!
      reason = params[:reason].to_s.presence || "No reason given"
      mic.update!(status: :ended, pending: false)
      mic.mic_edits.create!(editor_user_id: current_user.id, source: :admin, field: "status",
                             new_value: "ended", note: "Rejected by hub captain: #{reason}")
      redirect_to mics_captain_hub_path(@hub.slug, anchor: "queue-top"), notice: "Rejected #{mic.name}."
    end

    def approve_claim
      claim = scoped_claim!
      MicClaim.transaction do
        claim.update!(status: :approved, decided_at: Time.current, adjudicator: current_user)
        claim.mic.mic_owners.find_or_create_by!(user_id: claim.claimant_user_id) do |mp|
          mp.role = claim.role
          mp.accepted_at = Time.current
        end
        if claim.role_owner?
          claim.mic.update!(lead_owner_user_id: claim.claimant_user_id, claimed_at: Time.current)
        end
        claim.mic.mic_edits.create!(editor_user_id: current_user.id, source: :admin, field: "claim",
                                     new_value: "approved")
      end
      redirect_to mics_captain_hub_path(@hub.slug, anchor: "queue-top"), notice: "Approved claim."
    end

    def reject_claim
      claim = scoped_claim!
      claim.update!(status: :rejected, decided_at: Time.current, adjudicator: current_user,
                    reason: params[:reason])
      redirect_to mics_captain_hub_path(@hub.slug, anchor: "queue-top"), notice: "Rejected claim."
    end

    def resolve_challenge
      challenge = scoped_challenge!
      outcome = params[:outcome].to_s
      MicChallenge.transaction do
        challenge.update!(status: outcome, decided_at: Time.current, adjudicator: current_user)
        case outcome
        when "replaced"
          challenge.mic.mic_owners.where(user_id: challenge.target_user_id).destroy_all if challenge.target_user_id
          challenge.mic.mic_owners.find_or_create_by!(user_id: challenge.challenger_user_id) do |mp|
            mp.role = :owner
            mp.accepted_at = Time.current
          end
          challenge.mic.update!(lead_owner_user_id: challenge.challenger_user_id)
        when "co_produce"
          challenge.mic.mic_owners.find_or_create_by!(user_id: challenge.challenger_user_id) do |mp|
            mp.role = :co_owner
            mp.accepted_at = Time.current
          end
        end
      end
      redirect_to mics_captain_hub_path(@hub.slug, anchor: "queue-top"), notice: "Challenge resolved (#{outcome})."
    end

    def approve_suggestion
      suggestion = scoped_suggestion!
      suggestion.update!(status: :approved, decided_at: Time.current, adjudicator: current_user)
      suggestion.mic.mic_edits.create!(editor_user_id: current_user.id, source: :suggestion,
                                        field: "suggestion", new_value: "approved",
                                        note: suggestion.note.to_s)
      redirect_to mics_captain_hub_path(@hub.slug, anchor: "queue-top"), notice: "Suggestion approved."
    end

    def reject_suggestion
      suggestion = scoped_suggestion!
      suggestion.update!(status: :rejected, decided_at: Time.current, adjudicator: current_user)
      redirect_to mics_captain_hub_path(@hub.slug, anchor: "queue-top"), notice: "Suggestion rejected."
    end

    private

    # ── scoped_* helpers: return the requested record only if the
    # underlying Mic belongs to a venue rolled up to this hub. Otherwise
    # we 403 — prevents a captain from acting on another hub's items
    # by ID-guessing in the URL.
    def scoped_mic!
      mic = Mic.find(params[:id])
      head(:forbidden) and return unless mic.venue&.city_hub_id == @hub.id
      mic
    end

    def scoped_claim!
      claim = MicClaim.find(params[:id])
      head(:forbidden) and return unless claim.mic.venue&.city_hub_id == @hub.id
      claim
    end

    def scoped_challenge!
      ch = MicChallenge.find(params[:id])
      head(:forbidden) and return unless ch.mic.venue&.city_hub_id == @hub.id
      ch
    end

    def scoped_suggestion!
      sug = MicSuggestion.find(params[:id])
      head(:forbidden) and return unless sug.mic.venue&.city_hub_id == @hub.id
      sug
    end

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
