# frozen_string_literal: true

# Superadmin Finances: CocoScout's own money, every organization's money,
# the bills CocoScout sends, and the daily check against Stripe. Four pages
# and an org page:
#
#   /superadmin/finances                CocoScout: ours now, owed to us, owed back, profit by stream
#   /superadmin/finances/organizations  each org: held, in flight, billed, paid us
#   /superadmin/finances/subscriptions  plans, comps, bills, usage
#   /superadmin/finances/stripe         does it all match Stripe?
#   /superadmin/finances/orgs/:org_id   one org, all of it
module Superadmin
  class FinancesController < ApplicationController
    before_action :require_superadmin
    before_action :use_superadmin_sidebar

    def cocoscout
      @check = PlatformReconciliation.latest
      @give_back = UsageOverbilling.all_rows
      @finances = CocoScoutFinances.new(params[:period], give_back: @give_back)
      @money_now = CocoScoutMoneyNow.new(check: @check, give_back: @give_back)
      @monthly = CocoScoutFinances.monthly(give_back: @give_back)
      respond_to do |format|
        format.html
        format.csv do
          send_data ledger_csv(@finances.entries.includes(:organization).order(:occurred_at)),
                    filename: "cocoscout-ledger-#{@finances.period}-#{Date.current.iso8601}.csv", type: "text/csv"
        end
      end
    end

    # One month in full, for the month-by-month table's panel: where its
    # money came from and where it went. Loaded when the panel opens.
    def month
      @finances = CocoScoutFinances.new(params[:month].to_s, give_back: UsageOverbilling.all_rows)
      return head :not_found unless @finances.period == params[:month].to_s

      render partial: "superadmin/finances/month_detail", locals: { finances: @finances }
    end

    # Give back one bill that charged too much (a second bill for a month, or
    # more than the month's paid work): refunded to the card or bank it was
    # paid from, or (how=credit) taken off the organization's next bills.
    def give_back
      invoice = BillingInvoice.find(params[:id])
      how = give_back_how
      row = UsageOverbilling.row_for(invoice)
      unless row&.refundable_now?
        message = row&.lands_on ? "its payment is still landing (about #{row.lands_on.strftime('%b %-d')})" : "there's nothing to give back on it"
        redirect_to finances_path, alert: "#{invoice.organization.name}'s bill #{invoice.number} can't be given back yet: #{message}."
        return
      end

      note = UsageOverbilling.give_back!(row, how: how)
      done = how == "credit" ? "Credited #{helpers.usd(row.over_cents)} to #{invoice.organization.name}'s next bills, from bill #{invoice.number}." :
                               "Refunded #{helpers.usd(row.over_cents)} to #{invoice.organization.name} on bill #{invoice.number}. It reaches their card or bank in a few days."
      redirect_to finances_path, notice: note ? done : "Bill #{invoice.number} has already been given back."
    rescue Stripe::StripeError => e
      redirect_to finances_path, alert: "Giving back bill #{invoice.number} didn't go through: #{e.message}"
    end

    # Move money from CocoScout's own bank into its Stripe balance (a Stripe
    # top-up), to cover what the organizations' balances are owed. A bank
    # transfer, so it takes a few business days to become available; the
    # books count it as soon as Stripe shows it, which the check run right
    # after picks up.
    ADD_FUNDS_MAX_CENTS = 1_000_000

    def add_funds
      cents = (params[:amount].to_s.delete("$,").to_d * 100).round.to_i
      unless cents.between?(100, ADD_FUNDS_MAX_CENTS)
        redirect_to finances_path, alert: "Add between $1 and #{helpers.usd(ADD_FUNDS_MAX_CENTS)}."
        return
      end

      topup = Stripe::Topup.create(
        { amount: cents, currency: "usd", description: "Added from CocoScout's bank by #{Current.user&.email_address}" },
        { idempotency_key: "cocoscout-add-funds-#{Current.user&.id}-#{cents}-#{Time.current.strftime('%Y%m%d%H%M')}" }
      )
      PlatformCheckNowJob.perform_later
      lands = topup["expected_availability_date"] ? Time.zone.at(topup["expected_availability_date"]).strftime("%b %-d") : "in a few business days"
      redirect_to finances_path, notice: "Adding #{helpers.usd(cents)} from CocoScout's bank. Stripe expects it #{lands}; it counts toward the gap as soon as Stripe shows it (refresh in a minute)."
    rescue Stripe::StripeError => e
      redirect_to finances_path, alert: "Stripe didn't take the transfer: #{e.message} You can also add it in Stripe under Balances, Add to balance."
    end

    # Give back every bill that charged too much and can go now, the same way.
    def give_back_all
      how = give_back_how
      rows = UsageOverbilling.all_rows.select(&:refundable_now?)
      rows.each { |row| UsageGiveBackJob.perform_later(row.invoice.id, how) }
      verb = how == "credit" ? "Crediting" : "Refunding"
      redirect_to finances_path, notice: rows.any? ? "#{verb} #{helpers.pluralize(rows.size, 'bill')} (#{helpers.usd(rows.sum(&:over_cents))}). Refresh in a minute to see them go." :
                                                     "Nothing can be given back right now."
    end

    def organizations
      month = Date.current.beginning_of_month.beginning_of_day..Time.current
      ids = (OrgCashEntry.distinct.pluck(:organization_id) + BillingInvoice.distinct.pluck(:organization_id) +
             CocoScoutLedgerEntry.where.not(organization_id: nil).distinct.pluck(:organization_id) +
             Organization.where(comped_indefinitely: true).or(Organization.where(comped_until: Time.current..))
                         .or(Organization.where(subscription_status: SubscriptionSyncService::ACCESS_STATUSES)).pluck(:id)).uniq
      paid_us = CocoScoutLedgerEntry.where(organization_id: ids, occurred_at: month, entry_type: CocoScoutLedgerEntry.types_in(:income))
                                    .group(:organization_id).sum(:amount_cents)
      unpaid = BillingInvoice.unpaid.where(organization_id: ids).group(:organization_id).sum(:amount_remaining_cents)
      @rows = Organization.where(id: ids).order(:name).map do |org|
        summary = OrgMoneySummary.new(org)
        { organization: org, held_cents: summary.held_cents, available_cents: summary.balance.available_cents,
          in_flight_cents: summary.in_flight.sum(&:cents), paid_us_cents: paid_us[org.id].to_i, unpaid_cents: unpaid[org.id].to_i }
      end
    end

    def subscriptions
      @orgs = Organization.where(comped_indefinitely: true).or(Organization.where(comped_until: Time.current..))
                          .or(Organization.where.not(subscription_status: [ nil, "" ]))
                          .or(Organization.where.not(staffing_subscription_id: nil))
                          .order(:name).to_a
      month = Date.current
      @usage = @orgs.index_with do |org|
        { performers: PerformerActivation.where(organization: org).for_month(month).count,
          staff: StaffActivation.where(organization: org).for_month(month).count }
      end
      @last_invoices = BillingInvoice.where(organization_id: @orgs.map(&:id)).newest_first.group_by(&:organization_id)
      paying = @orgs.select { |o| !o.comped? && (o.pro_on_monthly_bill? || o.subscription_status.in?(SubscriptionSyncService::ACCESS_STATUSES)) }
      @mrr_cents = paying.sum { |o| !o.pro_on_monthly_bill? && o.subscription_interval == "year" ? (SubscriptionPlan::PRO_ANNUAL_CENTS / 12.0).round : SubscriptionPlan::PRO_MONTHLY_CENTS }
      @paying_count = paying.size
      @comped = @orgs.select(&:comped?)
      @past_due = @orgs.select { |o| o.subscription_status == "past_due" }
      @failed_invoices = BillingInvoice.where(organization_id: @orgs.map(&:id)).select(&:failed?)
    end

    def stripe_check
      @check = PlatformReconciliation.latest
      @history = PlatformReconciliation.newest_first.limit(30)
      @lines = StripeBalanceTransaction.needs_a_look.newest_first.includes(:organization).limit(200)
      @failed_webhooks = WebhookEvent.failed.order(updated_at: :desc).limit(50)
      @last_import_at = StripeBalanceTransaction.maximum(:updated_at)
      @opening = CocoScoutLedgerEntry.find_by(entry_type: "opening_difference")
      @recent = StripeBalanceTransaction.newest_first.includes(:organization).limit(50)
    end

    def run_check
      PlatformCheckNowJob.perform_later
      redirect_to finances_stripe_check_path, notice: "Checking Stripe now. Refresh in a minute for the result."
    end

    def explain_line
      row = StripeBalanceTransaction.find(params[:id])
      note = params[:note].to_s.strip
      if note.blank?
        redirect_to finances_stripe_check_path, alert: "Say what it was, so the next person knows."
        return
      end

      row.explain!(note: note, by: Current.user)
      PlatformReconciliationCheck.run!
      redirect_to finances_stripe_check_path, notice: "Explained. It now counts as CocoScout's own money."
    end

    def opening_difference
      row = PlatformReconciliationCheck.run!
      entry = CocoScoutLedgerBackfill.record_opening_difference!(row)
      PlatformReconciliationCheck.run!
      redirect_to finances_stripe_check_path,
                  notice: entry ? "Recorded #{helpers.number_to_currency(entry.amount_cents / 100.0)} as the opening difference." : "Nothing to record."
    end

    def organization
      @org = Organization.find(params[:org_id])
      @summary = OrgMoneySummary.new(@org)
      @statements = @org.org_statements.newest_first.limit(24)
    end

    def statement
      statement = OrgStatement.find(params[:id])
      return head :not_found unless statement.pdf.attached?

      send_data statement.pdf.download, filename: statement.filename, type: "application/pdf", disposition: "inline"
    end

    # CocoScout's invoice for any organization's bill, as the org sees it.
    def invoice
      bill = BillingInvoice.find(params[:id])
      send_data InvoicePdf.new(CocoScoutInvoice.document(bill)).render, filename: CocoScoutInvoice.filename(bill),
                                                                         type: "application/pdf", disposition: "inline"
    end

    # Make (or remake) a statement for a month without emailing it.
    def make_statement
      org = Organization.find(params[:org_id])
      month = Date.iso8601(params[:month].presence || Date.current.prev_month.beginning_of_month.iso8601)
      OrgStatementJob.perform_later(org.id, month.beginning_of_month.iso8601, email: false)
      redirect_to finances_org_detail_path(org_id: org.id), notice: "Making the #{month.strftime('%B %Y')} statement. Refresh in a moment."
    rescue Date::Error
      redirect_to finances_org_detail_path(org_id: params[:org_id]), alert: "Pick a month."
    end

    private

    def give_back_how
      params[:how] == "credit" ? "credit" : "refund"
    end

    def use_superadmin_sidebar
      @show_my_sidebar = false
      @show_manage_sidebar = false
      @show_manage_header_only = false
      @show_group_sidebar = false
      @show_account_sidebar = false
      @show_superadmin_sidebar = true
    end

    def ledger_csv(entries)
      require "csv"
      CSV.generate do |csv|
        csv << [ "Date", "Kind", "Organization", "Amount", "Description" ]
        entries.find_each do |entry|
          csv << [ entry.occurred_at.in_time_zone.to_date.iso8601, entry.label, entry.organization&.name,
                   format("%.2f", entry.amount_cents / 100.0), entry.description ]
        end
      end
    end
  end
end
