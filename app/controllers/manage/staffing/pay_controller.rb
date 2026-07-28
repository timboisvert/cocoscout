# frozen_string_literal: true

module Manage
  module Staffing
    # Staff pay run: a Gusto-style hours grid. The manager enters hours (and any
    # bonus / reimbursement / tips) per staff member; submitting builds a
    # PayoutBatch and pays everyone with a connected bank through Stripe Connect.
    class PayController < Manage::ManageController
      before_action :ensure_org_owner_or_manager

      def new
        @staff_members = payable_staff
        @payday = Date.current
        # Approved-but-unpaid hours per person, for the "N hours" pull hint. Hours
        # must be approved on the Approve Hours queue before they're payable.
        @approved_hours_by_person = Current.organization.staff_time_entries.approved
                                           .group(:person_id).sum(:hours)
        @draft = PayDraft.read(Current.user, Current.organization)
      end

      # A person's approved (sign-off complete, unpaid) time entries, rendered
      # into the pull-hours modal frame.
      def time_entries
        person = staff_person
        member = Current.organization.organization_staff_members.active.find_by(person_id: person.id)
        render partial: "manage/staffing/pay/time_entries", locals: { entries: approved_entries_for(person), person: person, member: member }
      end

      # Server-side draft autosave of the whole pay form (opaque JSON blob).
      def save_draft
        PayDraft.write(Current.user, Current.organization, params[:draft].to_s)
        head :no_content
      end

      # Add the entered hours/amounts to the org's open staffing payout run
      # (accumulate model — funded and paid later from the payout-runs page, on
      # its own schedule). Everyone with a positive amount is added; people who
      # haven't connected a bank are flagged on the run and skipped at pay time.
      def create
        lines = parse_lines
        if lines.empty?
          redirect_to manage_staffing_pay_path, alert: "Enter hours or an amount for at least one person." and return
        end

        result = StaffPayRunService.add_lines!(
          organization: Current.organization, created_by: Current.user,
          lines: lines, payday: parse_payday
        )

        if result.added.zero?
          redirect_to manage_staffing_pay_path, alert: "Nothing to add — enter hours or an amount for at least one person." and return
        end

        PayDraft.clear(Current.user, Current.organization)
        redirect_to manage_payout_batch_path(result.batch),
                    notice: "Added #{helpers.pluralize(result.added, 'person')} to your staff payout run. Fund and pay it when you're ready."
      end

      private

      # Only a person who's on this org's staff (scopes the pull/approve to us).
      def staff_person
        staff_ids = Current.organization.organization_staff_members.pluck(:person_id)
        Person.where(id: staff_ids).find(params[:person_id])
      end

      def approved_entries_for(person)
        Current.organization.staff_time_entries.approved.for_person(person)
               .includes(shift_assignment: { shift: :house_role }).chronological
      end

      def payable_staff
        Current.organization.organization_staff_members.active
               .includes(:person).order("people.name").references(:person).to_a
      end

      # Turn the submitted grid into StaffPayRunService line hashes, keeping only
      # rows with something to pay.
      def parse_lines
        rows = params[:lines].is_a?(ActionController::Parameters) ? params[:lines].to_unsafe_h : {}
        members = Current.organization.organization_staff_members.active.where(id: rows.keys).index_by(&:id)

        rows.filter_map do |id, row|
          member = members[id.to_i]
          next unless member

          line = {
            staff_member: member,
            hours: row[:hours].to_f,
            bonus_cents: dollars_to_cents(row[:bonus]),
            reimbursement_cents: dollars_to_cents(row[:reimbursement]),
            tips_cents: dollars_to_cents(row[:tips]),
            cash_tips_cents: dollars_to_cents(row[:cash_tips]),
            tips_worksheet: parse_worksheet(row[:tips_sheet]),
            cash_tips_worksheet: parse_worksheet(row[:cash_tips_sheet]),
            notes: row[:notes].to_s.strip.presence,
            time_entry_ids: Array(row[:time_entry_ids])
          }
          worked = StaffPayRunService.worked_cents(
            organization: Current.organization, member: member,
            hours: line[:hours], time_entry_ids: line[:time_entry_ids]
          )
          gross = StaffPayRunService.payable_cents(
            worked_cents: worked,
            bonus_cents: line[:bonus_cents], reimbursement_cents: line[:reimbursement_cents], tips_cents: line[:tips_cents]
          )
          next if gross <= 0

          line
        end
      end

      def dollars_to_cents(value)
        return 0 if value.blank?

        (value.to_s.delete("$,").to_d * 100).round
      end

      # The tips / cash-tips worksheet arrives as hidden inputs, each a
      # "date|amount" string (see tips_worksheet_controller#useTotal). Turn it
      # into the per-day breakdown stored on the contribution; drop blank/zero
      # rows.
      def parse_worksheet(raw)
        Array(raw).filter_map do |entry|
          date, amount = entry.to_s.split("|", 2)
          cents = dollars_to_cents(amount)
          next if cents.zero?

          { "date" => date.to_s.strip.presence, "amount_cents" => cents }
        end
      end

      def parse_payday
        Date.parse(params[:payday].to_s)
      rescue ArgumentError, TypeError
        Date.current
      end
    end
  end
end
