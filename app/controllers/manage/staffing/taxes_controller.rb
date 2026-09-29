# frozen_string_literal: true

module Manage
  module Staffing
    # Staffing → Taxes. Every house staffer is an independent contractor, so the
    # org needs a signed W-9 from each one to send them a 1099. This page is the
    # to-do list for that: who's given one, who's been asked, who hasn't, and the
    # one-click "ask everyone who's missing" used to roll this out to people
    # who were already on staff.
    class TaxesController < Manage::ManageController
      before_action :ensure_org_owner_or_manager
      before_action :set_staff_member, only: %i[request_w9 w9]

      def index
        @tax_setting = Current.organization.tax_setting
        @members = Current.organization.organization_staff_members.active
                          .includes(:w9_submissions, organization: :tax_setting,
                                    person: [ :user, Manage::StaffingController::HEADSHOT_PRELOAD ])
                          .joins(:person).order("people.name").to_a
        @by_status = @members.group_by(&:w9_status)
        @missing = @members.select(&:needs_w9?)
        @requestable_missing = @missing.select { |m| StaffW9Requester.requestable?(m) }
      end

      # Ask a batch for their W-9: the checked people, or (all=1) everyone still
      # missing one. People who can't sign in yet are skipped and counted — their
      # onboarding invite covers it.
      def request_w9s
        scope = Current.organization.organization_staff_members.active
                       .includes(:w9_submissions, organization: :tax_setting, person: :user)
        scope = scope.where(id: Array(params[:staff_member_ids]).map(&:to_i)) unless params[:all].present?
        targets = scope.select(&:needs_w9?)

        sent = 0
        skipped = []
        targets.each do |member|
          if StaffW9Requester.requestable?(member)
            StaffW9Requester.call(staff_member: member, sender: Current.user)
            sent += 1
          else
            skipped << member.display_name
          end
        rescue StaffW9Requester::Error => e
          Rails.logger.info("[TaxesController#request_w9s] #{member.id}: #{e.message}")
          skipped << member.display_name
        end

        notice = sent.positive? ? "Asked #{helpers.pluralize(sent, 'person')} for their W-9." : "Nobody new to ask."
        if skipped.any?
          notice += " #{skipped.to_sentence} #{skipped.one? ? "hasn't" : "haven't"} set up an account yet — they'll be asked during onboarding."
        end
        redirect_to manage_staffing_taxes_path, notice: notice
      end

      # One person, from their row or their staff page, with the manager's
      # edited copy from the invite-preview modal.
      def request_w9
        StaffW9Requester.call(staff_member: @staff_member, sender: Current.user,
                              subject: params[:email_subject], body: params[:email_body])
        redirect_to return_path, notice: "Asked #{@staff_member.display_name} for their W-9 — we emailed and messaged them."
      rescue StaffW9Requester::Error => e
        redirect_to return_path, alert: e.message
      end

      # The signed W-9 as a PDF. It shows the full TIN, so every open is logged.
      def w9
        submission = @staff_member.current_w9
        return redirect_to(return_path, alert: "#{@staff_member.display_name} hasn't given you a W-9 yet.") unless submission

        TaxDocumentAccess.create!(organization: Current.organization, user: Current.user,
                                  w9_submission: submission, ip_address: request.remote_ip)
        pdf = Tax::W9Pdf.new(submission)
        send_data pdf.render, filename: pdf.filename, type: "application/pdf", disposition: "inline"
      end

      private

      # Asked from the staff page (from=staff) → back to its Taxes tab;
      # otherwise back to the Taxes page.
      def return_path
        if params[:from] == "staff"
          manage_edit_staffing_staff_path(@staff_member, anchor: "taxes")
        else
          manage_staffing_taxes_path
        end
      end

      def set_staff_member
        @staff_member = Current.organization.organization_staff_members.find(params[:id])
      end
    end
  end
end
