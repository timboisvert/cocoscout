# frozen_string_literal: true

# Public, no-login page where a contract's counterparty reviews and signs it.
# Reached at /sign/contract/:token — the org sends that link however they like.
# The token is the only credential and names exactly one contract. Signing is an
# electronic agreement (acknowledge + type your name), stamped with time + IP.
class ContractSigningController < ApplicationController
  allow_unauthenticated_access
  before_action :set_contract
  # Best-effort: populate Current.user when the visitor happens to be signed in
  # (e.g. arriving from My Contracts), so we can greet a member by name — without
  # requiring a login.
  before_action :resume_session

  # Review + agree. Once executed, there's nothing to sign — send them to the
  # confirmation, which offers the signed PDF.
  def show
    return redirect_to sign_contract_success_path(token: @token) if @contract.signing_executed?

    @document = signable_document
    @signer_person = signed_in_signer_person
    # An amendment: say what actually changed, so signing is agreeing rather
    # than scrolling.
    @change_lines = amendment_change_lines
  end

  # Record the counterparty's agreement.
  def sign
    signer_name  = params[:signer_name].to_s.strip
    signer_email = params[:signer_email].to_s.strip.presence || @contract.contractor_email
    agreed       = params[:agree] == "1"

    if signer_name.blank? || !agreed
      @document = signable_document
      flash.now[:alert] = "Please type your full name and check the box to agree."
      render :show, status: :unprocessable_entity
      return
    end

    # If a signed-in member is signing (e.g. from My Contracts), link the
    # signature to their account.
    member_person = @contract.signer_member_person
    member_person = nil unless member_person && Current.user&.people&.exists?(id: member_person.id)

    if @contract.execute_by_signature!(signer_name: signer_name, signer_email: signer_email, request: request, person: member_person)
      redirect_to sign_contract_success_path(token: @token)
    else
      redirect_to sign_contract_path(token: @token)
    end
  end

  # Post-signing confirmation + (once the job finishes) the signed PDF.
  def success
    return redirect_to sign_contract_path(token: @token) unless @contract.signing_executed?

    @contract.ensure_signed_pdf!
    @signature = @contract.contractor_signature
  end

  private

  # The signed-in CocoScout member signing this contract, when the current user
  # is the contractor's linked person (or the email-matched member). Nil for an
  # anonymous / non-member signer — they type their name + email instead.
  def signed_in_signer_person
    return nil unless Current.user

    person = @contract.signer_member_person
    person if person && Current.user.people.exists?(id: person.id)
  end

  # The exact document the org sent — the snapshot the org signed, so both parties
  # agree to identical text. Falls back to a fresh render if somehow absent. The
  # snapshot is our own generated HTML, so render it as HTML (not escaped text).
  # Plain-English diff for an amendment awaiting signature. Empty for a first
  # signature — there's nothing to compare against.
  def amendment_change_lines
    version = @contract.current_version
    return [] if version.blank? || version.staged_amendment.blank?

    ContractAmendmentSummary.lines(@contract, version.staged_amendment)
  end

  def signable_document
    # The version's snapshot, never a live re-render — amending the deal must
    # not silently rewrite the document somebody is about to sign.
    snapshot = @contract.current_version&.content_snapshot.presence
    return snapshot.html_safe if snapshot

    @contract.render_signable_document
  end

  def set_contract
    @token = params[:token].to_s
    @contract = Contract.find_by(signing_token: @token) if @token.present?

    if @contract.nil? && @token.present?
      # Not the live token — but if a previous version went out with it, explain
      # that rather than 404ing. Signing a superseded document would be worse
      # still, so this never offers the new one; it points at the org instead.
      superseded = ContractVersion.find_by(signing_token: @token)
      if superseded&.superseded?
        @superseded_version = superseded
        @contract = superseded.contract
        @organization = @contract.organization
        render :superseded, status: :ok
        return
      end
    end

    return render :invalid, status: :not_found unless @contract

    @organization = @contract.organization
  end
end
