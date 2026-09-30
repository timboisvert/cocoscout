# frozen_string_literal: true

module Manage
  module Staffing
    # Staffing → Taxes. Every house staffer is an independent contractor, so the
    # org needs a signed W-9 from each one to send them a 1099. This page is the
    # to-do list for that: who's given one, who's been asked, who hasn't, and
    # "ask everyone who's missing" — used to roll this out to people who were
    # already on staff — which shows who gets it and the draft before sending.
    class TaxesController < Manage::ManageController
      before_action :ensure_org_owner_or_manager
      before_action :set_staff_member, only: %i[request_w9 w9 upload_w9]
      before_action :set_form_1099, only: %i[form_1099 update_1099 deliver_1099 mark_1099_filed correct_1099 void_1099]

      def index
        @tax_setting = Current.organization.tax_setting
        @members = Current.organization.organization_staff_members.active
                          .includes(:w9_submissions, organization: :tax_setting,
                                    person: [ :user, Manage::StaffingController::HEADSHOT_PRELOAD ])
                          .joins(:person).order("people.name").to_a
        @by_status = @members.group_by(&:w9_status)
        @missing = @members.select(&:needs_w9?)
        @requestable_missing = @missing.select { |m| StaffW9Requester.requestable?(m) }
        @w9_draft = StaffW9Requester.bulk_draft(organization: Current.organization) if @requestable_missing.any?

        # 1099 section — a year switcher, defaulting to the tax year the manager
        # is working toward right now.
        @tax_year = (params[:tax_year].presence || Tax::Calendar.working_tax_year).to_i
        @tax_years = tax_year_options
        @forms_by_person = Current.organization.tax_form_1099s.for_year(@tax_year).not_void
                                   .includes(:person, :w9_submission).index_by(&:person_id)
        @earnings = Tax::YearEarnings.for(Current.organization, @tax_year)
        # Rows for the 1099s table: every member who has a form for the year OR
        # was paid in the year (so people over the threshold with no form yet
        # still show up as "Generate").
        person_ids = (@forms_by_person.keys + @earnings.keys).uniq
        @person_1099_rows = Current.organization.organization_staff_members.active
                                    .where(person_id: person_ids)
                                    .includes(:person, :w9_submissions)
                                    .sort_by { |m| m.display_name.to_s.downcase }
        @nec_threshold_cents = TaxForm1099.threshold_cents(@tax_year)
      end

      # Ask a batch for their W-9, from the "Ask for W-9s" modal: the people
      # ticked there, each sent the manager's edited draft with their own first
      # name filled in. People who can't sign in yet are skipped and counted —
      # their onboarding invite covers it.
      def request_w9s
        ids = Array(params[:staff_member_ids]).map(&:to_i)
        return redirect_to(manage_staffing_taxes_path, alert: "Tick at least one person to ask.") if ids.empty?

        targets = Current.organization.organization_staff_members.active
                         .includes(:w9_submissions, organization: :tax_setting, person: :user)
                         .where(id: ids).select(&:needs_w9?)

        sent = 0
        skipped = []
        targets.each do |member|
          if StaffW9Requester.requestable?(member)
            StaffW9Requester.call(staff_member: member, sender: Current.user,
                                  subject: params[:email_subject], body: params[:email_body])
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

      # The signed W-9: the PDF of one filled in online, or the file a manager
      # uploaded. Either shows the full TIN, so every open is logged, and an
      # upload is streamed from here — never a storage link someone could keep.
      def w9
        submission = @staff_member.current_w9
        return redirect_to(return_path, alert: "#{@staff_member.display_name} hasn't given you a W-9 yet.") unless submission

        TaxDocumentAccess.create!(organization: Current.organization, user: Current.user,
                                  w9_submission: submission, ip_address: request.remote_ip)
        if submission.uploaded? && submission.document.attached?
          blob = submission.document.blob
          send_data blob.download, filename: blob.filename.to_s, type: blob.content_type, disposition: "inline"
        else
          pdf = Tax::W9Pdf.new(submission)
          send_data pdf.render, filename: pdf.filename, type: "application/pdf", disposition: "inline"
        end
      end

      # Record a W-9 the org already has (paper, or another system): the file
      # plus what a 1099 needs, typed in. It becomes their current W-9.
      def upload_w9
        upload = StaffW9Upload.new(staff_member: @staff_member, uploaded_by: Current.user, params: params[:w9])
        if upload.save
          redirect_to return_path, notice: "Saved #{@staff_member.display_name}'s W-9."
        else
          redirect_to return_path, alert: "Couldn't save that W-9: #{upload.error_sentence}."
        end
      end

      # ----- 1099-NECs -----------------------------------------------------

      def generate_1099s
        tax_year = params[:tax_year].to_i
        forms = TaxForm1099.generate_for_year!(organization: Current.organization, tax_year: tax_year, generated_by: Current.user)
        redirect_to manage_staffing_taxes_path(tax_year: tax_year),
                    notice: forms.any? ? "Generated #{helpers.pluralize(forms.size, '1099')} for #{tax_year}." : "Nobody needs a 1099 for #{tax_year} — no reportable payments on file."
      rescue ArgumentError => e
        redirect_to manage_staffing_settings_section_path(section: "taxes"), alert: e.message.upcase_first
      end

      # The PDF of a single 1099 — the payer's copy (Copy C, full TIN); it's for
      # the payer's own records. The recipient gets Copy B via their portal.
      def form_1099
        pdf = Tax::Form1099NecPdf.new(@form, copy: :payer)
        send_data pdf.render, filename: pdf.filename, type: "application/pdf", disposition: "inline"
      end

      def update_1099
        return redirect_back(fallback_location: manage_staffing_taxes_path, alert: "This 1099 has been sent — a change needs a correction, not an edit.") unless @form.editable?

        attrs = {
          adjustment_cents: dollar_field(params[:adjustment_dollars]),
          federal_withheld_cents: dollar_field(params[:federal_withheld_dollars]).abs,
          adjustment_note: params[:adjustment_note].to_s.strip.presence
        }
        attrs[:status] = "ready" if params[:mark_ready] == "1"
        if @form.update(attrs)
          redirect_to manage_staffing_taxes_path(tax_year: @form.tax_year), notice: "Updated #{@form.recipient_name}'s 1099."
        else
          redirect_back fallback_location: manage_staffing_taxes_path(tax_year: @form.tax_year), alert: @form.errors.full_messages.to_sentence
        end
      end

      # Send the recipient's copy: email + in-app message. The PDF is generated
      # from the form on delivery (electronic delivery).
      def deliver_1099
        return redirect_back(fallback_location: manage_staffing_taxes_path, alert: "This 1099 isn't ready to send yet.") unless @form.editable?
        unless @form.deliverable?
          return redirect_back(fallback_location: manage_staffing_taxes_path, alert: "This 1099 needs a W-9 on file with a real TIN before it can go out.")
        end

        StaffTaxFormDeliverer.call(form: @form, sender: Current.user)
        @form.mark_delivered!
        redirect_to manage_staffing_taxes_path(tax_year: @form.tax_year), notice: "Sent #{@form.recipient_name}'s 1099."
      end

      # Manager confirms they filed the batch with the IRS (e.g. IRIS upload).
      # A reference and notes are optional.
      def mark_1099_filed
        @form.mark_filed!(reference: params[:filing_reference], notes: params[:filing_notes])
        redirect_to manage_staffing_taxes_path(tax_year: @form.tax_year), notice: "Marked #{@form.recipient_name}'s 1099 as filed."
      end

      # Open a fresh correction that supersedes this one (see model). The old
      # form flips to "corrected" once the correction is delivered.
      def correct_1099
        original = @form
        TaxForm1099.transaction do
          member = Current.organization.organization_staff_members.find_by(person_id: original.person_id)
          correction = original.dup
          correction.assign_attributes(status: "draft", delivered_at: nil, filed_at: nil,
                                       filing_reference: nil, filing_notes: nil, corrects: original,
                                       generated_by: Current.user)
          # Refresh the recipient snapshot only if the member has a current W-9;
          # if they don't, keep the original's frozen snapshot rather than
          # clobbering it with "—" placeholders.
          TaxForm1099.snapshot_recipient_from(correction, member) if member&.current_w9
          correction.save!
          original.update!(status: "corrected") if original.status.in?(%w[delivered filed])
        end
        redirect_to manage_staffing_taxes_path(tax_year: original.tax_year),
                    notice: "Started a correction for #{original.recipient_name}. It'll be sent as a fresh CORRECTED 1099."
      end

      def void_1099
        return redirect_back(fallback_location: manage_staffing_taxes_path, alert: "Already filed 1099s can't be voided — use Correct instead.") if @form.filed_at.present?

        @form.void!
        redirect_to manage_staffing_taxes_path(tax_year: @form.tax_year), notice: "Voided that 1099 draft."
      end

      def iris_export
        tax_year = params[:tax_year].to_i
        forms = Current.organization.tax_form_1099s.for_year(tax_year).where(status: %w[ready delivered filed])
                        .includes(:w9_submission).to_a
        return redirect_to(manage_staffing_taxes_path(tax_year: tax_year), alert: "No 1099s are ready to export yet.") if forms.empty?

        exporter = Tax::IrisExport.new(forms)
        send_data exporter.to_csv, filename: exporter.filename(tax_year), type: "text/csv"
      end

      private

      def set_form_1099
        @form = Current.organization.tax_form_1099s.find(params[:id])
      end

      # A "$1,234.56" or "1234" string → cents (integer). Blank → 0. Negative
      # allowed for adjustments (the sign carries meaning).
      def dollar_field(value)
        return 0 if value.blank?

        (value.to_s.delete("$,").to_d * 100).round
      end

      # The years worth listing on the switcher: whichever have activity, plus
      # this year and the year we're currently reporting for. Newest first.
      def tax_year_options
        years = Current.organization.tax_form_1099s.distinct.pluck(:tax_year)
        years += [ Tax::Calendar.working_tax_year, Date.current.year ]
        years.uniq.sort.reverse
      end

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
