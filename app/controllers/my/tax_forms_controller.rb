# frozen_string_literal: true

module My
  # The W-9 a staff member gives each organization they work for. Reached from
  # onboarding, the "share your tax info" prompt on My Shifts / the dashboard,
  # the W-9 request email, and My Payments. Submitting again (to update it)
  # supersedes the old one; history is kept.
  class TaxFormsController < ApplicationController
    RETURN_TO = %w[onboarding payments].freeze

    before_action :require_user
    before_action :set_membership

    def w9
      @existing = @member.current_w9
      @w9 = prefilled_submission
    end

    def submit_w9
      @existing = @member.current_w9
      @w9 = W9Submission.new(w9_params.merge(
        organization: @member.organization,
        person: @member.person,
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
      redirect_to after_submit_path, notice: "Thanks — your W-9 is on file with #{@member.organization.name}."
    rescue ActiveRecord::RecordInvalid
      render :w9, status: :unprocessable_content
    end

    # Your own copy of your 1099-NEC for the year (Copy B).
    def form_1099
      form = @member.organization.tax_form_1099s
                     .where(person_id: @member.person_id, tax_year: params[:tax_year].to_i)
                     .where(status: %w[ready delivered filed corrected])
                     .order(created_at: :desc).first
      return redirect_to(my_payments_path, alert: "No 1099 is available for that year yet.") unless form

      pdf = Tax::Form1099NecPdf.new(form, copy: :recipient)
      send_data pdf.render, filename: pdf.filename, type: "application/pdf", disposition: "inline"
    end

    # Your own copy of the W-9 you signed.
    def w9_copy
      submission = @member.current_w9
      return redirect_to(my_w9_path(@member.organization_id), alert: "You haven't filled in a W-9 for #{@member.organization.name} yet.") unless submission

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
        name = [ @member.first_name, @member.middle_initial, @member.last_name ].compact_blank.join(" ").presence || @member.person.name
        W9Submission.new(legal_name: name, tax_classification: "individual", tin_type: "ssn")
      end
    end

    def w9_params
      params.require(:w9).permit(:legal_name, :business_name, :tax_classification, :llc_tax_class,
                                 :other_classification, :exempt_payee_code, :fatca_code,
                                 :address_line1, :address_line2, :city, :state, :zip,
                                 :tin_type, :tin, :subject_to_backup_withholding, :signature_name)
    end

    # Where they came from: back to onboarding or My Payments, else My Shifts.
    def return_to
      params[:return_to].presence_in(RETURN_TO)
    end
    helper_method :return_to

    def after_submit_path
      case return_to
      when "onboarding" then my_onboarding_path(@member.organization_id)
      when "payments" then my_payments_path
      else my_shifts_path
      end
    end

    # The caller's active staff membership at this org, matched across every
    # Person on their account (same lookup as the staff-agreement prompt).
    def set_membership
      person_ids = Current.user.people.active.pluck(:id)
      @member = OrganizationStaffMember.active
                                       .find_by(organization_id: params[:organization_id], person_id: person_ids)
      return if @member

      redirect_to my_dashboard_path, alert: "We couldn't find a staff position for your account at that organization."
    end

    def require_user
      return if Current.user

      redirect_to signin_path, alert: "Please sign in to fill out your W-9."
    end
  end
end
