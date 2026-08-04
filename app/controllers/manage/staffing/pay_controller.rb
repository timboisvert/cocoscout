# frozen_string_literal: true

module Manage
  module Staffing
    # Staff pay run: a Gusto-style hours grid. The manager enters hours (and any
    # bonus / reimbursement / tips) per staff member; submitting builds a
    # PayoutBatch and pays everyone with a connected bank through Stripe Connect.
    class PayController < Manage::ManageController
      before_action :ensure_org_owner_or_manager

      def new
        all_members = payable_staff
        # Hidden from the grid by default: members excluded in Staffing settings
        # (e.g. salaried managers) and inactive members. Both stay revealable
        # one-by-one from the list at the bottom for one-off payments — and go
        # back to hidden on the next visit.
        @hidden_staff_members = all_members.select { |m| m.inactive? || m.excluded_from_pay? }
        @staff_members = all_members - @hidden_staff_members
        @payday = Date.current
        # Approved (signed-off, unpaid) entries per person — listed with
        # checkboxes in each person's Hours modal, and what the submit-time
        # "missing hours" checker compares against. Hours must be approved on
        # the Approve Hours queue before they're payable.
        @approved_entries_by_person = Current.organization.staff_time_entries.approved
                                             .includes(:house_role, shift_assignment: { shift: :house_role })
                                             .chronological
                                             .group_by(&:person_id)
        # Each member's qualified roles with resolved rates — ad-hoc hours are
        # priced by the role they were worked as, not a single per-person rate.
        @role_rates_by_member = all_members.each_with_object({}) do |m, h|
          h[m.id] = m.staff_role_qualifications.filter_map do |q|
            q.house_role && { role: q.house_role, rate_cents: m.rate_cents_for(q.house_role).to_i }
          end
        end
        @draft = PayDraft.read(Current.organization)
      end

      # Server-side draft autosave of the whole pay form (opaque JSON blob).
      def save_draft
        PayDraft.write(Current.organization, params[:draft].to_s)
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

        # The pay date is the day the manager plans to fund & pay — it can't be
        # in the past (the client flags this too; this is the backstop).
        payday = parse_payday
        if payday < Date.current
          redirect_to manage_staffing_pay_path, alert: "That pay date has passed — pick today or a later date." and return
        end

        result = StaffPayRunService.add_lines!(
          organization: Current.organization, created_by: Current.user,
          lines: lines, payday: payday
        )

        if result.added.zero?
          redirect_to manage_staffing_pay_path, alert: "Nothing to add — enter hours or an amount for at least one person." and return
        end

        PayDraft.clear(Current.organization)
        redirect_to manage_payout_batch_path(result.batch),
                    notice: "Added #{helpers.pluralize(result.added, 'person')} to your staff payout run. Fund and pay it when you're ready."
      end

      private

      # All members, active AND inactive — the grid shows active/non-excluded by
      # default and keeps the rest revealable for one-off payments.
      def payable_staff
        Current.organization.organization_staff_members
               .includes(:person, staff_role_qualifications: :house_role)
               .order("people.name").references(:person).to_a
      end

      # Turn the submitted grid into StaffPayRunService line hashes, keeping only
      # rows with something to pay.
      def parse_lines
        rows = params[:lines].is_a?(ActionController::Parameters) ? params[:lines].to_unsafe_h : {}
        # Not scoped to active: inactive/excluded members can be revealed on the
        # grid for one-off payments, and their rows must survive the submit.
        members = Current.organization.organization_staff_members.where(id: rows.keys).index_by(&:id)

        rows.filter_map do |id, row|
          member = members[id.to_i]
          next unless member

          line = {
            staff_member: member,
            # Ad-hoc "hours|role_id" pairs from the Hours modal — each line is
            # priced at its own role's rate. Roles resolve against the org so a
            # forged id can't smuggle in another org's rate.
            adhoc: parse_adhoc(row),
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
            adhoc: line[:adhoc], time_entry_ids: line[:time_entry_ids]
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

      # Ad-hoc worked-hours lines: "hours|role_id" pairs from the Hours modal.
      # Also accepts the legacy single hours + house_role_id shape (old drafts).
      def parse_adhoc(row)
        pairs = Array(row[:adhoc]).filter_map do |pair|
          hours, role_id = pair.to_s.split("|", 2)
          hours = hours.to_f
          next if hours <= 0

          { hours: hours, house_role: Current.organization.house_roles.find_by(id: role_id) }
        end
        return pairs if pairs.any?

        legacy_hours = row[:hours].to_f
        return [] unless legacy_hours.positive?

        [ { hours: legacy_hours, house_role: Current.organization.house_roles.find_by(id: row[:house_role_id]) } ]
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
