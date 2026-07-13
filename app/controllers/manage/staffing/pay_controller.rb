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
        render partial: "manage/staffing/pay/time_entries", locals: { entries: approved_entries_for(person), person: person }
      end

      # Server-side draft autosave of the whole pay form (opaque JSON blob).
      def save_draft
        PayDraft.write(Current.user, Current.organization, params[:draft].to_s)
        head :no_content
      end

      def create
        lines = parse_lines
        if lines.empty?
          redirect_to manage_staffing_pay_path, alert: "Enter hours or an amount for at least one person." and return
        end

        result = StaffPayRunService.build(
          organization: Current.organization, created_by: Current.user,
          lines: lines, payday: parse_payday
        )
        batch = result.batch

        if batch.items.empty?
          batch.destroy
          redirect_to manage_staffing_pay_path,
                      alert: skip_alert(result.skipped) and return
        end

        method = params[:funding_method].presence_in(PayoutBatchService::FUNDING_METHODS) || "ach"
        PayoutBatchService.fund!(batch, method: method)

        PayDraft.clear(Current.user, Current.organization)
        redirect_to manage_payout_batch_path(batch), notice: pay_notice(batch, result.skipped)
      rescue PayoutBatchService::Error => e
        redirect_to manage_staffing_pay_path,
                    alert: "Couldn't start the pay run: #{e.message}. Make sure your organization has a payment method set up to fund payouts."
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
            notes: row[:notes].to_s.strip.presence,
            time_entry_ids: Array(row[:time_entry_ids])
          }
          gross = StaffPayRunService.payable_cents(
            rate_cents: member.hourly_rate_cents, hours: line[:hours],
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

      def parse_payday
        Date.parse(params[:payday].to_s)
      rescue ArgumentError, TypeError
        Date.current
      end

      def pay_notice(batch, skipped)
        note = "Pay run started — #{helpers.number_to_currency(batch.total_cents / 100.0)} to #{batch.items.size} #{'person'.pluralize(batch.items.size)}."
        note += " #{skipped.size} skipped (no connected bank yet)." if skipped.any?
        note
      end

      def skip_alert(skipped)
        if skipped.any?
          "No one could be paid yet — #{skipped.size} #{'person'.pluralize(skipped.size)} still need to connect a bank."
        else
          "No one had an amount to pay."
        end
      end
    end
  end
end
