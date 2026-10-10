# frozen_string_literal: true

module My
  class PaymentsController < ApplicationController
    before_action :require_user
    before_action :set_person

    def index
      # Payment history: one row per actual payment this person received — a
      # payout-run deposit (one bank transfer, possibly bundling several
      # earnings), a show payout hand-paid outside CocoScout, or staffing hours
      # settled outside CocoScout. Several in a week is normal — they're paid
      # different ways, and each is its own receipt.
      @payment_history = payment_history_rows

      # Tax documents: the W-9 they've given (or owe) each org they're on
      # staff at. 1099s will land here too.
      @tax_memberships = OrganizationStaffMember.active
                                                .where(person_id: Current.user.people.active.select(:id))
                                                .includes(:w9_submissions, organization: :tax_setting)
                                                .select { |m| m.w9_received? || m.needs_w9? }
                                                .sort_by { |m| m.organization.name.to_s.downcase }
      # 1099s the org has sent (or filed) for this person. Only visible after
      # delivery — a draft belongs to the payer.
      person_ids = Current.user.people.active.pluck(:id)
      @person_1099s = TaxForm1099.where(person_id: person_ids)
                                  .where(status: %w[delivered filed corrected])
                                  .includes(:organization).order(tax_year: :desc, created_at: :desc)
      @total_received = @payment_history.sum { |p| p[:cents] } / 100.0

      # What they're owed now, itemized straight from the ledger earnings (the
      # source of the balance), with a friendly label per line. Anything already
      # paid out shows as a reconciling deduction so it nets to the balance.
      net_cents = @person.payout_balance_cents
      earnings = PayoutLedgerEntry.where(payee: @person, entry_type: "earning")
                                  .includes(:organization, :source).order(occurred_at: :desc).to_a
      # Charges netted out of a share (a rehearsal, a service) sit under the
      # share they came out of, so the calculation shows: share, what was taken
      # out, what they get (Tim, 2026-10-10).
      taken = deductions_by_earning(earnings)
      @owed_lines = earnings.reject { |e| e.amount_cents.zero? }.map do |e|
        { label: earning_label(e), org: e.organization&.name, cents: e.amount_cents, date: earning_date(e),
          deductions: taken[e.id].map { |d| { label: d.deduction_label, cents: d.amount_cents } } }
      end
      # payouts + advances already netted against those earnings (the
      # deductions listed under their shares aren't payouts).
      @already_paid_out_cents = earnings.sum(&:amount_cents) + taken.values.flatten.sum(&:amount_cents) - net_cents

      # Hours still awaiting a manager's approval — estimated at their rate,
      # included in the total but clearly flagged as not yet approved.
      # No .active filter: hours worked before someone was marked inactive still
      # price at their rate (an inactive membership keeps its rates).
      # Qualifications carry the per-role rates every pending line is priced at;
      # without them each line loads its member's whole qualification set again.
      members = OrganizationStaffMember.where(person_id: @person.id)
                                       .includes(staff_role_qualifications: :house_role)
                                       .index_by(&:organization_id)
      pending = StaffTimeEntry.where(person_id: @person.id).pending
                              .includes(:organization, shift_assignment: { shift: :house_role })
                              .chronological.to_a
      @pending_lines = pending.map do |e|
        member = members[e.organization_id]
        cents = member ? member.amount_cents_for(e.effective_house_role, hours: e.hours) : 0
        { label: pending_label(e), org: e.organization&.name, cents: cents, date: e.started_at }
      end
      @pending_total_cents = @pending_lines.sum { |l| l[:cents] }

      # Total owed includes the pending (awaiting-approval) estimate.
      @to_be_paid_cents = net_cents + @pending_total_cents

      # Money already staged in payout runs — proof the org has taken action.
      # Submitted = the run is funded/funding/paying, so the money is moving and
      # only the bank's timeline remains; queued = sitting in a draft run that
      # goes out on its payday. Both still count in the owed balance (the
      # debiting ledger entry posts only when the transfer lands).
      #
      # "failed" counts too: on a funded run it means a transfer bounced and
      # will be retried automatically — from the payee's side the money is
      # still on its way, and "failed" is an internal state they must never
      # see (or worse, silently lose the "on its way" line they were emailed).
      run_items = PayoutBatchItem.where(payee: @person, status: %w[pending failed])
                                 .joins(:payout_batch)
                                 .where(payout_batches: { status: PayoutBatchService::UNSETTLED_BATCH_STATUSES })
                                 .includes(payout_contributions: :source, payout_batch: :organization)
                                 .order("payout_batches.created_at DESC")
      @submitted_run_items = run_items.select { |i| i.payout_batch.in_flight? }
      @queued_run_items = run_items.select { |i| i.payout_batch.open? }
    end

    # A receipt for one payment — everything it covered. Every lookup is scoped
    # to the signed-in person, so nobody can read someone else's receipt.
    def receipt
      case params[:kind]
      when "run"
        @item = PayoutBatchItem.where(payee: @person, status: "paid")
                               .includes(payout_batch: :organization).find(params[:id])
        @contributions = @item.payout_contributions.includes(:source).order(:created_at).to_a
      when "show"
        @line_item = ShowPayoutLineItem.where(payee: @person, manually_paid: true)
                                       .includes(show_payout: { show: :production }).find(params[:id])
      when "offset"
        @share = offset_shares.find(params[:id])
        @paid_down = offset_paid_down(@share)
        @still_owed = @share.contract.contract_payments.status_pending.direction_incoming
                            .where(settlement_method: "payout_deduction").to_a
      when "hours"
        @entry = StaffTimeEntry.where(person_id: @person.id).where.not(offline_paid_at: nil)
                               .includes(:organization, shift_assignment: { shift: :house_role }).find(params[:id])
        member = OrganizationStaffMember.find_by(person_id: @person.id, organization_id: @entry.organization_id)
        # Total received; when a reimbursement rode along, the receipt breaks
        # out wages vs reimbursement from the two components.
        @entry_wage_cents = @entry.offline_amount_cents ||
                            (member ? member.amount_cents_for(@entry.effective_house_role, hours: @entry.hours) : 0)
        @entry_reimbursement_cents = @entry.offline_reimbursement_cents.to_i
        @entry_amount_cents = @entry_wage_cents + @entry_reimbursement_cents
      else
        redirect_to my_payments_path and return
      end
      @kind = params[:kind]
    rescue ActiveRecord::RecordNotFound
      redirect_to my_payments_path, alert: "We couldn't find that payment."
    end

    def setup
      # Payment settings page: connect your bank (Stripe captures your legal name
      # during onboarding, so there's no name step here).
    end

    # Start (or resume) Stripe Connect bank onboarding.
    def connect_bank
      start_bank_onboarding
    end

    # Stripe redirects here when the onboarding link expires — hand back a fresh one.
    def connect_refresh
      start_bank_onboarding
    end

    # Stripe redirects here after the worker finishes (or exits) onboarding.
    def connect_return
      StripeConnectService.new(@person).sync_account
      # Keep each org's cached staff onboarding_state in step with the new bank
      # status, so "awaiting bank" clears wherever they connected it.
      OrganizationStaffMember.active.where(person_id: @person.id).find_each(&:refresh_onboarding_state!)
      notice = if @person.can_receive_payouts?
        "Your bank is connected — you're all set to get paid directly."
      else
        "Almost there — finish the remaining steps so you can get paid to your bank."
      end
      redirect_to my_payments_setup_path, notice: notice
    rescue StripeConnectService::Error
      redirect_to my_payments_setup_path, alert: "We couldn't confirm your bank setup. Please try again."
    end

    private

    # One hash per payment actually received, newest first. Three shapes of
    # payment, each its own receipt: run = a payout-run bank deposit (can bundle
    # several earnings); show = a show payout hand-paid outside CocoScout;
    # hours = staffing hours settled outside CocoScout (offline-marked).
    def payment_history_rows
      rows = []

      PayoutBatchItem.where(payee: @person, status: "paid")
                     .includes(payout_contributions: :source, payout_batch: :organization)
                     .find_each do |item|
        batch = item.payout_batch
        payable = item.payout_contributions.reject(&:excluded_from_payout)
        deductions = payable.select(&:deduction?)
        line_count = payable.size - deductions.size
        taken_out = deductions.sum(&:amount_cents).abs
        subtitle = [ ("#{line_count} items in this deposit" if line_count > 1),
                     ("after #{helpers.number_to_currency(taken_out / 100.0)} taken out" if taken_out.positive?) ].compact.join(", ")
        rows << { kind: "run", id: item.id, org: batch.organization&.name,
                  title: "#{batch.kind_label} · bank deposit",
                  subtitle: subtitle.presence,
                  cents: item.amount_cents, paid_at: item.paid_at, method: "stripe" }
      end

      # A share that went wholly toward what they owed: nothing was deposited,
      # but it's a payment all the same, and its receipt shows the working.
      offset_shares.includes(contract: :organization).find_each do |share|
        rows << { kind: "offset", id: share.id, org: share.contract.organization&.name,
                  title: share.contract.production_name.presence || share.contract.contractor_name,
                  subtitle: share.display_name,
                  cents: 0, offset_cents: (share.amount.to_d * 100).round,
                  paid_at: share.paid_date, method: "offset" }
      end

      # Hand-paid show lines only — lines settled through a payout run are
      # already covered by that run's deposit row above.
      ShowPayoutLineItem.where(payee: @person, manually_paid: true)
                        .includes(show_payout: { show: :production }).find_each do |li|
        show = li.show_payout&.show
        rows << { kind: "show", id: li.id, org: nil,
                  title: show&.production&.name || "Show payout",
                  # The manager's reference note rides along ("Zelle conf #1234") —
                  # it's often the only context the payee has for a hand-payment.
                  subtitle: [ show&.date_and_time&.strftime("%B %-d, %Y"), li.payment_notes.presence ].compact.join(" · "),
                  cents: (li.net_amount.to_d * 100).round, paid_at: li.paid_at || li.manually_paid_at,
                  method: li.payment_method }
      end

      staff_members = OrganizationStaffMember.where(person_id: @person.id)
                                             .includes(staff_role_qualifications: :house_role)
                                             .index_by(&:organization_id)
      StaffTimeEntry.where(person_id: @person.id).where.not(offline_paid_at: nil)
                    .includes(:organization, :house_role, shift_assignment: { shift: :house_role })
                    .find_each do |e|
        member = staff_members[e.organization_id]
        entry_cents = member ? member.amount_cents_for(e.effective_house_role, hours: e.hours) : 0
        hrs = ActiveSupport::NumberHelper.number_to_rounded(e.hours, precision: 2, strip_insignificant_zeros: true)
        rows << { kind: "hours", id: e.id, org: e.organization&.name,
                  title: e.offline_reimbursement_only? ? "Reimbursement" : "Staffing hours · #{hrs}h",
                  # The manager's "how it was paid" note (e.g. "Paid via Gusto")
                  # shows right on the row — it's the payee's only context for
                  # hours settled outside CocoScout.
                  subtitle: [ e.started_at&.strftime("%B %-d, %Y"), e.offline_payment_note.presence ].compact.join(" · "),
                  # The full amount handed over — wages plus any reimbursement.
                  cents: e.offline_total_cents || entry_cents, paid_at: e.offline_paid_at,
                  method: nil }
      end

      # Zero-dollar rows ($0 "mark done" lines, rate-less hours) are noise in a
      # payment log — nothing was received, so nothing to list.
      rows.reject! { |r| r[:cents].to_i <= 0 && r[:offset_cents].to_i <= 0 }

      rows.sort_by { |r| r[:paid_at]&.to_time || Time.at(0) }.reverse.first(100)
    end

    # Shares this person's contracts settled by offset: their charges ate the
    # whole share, so nothing was deposited (ContractorPayoutRunService
    # .settle_as_wash!).
    def offset_shares
      ContractPayment.joins(contract: :contractor).where(contractors: { person_id: @person.id })
                     .direction_outgoing.status_paid.where(payment_method: "offset")
    end

    # The charges an offset share paid down: settled by deduction on the same
    # run (the share's reference names it).
    def offset_paid_down(share)
      run_id = share.reference_number.to_s[/run #(\d+)/, 1]
      return [] unless run_id

      share.contract.contract_payments.direction_incoming.status_paid
           .where(payment_method: "payout_deduction", reference_number: "offset_run_#{run_id}").order(:due_date, :id).to_a
    end

    # Deduction ledger lines (a charge netted out of a share on a run), keyed
    # by the earning line of the share they came out of.
    def deductions_by_earning(earnings)
      by_item = PayoutLedgerEntry.where(payee: @person, entry_type: "adjustment", source_type: "PayoutContribution")
                                 .includes(source: :source).to_a.select { |a| a.source&.deduction? }
                                 .group_by { |a| a.source.payout_batch_item_id }
      taken = Hash.new { |h, k| h[k] = [] }
      return taken if by_item.empty?

      shares = earnings.select { |e| e.source.is_a?(PayoutContribution) }.group_by { |e| e.source.payout_batch_item_id }
      by_item.each do |item_id, lines|
        candidates = shares[item_id] || []
        lines.each do |line|
          contract_id = line.source.source.contract_id
          host = candidates.find { |e| e.source.source.is_a?(ContractPayment) && e.source.source.contract_id == contract_id } || candidates.first
          taken[host.id] << line.source if host
        end
      end
      taken
    end

    # When the work behind an earning line happened: the show's date for show
    # payouts, or the [oldest, newest] work-date range for a pay-run line
    # (tips worksheet days, tied worked-hours entries). Nil when undated.
    def earning_date(entry)
      case entry.source
      when ShowPayoutLineItem
        entry.source.show_payout&.show&.date_and_time
      when PayoutContribution
        entry.source.covered_date_range
      end
    end

    # Friendly label for an earning ledger line, enriched from its source where
    # possible (show name, staff-pay component, contract detail).
    def earning_label(entry)
      case entry.source
      when PayoutContribution
        entry.source.label.presence || entry.description
      when ShowPayoutLineItem
        entry.source.show_payout&.show&.production&.name.presence || "Show payout"
      else
        entry.description.presence || "Earnings"
      end
    end

    # Friendly label for a pending (awaiting-approval) time entry.
    def pending_label(entry)
      hrs = ActiveSupport::NumberHelper.number_to_rounded(entry.hours, precision: 2, strip_insignificant_zeros: true)
      role = entry.shift&.house_role&.name
      base = role ? "#{role} shift" : (entry.source == "manual" ? "Additional time" : "Shift")
      "#{base} · #{hrs}h"
    end

    def start_bank_onboarding
      url = StripeConnectService.new(@person).onboarding_link(
        return_url: my_payments_connect_return_url,
        refresh_url: my_payments_connect_refresh_url
      )
      redirect_to url, allow_other_host: true
    rescue StripeConnectService::Error => e
      redirect_to my_payments_setup_path, alert: "Couldn't start bank setup: #{e.message}"
    end

    def require_user
      return if Current.user

      redirect_to signin_path, alert: "Please sign in to view your payments."
    end

    def set_person
      @person = Current.user&.person
      return if @person

      redirect_to profile_path, alert: "Please complete your profile to view payments."
    end
  end
end
