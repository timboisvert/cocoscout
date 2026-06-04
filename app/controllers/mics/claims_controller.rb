# frozen_string_literal: true

module Mics
  class ClaimsController < AuthedBaseController
    before_action :load_mic

    def new
      @claim = MicClaim.new
    end

    # One user-facing "claim" action that does the right thing under the
    # hood: a fresh MicClaim when the mic is unclaimed, or a MicChallenge
    # when the mic already has a lead owner.
    def create
      if @mic.claimed?
        file_challenge_from_claim_form
      else
        file_claim
      end
    end

    def thanks
    end

    private

    def file_claim
      @claim = @mic.mic_claims.build(claim_params)
      @claim.claimant = current_user
      @claim.status = :pending
      @claim.save!

      # Auto-approve when the proof email matches a venue's published
      # contact email. We keep it simple — exact match only.
      if auto_approve?(@claim)
        approve_claim!(@claim)
        redirect_to mics_owner_mic_path(@mic.slug),
                    notice: "Claim auto-approved — you're now the lead owner."
      else
        Mics::NotificationService.notify_claim(claim: @claim)
        redirect_to mics_claim_thanks_path(@mic.slug)
      end
    end

    # Map the unified claim form into a MicChallenge when the mic already
    # has an owner. The user just sees "submit a claim"; the data model
    # uses the existing challenge/dispute pipeline.
    def file_challenge_from_claim_form
      proof = (params.dig(:mic_claim, :proof) || {}).to_unsafe_h
      @challenge = @mic.mic_challenges.build(
        reason:   proof["note"].to_s.presence || "(no reason given)",
        evidence: {
          email: proof["email"].to_s,
          url:   proof["evidence_url"].to_s,
          note:  proof["note"].to_s
        }
      )
      @challenge.challenger = current_user
      @challenge.target_user_id = @mic.lead_owner_user_id
      @challenge.status = :pending
      @challenge.save!

      Mics::NotificationService.notify_challenge(challenge: @challenge)
      redirect_to mics_claim_thanks_path(@mic.slug)
    end

    def claim_params
      params.require(:mic_claim).permit(:role, proof: [ :email, :role, :evidence_url, :note ])
    end

    def auto_approve?(claim)
      email = claim.proof["email"].to_s.downcase.presence
      return false if email.blank?
      venue_email = @mic.venue.respond_to?(:contact_email) ? @mic.venue.contact_email.to_s.downcase : nil
      venue_email.present? && venue_email == email
    end

    def approve_claim!(claim)
      MicClaim.transaction do
        claim.update!(status: :approved, decided_at: Time.current, adjudicator: current_user)
        @mic.mic_owners.create!(user: claim.claimant, role: claim.role, accepted_at: Time.current)
        @mic.update!(lead_owner_user_id: claim.claimant_user_id, claimed_at: Time.current) if claim.role_owner?
        @mic.mic_edits.create!(editor_user_id: current_user&.id, source: :system, field: "claim",
                                new_value: "auto_approved", note: "Auto-approved via email match")
      end
    end
  end
end
