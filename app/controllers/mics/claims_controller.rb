# frozen_string_literal: true

module Mics
  class ClaimsController < AuthedBaseController
    before_action :load_mic

    def new
      @claim = MicClaim.new
    end

    def create
      @claim = @mic.mic_claims.build(claim_params)
      @claim.claimant = current_user
      @claim.status = :pending
      @claim.save!

      # Auto-approve when the proof email matches a venue's published
      # contact email. We keep it simple — exact match only.
      if auto_approve?(@claim)
        approve_claim!(@claim)
        redirect_to mics_owner_mic_path(@mic.slug),
                    notice: "Claim auto-approved — you're now the lead producer."
      else
        Mics::NotificationService.notify_claim(claim: @claim)
        redirect_to mics_claim_thanks_path(@mic.slug)
      end
    end

    def thanks
    end

    private

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
        @mic.mic_producers.create!(user: claim.claimant, role: claim.role, accepted_at: Time.current)
        @mic.update!(lead_producer_user_id: claim.claimant_user_id, claimed_at: Time.current) if claim.role_producer?
        @mic.mic_edits.create!(editor_user_id: current_user&.id, source: :system, field: "claim",
                                new_value: "auto_approved", note: "Auto-approved via email match")
      end
    end
  end
end
