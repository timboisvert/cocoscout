# frozen_string_literal: true

module My
  # The W-9 someone gives each organization that pays them: its staff, and
  # since 2026-11-22 the performers, contract people and instructors it pays
  # personally. Reached from onboarding, the "share your tax info" prompt on
  # My Shifts / the dashboard, the W-9 request email and notification, and My
  # Payments. Submitting again (to update it) supersedes the old one; history
  # is kept. The year page shows what the organization has paid them this year
  # against the 1099 amount, with a plain explanation.
  class TaxFormsController < ApplicationController
    RETURN_TO = %w[onboarding payments].freeze

    before_action :require_user
    before_action :set_payee

    # The year with this organization (Tim, 2026-11-22): what it has paid
    # them, the W-9 request and 1099 lines, where their W-9 stands, and what
    # it all means, with links to the IRS's own pages.
    def year
      @tax_year = Time.current.year
      @paid_cents = Tax::YearEarnings.for(@organization, @tax_year)[@person.id]&.net_cents.to_i
      @threshold_cents = TaxForm1099.threshold_cents(@tax_year)
      @request_at_cents = PerformerW9Requester::REQUEST_AT_CENTS
      @existing = current_w9
      @w9_request = W9Request.find_by(organization: @organization, person: @person)
      @forms = @organization.tax_form_1099s.where(person: @person, status: %w[ready delivered filed corrected]).order(tax_year: :desc)
    end

    def w9
      @existing = current_w9
      @w9 = prefilled_submission
    end

    def submit_w9
      @existing = current_w9
      @w9 = W9Submission.new(w9_params.merge(
        organization: @organization,
        person: @person,
        organization_staff_member: @member,
        signed_at: Time.current,
        signed_ip: request.remote_ip,
        signed_user_agent: request.user_agent.to_s.first(255),
        e_delivery_consented_at: params[:e_delivery_consent] == "1" ? Time.current : nil
      ))

      unless params[:certify] == "1"
        @w9.errors.add(:base, "Please check the box to certify the information is correct.")
        return render :w9, status: :unprocessable_content
      end

      @w9.submit!
      redirect_to after_submit_path, notice: "Thanks — your W-9 is on file with #{@organization.name}."
    rescue ActiveRecord::RecordInvalid
      render :w9, status: :unprocessable_content
    end

    # Your own copy of your 1099-NEC for the year (Copy B).
    def form_1099
      form = @organization.tax_form_1099s
                     .where(person_id: @person.id, tax_year: params[:tax_year].to_i)
                     .where(status: %w[ready delivered filed corrected])
                     .order(created_at: :desc).first
      return redirect_to(my_payments_path, alert: "No 1099 is available for that year yet.") unless form

      pdf = Tax::Form1099NecPdf.new(form, copy: :recipient)
      send_data pdf.render, filename: pdf.filename, type: "application/pdf", disposition: "inline"
    end

    # Your own copy of the W-9 you signed.
    def w9_copy
      submission = current_w9
      return redirect_to(my_w9_path(@organization.id), alert: "You haven't filled in a W-9 for #{@organization.name} yet.") unless submission

      pdf = Tax::W9Pdf.new(submission)
      send_data pdf.render, filename: pdf.filename, type: "application/pdf", disposition: "inline"
    end

    private

    # Start from their last W-9 (minus the TIN, which is never sent back to the
    # browser), else from the name the org has on file for them.
    def prefilled_submission
      if @existing
        @existing.dup.tap do |w|
          w.tin = nil
          w.signature_name = nil
        end
      else
        name = @member && [ @member.first_name, @member.middle_initial, @member.last_name ].compact_blank.join(" ").presence
        name ||= @person.name
        W9Submission.new(legal_name: name, tax_classification: "individual", tin_type: "ssn")
      end
    end

    def w9_params
      params.require(:w9).permit(:legal_name, :business_name, :tax_classification, :llc_tax_class,
                                 :other_classification, :exempt_payee_code, :fatca_code,
                                 :address_line1, :address_line2, :city, :state, :zip,
                                 :tin_type, :tin, :subject_to_backup_withholding, :signature_name)
    end

    # Where they came from: back to onboarding or My Payments, else My Shifts
    # for staff and their year page for everyone else.
    def return_to
      params[:return_to].presence_in(RETURN_TO)
    end
    helper_method :return_to

    def after_submit_path
      case return_to
      when "onboarding" then my_onboarding_path(@organization.id)
      when "payments" then my_payments_path
      else @member ? my_shifts_path : my_tax_year_path(@organization.id)
      end
    end

    def current_w9
      @organization.w9_submissions.current.where(person: @person).order(signed_at: :desc).first
    end

    # Who they are to this organization, matched across every Person on their
    # account: an active staff member (same lookup as the staff-agreement
    # prompt), or someone it has paid personally or requested a W-9 from.
    def set_payee
      person_ids = Current.user.people.active.pluck(:id)
      @organization = Organization.find_by(id: params[:organization_id])
      @member = @organization && OrganizationStaffMember.active.find_by(organization: @organization, person_id: person_ids)
      @person = @member&.person
      @person ||= @organization && Person.where(id: person_ids).find do |person|
        W9Request.exists?(organization: @organization, person: person) ||
          PayoutLedgerEntry.where(organization: @organization, payee: person, entry_type: "payout").exists? ||
          Contractor.exists?(organization: @organization, person_id: person.id)
      end
      return if @person

      redirect_to my_dashboard_path, alert: "We couldn't find any payments to you from that organization."
    end

    def require_user
      return if Current.user

      redirect_to signin_path, alert: "Please sign in to fill out your W-9."
    end
  end
end
