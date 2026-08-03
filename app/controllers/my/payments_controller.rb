# frozen_string_literal: true

module My
  class PaymentsController < ApplicationController
    before_action :require_user
    before_action :set_person

    def index
      # A simple log of everything this person has been paid, across all shows.
      paid_items = ShowPayoutLineItem
        .where(payee: @person)
        .joins(show_payout: :show)
        .where(show_payouts: { status: "paid" })
        .includes(show_payout: { show: :production })
        .order("show_payout_line_items.paid_at DESC NULLS LAST, shows.date_and_time DESC")

      @total_received = paid_items.to_a.sum(&:amount)

      # What they're owed now, itemized straight from the ledger earnings (the
      # source of the balance), with a friendly label per line. Anything already
      # paid out shows as a reconciling deduction so it nets to the balance.
      net_cents = @person.payout_balance_cents
      earnings = PayoutLedgerEntry.where(payee: @person, entry_type: "earning")
                                  .includes(:organization).order(occurred_at: :desc).to_a
      @owed_lines = earnings.reject { |e| e.amount_cents.zero? }.map do |e|
        { label: earning_label(e), org: e.organization&.name, cents: e.amount_cents }
      end
      # payouts + advances already netted against those earnings.
      @already_paid_out_cents = earnings.sum(&:amount_cents) - net_cents

      # Hours still awaiting a manager's approval — estimated at their rate,
      # included in the total but clearly flagged as not yet approved.
      # No .active filter: hours worked before someone was marked inactive still
      # price at their rate (an inactive membership keeps its rates).
      members = OrganizationStaffMember.where(person_id: @person.id).index_by(&:organization_id)
      pending = StaffTimeEntry.where(person_id: @person.id).pending
                              .includes(:organization, shift_assignment: { shift: :house_role })
                              .chronological.to_a
      @pending_lines = pending.map do |e|
        member = members[e.organization_id]
        rate = member ? member.rate_cents_for(e.shift&.house_role).to_i : 0
        { label: pending_label(e), org: e.organization&.name, cents: (rate * e.hours.to_f).round }
      end
      @pending_total_cents = @pending_lines.sum { |l| l[:cents] }

      # Total owed includes the pending (awaiting-approval) estimate.
      @to_be_paid_cents = net_cents + @pending_total_cents

      @pagy, @payment_history = pagy(paid_items, limit: 25)
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
