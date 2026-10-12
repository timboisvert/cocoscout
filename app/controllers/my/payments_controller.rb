# frozen_string_literal: true

module My
  class PaymentsController < ApplicationController
    before_action :require_user
    before_action :set_person

    def index
      # What's coming (by where it stands, line by line) and what's been paid
      # (each payment with what it covered): MyPaymentsSummary.
      @summary = MyPaymentsSummary.new(@person)

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
        @paid_down = MyPaymentsSummary.offset_paid_down(@share)
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

    # Shares this person's contracts settled by offset: their charges ate the
    # whole share, so nothing was deposited (ContractorPayoutRunService
    # .settle_as_wash!).
    def offset_shares
      ContractPayment.joins(contract: :contractor).where(contractors: { person_id: @person.id })
                     .direction_outgoing.status_paid.where(payment_method: "offset")
    end


    # The app opens Stripe in its own secure sheet, which has none of the
    # app's cookies, so Stripe sends it back by way of /app/return instead of
    # straight to a signed-in page. An expired link lands on Payment Settings
    # to start again.
    def start_bank_onboarding
      return_url, refresh_url = if turbo_native_app?
        [ app_return_url(to: my_payments_connect_return_path), app_return_url(to: my_payments_setup_path) ]
      else
        [ my_payments_connect_return_url, my_payments_connect_refresh_url ]
      end
      url = StripeConnectService.new(@person).onboarding_link(return_url: return_url, refresh_url: refresh_url)
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
